-- Reads the stdout of a program line by line through a pipe, with no temporary file (design-spec-driven.md D1). The program
-- runs under sh, which prints a sentinel line after it, carrying the program's exit status: the sentinel marks the end of
-- the stream, because a pipe read returns 0 both for "no data yet" and for the end. The standard error is read through a second
-- pipe when the caller asks for it (run), and is read in the same loop, so a program that writes a lot to it cannot block.

import("core.base.pipe")
import("core.base.bytes")
import("core.base.process")

local SENTINEL = "\127END "
-- The first line the wrapper prints is the program's process id: the program is started by an exec in a shell that prints its own id
-- first, so the id is the program's own and it is known before the program writes anything. An error path kills the program and what
-- it started by that id (kill_tree): a kill of the wrapper alone leaves them running (measured: an orphaned `sleep` outlived a raising
-- callback, review r3 G6).
local PID_LINE = "\127PID "
-- The checks, and the milliseconds between them, that kill_tree makes before it reports a process still running (one second at most):
-- a process just signalled can still show in ps for a moment, and a check that passes first time costs nothing more.
local KILL_CHECKS = 20
local KILL_WAIT = 50
local CHUNK = 1 << 20
-- The most bytes of standard error kept: the last ones, when a program writes more.
local ERROR_LIMIT = 1 << 20
-- The milliseconds each wait for the child's exit lasts. child:wait(-1) can block for ever on a child that has already exited
-- (its exit is missed under load: measured as a stall of one run in a few hundred), so the exit is polled.
local CHILD_POLL = 100
-- The milliseconds of the check on each empty read. A wait of 0 blocks until the child exits (measured), so the check waits 1.
local CHILD_CHECK = 1
-- After the exit: at most DRAIN_READS empty reads of DRAIN_WAIT milliseconds (a bound of 2 s) before the sentinel is declared missing;
-- and WAIT_ERRORS wait errors in a row are an error. Measured: output reported after an exit came within 2 s.
local DRAIN_READS = 200
-- The longest a stream may go without a byte before it is an error (a guard against a hang of the pipe; the program name is in the
-- message). Ten minutes: the slowest first line of the parser under load is well under it.
local STALL_LIMIT = 600000
local DRAIN_WAIT = 10
local WAIT_ERRORS = 100

-- Every process of the system: pid -> {ppid, state}, from one ps call.
local function processes()
    local all = {}
    for line in string.gmatch(os.iorunv("ps", {"-axo", "pid=,ppid=,state="}), "[^\n]+") do
        local pid, ppid, state = string.match(line, "^%s*(%d+)%s+(%d+)%s+(%S+)")
        if pid then
            all[pid] = {ppid = ppid, state = state}
        end
    end
    return all
end

-- Kills the process root and every process it started, then waits until none of them runs (a zombie has exited). Raises when one
-- still runs after KILL_CHECKS checks.
local function kill_tree(root)
    local all = processes()
    local ids, queue = {}, {root}
    while #queue > 0 do
        local id = table.remove(queue)
        table.insert(ids, id)
        for other, info in pairs(all) do
            if info.ppid == id then
                table.insert(queue, other)
            end
        end
    end
    os.execv("kill", table.join({"-KILL"}, ids), {try = true})
    local left = {}
    for _ = 1, KILL_CHECKS do
        left = {}
        local now = processes()
        for _, id in ipairs(ids) do
            if now[id] and string.sub(now[id].state, 1, 1) ~= "Z" then
                table.insert(left, id)
            end
        end
        if #left == 0 then
            return
        end
        os.sleep(KILL_WAIT)
    end
    raise("processes still running after the kill: " .. table.concat(left, " "))
end

