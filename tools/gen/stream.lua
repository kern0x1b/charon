-- Reads the stdout of a program line by line through a pipe, with no temporary file (design-spec-driven.md D1). The program
-- runs under sh, which prints a sentinel line after it, carrying the program's exit status: the sentinel marks the end of
-- the stream, because a pipe read returns 0 both for "no data yet" and for the end.

import("core.base.pipe")
import("core.base.bytes")
import("core.base.process")

local SENTINEL = "\127END "
local CHUNK = 1 << 20

-- Calls each(line) for every line the program prints, in order, and returns the program's exit status. A partial last
-- line is passed on as it is; the program's stderr goes to ours.
function lines(program, args, each)
    local command = {"-c", '"$@"; printf "\\177END %d\\n" $?', "sh", program}
    for _, arg in ipairs(args) do
        table.insert(command, arg)
    end
    local rpipe, wpipe = pipe.openpair("AB", CHUNK)
    local child = process.openv("sh", command, {stdout = wpipe})
    wpipe:close()
    local buff = bytes(CHUNK)
    local carry, status = "", nil
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
            rpipe:wait(pipe.EV_READ, 100)
        else
            error("pipe read failed: " .. program)
        end
    end
    rpipe:close()
    child:wait(-1)
    child:close()
    return status
end
