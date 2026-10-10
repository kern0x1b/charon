-- Reads the stdout of a program line by line through a pipe, with no temporary file (design-spec-driven.md D1). The program
-- runs under sh, which prints a sentinel line after it, carrying the program's exit status: the sentinel marks the end of
-- the stream, because a pipe read returns 0 both for "no data yet" and for the end.

import("core.base.pipe")
import("core.base.bytes")
import("core.base.process")

local SENTINEL = "\127END "
local CHUNK = 1 << 20
-- The milliseconds each wait for the child's exit lasts. child:wait(-1) can block for ever on a child that has already exited
-- (its exit is missed under load: measured as a stall of one run in a few hundred), so the exit is polled.
local CHILD_POLL = 100
-- The milliseconds of the check on each empty read. A wait of 0 blocks until the child exits (measured), so the check waits 1.
local CHILD_CHECK = 1

-- Calls each(line) for every line the program prints, in order, and returns the program's exit status. A partial last
-- line is passed on as it is; the program's stderr goes to ours.
function lines(program, args, each)
    local command = {"-c", '"$@"; printf "\\177END %d\\n" $?', "sh", program}
    for _, arg in ipairs(args) do
        table.insert(command, arg)
    end
    local rpipe, wpipe = pipe.openpair("AB", CHUNK)
    local child = process.openv("sh", command, {stdout = wpipe})
    assert(child, "could not start " .. program)
    wpipe:close()
    local buff = bytes(CHUNK)
    local carry, status = "", nil
    -- Set when the child has exited: whatever it wrote is still in the pipe, so one more read follows, and an empty read after
    -- that means the sentinel never came.
    local exited = false
    while not status do
        local n = rpipe:read(buff, CHUNK)
        if n > 0 then
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
            assert(not exited, "the program ended without its sentinel: " .. program)
            exited = child:wait(CHILD_CHECK) ~= 0
            if not exited then
                rpipe:wait(pipe.EV_READ, 100)
            end
        else
            error("pipe read failed: " .. program)
        end
    end
    rpipe:close()
    -- child:wait returns 0 while the child runs (the poll timed out), 1 once it has exited, -1 on error.
    local finished = 0
    repeat
        finished = child:wait(CHILD_POLL)
    until finished ~= 0
    assert(finished == 1, "could not wait for " .. program)
    child:close()
    return status
end