-- The shared loop: calls each(line) for every stdout line in order, and returns the exit status and the standard error (empty
-- unless want_err: without it, the program's stderr goes to ours).
local function drive(program, args, each, want_err)
    -- The wrapper runs the program under a shell that prints its own process id, then execs the program (so the id is the program's);
    -- the wrapper waits for the program and prints the sentinel with its exit status.
    local command = {"-c", 'sh -c \'printf "\\177PID %d\\n" $$; exec "$0" "$@"\' "$@" <&0 & wait $! 2>/dev/null; printf "\\177END %d\\n" $?', "sh", program}
    for _, arg in ipairs(args) do
        table.insert(command, arg)
    end
    local rpipe, wpipe = pipe.openpair("AB", CHUNK)
    local options = {stdout = wpipe}
    local erpipe, ewpipe = nil, nil
    if want_err then
        erpipe, ewpipe = pipe.openpair("AB", CHUNK)
        options.stderr = ewpipe
    end
    local child = process.openv("sh", command, options)
    assert(child, "could not start " .. program)
    wpipe:close()
    if ewpipe then
        ewpipe:close()
    end
    local buff, ebuff = bytes(CHUNK), bytes(CHUNK)
    local carry, status = "", nil
    local program_pid = nil
    local errors = {}
    -- Reads what the program has written to its stderr so far (a read that finds nothing returns 0, and ends the read).
    local function read_errors()
        if erpipe == nil then
            return
        end
        while true do
            local m = erpipe:read(ebuff, CHUNK)
            if m <= 0 then
                break
            end
            table.insert(errors, ebuff:str(1, m))
        end
    end
    -- Once the child has exited, what it wrote is in the pipe; the reads that follow are bounded (DRAIN_READS of DRAIN_WAIT
    -- milliseconds each), and an empty read after the bound means the sentinel never came. A wait result of -1 is an error of the
    -- wait, not an exit: it is retried up to WAIT_ERRORS times.
    local exited, drained, wait_errors = false, 0, 0
    local last_byte = os.mclock()
    -- An error on the read path (a callback that raises, an assert, a pipe that fails) stops the program and the wrapper, and closes
    -- the pipes, before the error goes on (review r3 G6): a stream that raised leaves no program running. A kill that fails too is
    -- named with the error. The program is killed first, by its id: the wrapper's exit would leave it to launchd.
    local function stop(cause)
        local kill_errors = {}
        try {
            function()
                if program_pid then
                    kill_tree(tostring(program_pid))
                end
            end,
            catch {
                function(e)
                    table.insert(kill_errors, "killing " .. program .. " failed: " .. tostring(e))
                end
            }
        }
        try {
            function()
                child:kill()
            end,
            catch {
                function(e)
                    table.insert(kill_errors, "killing the wrapper of " .. program .. " failed: " .. tostring(e))
                end
            }
        }
        rpipe:close()
        if erpipe then
            erpipe:close()
        end
        raise(tostring(cause) .. (#kill_errors > 0 and ("; " .. table.concat(kill_errors, "; ")) or ""))
    end
    try {
        function()
            while not status do
                read_errors()
                local n = rpipe:read(buff, CHUNK)
                if n > 0 then
                    drained = 0
                    last_byte = os.mclock()
                    local text = carry .. buff:str(1, n)
                    local pos = 1
                    while not status do
                        local newline = string.find(text, "\n", pos, true)
                        if not newline then
                            break
                        end
                        local line = string.sub(text, pos, newline - 1)
                        local at, _, digits = string.find(line, SENTINEL .. "(%d+)$")
                        if at then
                            -- A program whose last line has no line feed leaves that text in front of the sentinel: it is passed on.
                            if at > 1 then
                                each(string.sub(line, 1, at - 1))
                            end
                            status = tonumber(digits)
                        elseif string.match(line, "^" .. PID_LINE .. "%d+$") then
                            program_pid = tonumber(string.sub(line, #PID_LINE + 1))
                        else
                            each(line)
                        end
                        pos = newline + 1
                    end
                    carry = string.sub(text, pos)
                elseif n == 0 then
                    assert(os.mclock() - last_byte < STALL_LIMIT, "no output from " .. program .. " for ten minutes")
                    if exited then
                        drained = drained + 1
                        assert(drained <= DRAIN_READS, "the program ended without its sentinel: " .. program)
                        rpipe:wait(pipe.EV_READ, DRAIN_WAIT)
                    else
                        local result = child:wait(CHILD_CHECK)
                        if result == 1 then
                            exited = true
                        elseif result == -1 then
                            wait_errors = wait_errors + 1
                            assert(wait_errors <= WAIT_ERRORS, "cannot observe the exit of " .. program)
                            rpipe:wait(pipe.EV_READ, DRAIN_WAIT)
                        else
                            rpipe:wait(pipe.EV_READ, 100)
                        end
                    end
                else
                    raise("pipe read failed: " .. program)
                end
            end
        end,
        catch {
            function(e)
                stop(e)
            end
        }
    }
    -- The sentinel comes after the program exited, so everything it wrote to stderr is in the pipe now.
    read_errors()
    rpipe:close()
    if erpipe then
        erpipe:close()
    end
    -- An exit the read loop already observed is not waited for again: that wait reaped the child, and a second wait never reports
    -- it (it spun forever in the doc and trace runs). child:wait returns 0 while the child runs, 1 once it has exited, -1 on error.
    if not exited then
        local finished = 0
        repeat
            finished = child:wait(CHILD_POLL)
        until finished ~= 0
        assert(finished == 1, "could not wait for " .. program)
    end
    child:close()
    local text = table.concat(errors)
    return status, string.sub(text, -ERROR_LIMIT)
end

-- Calls each(line) for every line the program prints, in order, and returns the program's exit status. A partial last
-- line is passed on as it is; the program's stderr goes to ours.
function lines(program, args, each)
    local status = drive(program, args, each, false)
    return status
end

-- Calls each(line) for every line the program prints, in order. Returns the program's exit status and its standard error (the
-- last ERROR_LIMIT bytes of it), which is read through a pipe and not shown.
function run(program, args, each)
    return drive(program, args, each, true)
end
