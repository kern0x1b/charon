-- Reads the stdout of a program line by line through a pipe, with no temporary file (design-spec-driven.md D1). The program
-- runs under sh, which prints a sentinel line after it, carrying the program's exit status: the sentinel marks the end of
-- the stream, because a pipe read returns 0 both for "no data yet" and for the end. The standard error is read through a second
-- pipe when the caller asks for it (run), and is read in the same loop, so a program that writes a lot to it cannot block.

import("core.base.pipe")
import("core.base.bytes")
import("core.base.process")

local SENTINEL = "\127END "
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

-- The shared loop: calls each(line) for every stdout line in order, and returns the exit status and the standard error (empty
-- unless want_err: without it, the program's stderr goes to ours).
local function drive(program, args, each, want_err)
    local command = {"-c", '"$@"; printf "\\177END %d\\n" $?', "sh", program}
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
                if string.sub(line, 1, #SENTINEL) == SENTINEL then
                    status = tonumber(string.sub(line, #SENTINEL + 1))
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
            error("pipe read failed: " .. program)
        end
    end
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
