-- stream.lines and stream.run: the lines of a program in order, the exit status and standard error, a last line with no line feed,
-- and the kill of a program and of what it started when the callback raises (review r3 G6). It runs sh and sleep and reads ps; nothing
-- else. Run: xmake l tests/gen/stream_test.lua (exits 1 on failure).

local ROOT = path.absolute(path.join(os.scriptdir(), "..", ".."))
local TOOLS = path.join(ROOT, "tools")

-- The error text f raises, or nil when f returns.
local function error_of(f)
    local message = nil
    try {
        function()
            f()
        end,
        catch {
            function(e)
                message = tostring(e)
            end
        }
    }
    return message
end

-- The ps lines of the processes whose command contains text and that are not exited (state Z is an exited process not yet reaped).
local function running(text)
    local found = {}
    for line in string.gmatch(os.iorunv("ps", {"-axo", "pid=,state=,command="}), "[^\n]+") do
        if string.find(line, text, 1, true) and not string.find(line, "^%s*%d+%s+Z") then
            table.insert(found, line)
        end
    end
    return found
end

function main()
    local failures, count = 0, 0
    local function check(ok, label)
        count = count + 1
        if not ok then
            failures = failures + 1
            print("FAIL " .. label)
        end
    end
    local stream = import("gen.stream", {rootdir = TOOLS, anonymous = true})

    local got = {}
    local status = stream.lines("sh", {"-c", "echo a; echo b; printf c; exit 3"}, function(line)
        table.insert(got, line)
    end)
    check(status == 3, "lines: the exit status of the program is returned")
    check(table.concat(got, "|") == "a|b|c", "lines: lines come in order, and a last line with no line feed is passed on")

    local out = {}
    local run_status, err = stream.run("sh", {"-c", "echo out; echo err 1>&2; exit 4"}, function(line)
        table.insert(out, line)
    end)
    check(run_status == 4 and table.concat(out, "|") == "out" and err == "err\n",
          "run: the exit status and the standard error are returned, the standard output is the lines")

    -- The duration is drawn at random, so the ps line of this command (which names no duration) cannot match it.
    local secs = tostring(math.random(3000, 3999))
    local message = error_of(function()
        stream.lines("sh", {"-c", "echo first; sleep " .. secs}, function(line)
            raise("boom from the callback")
        end)
    end)
    check(message ~= nil and string.find(message, "boom from the callback", 1, true) ~= nil,
          "kill: the callback's error goes on")
    check(#running("sleep " .. secs) == 0, "kill: no sleep of the program is left running after the error")

    print("stream test: " .. (failures == 0 and "OK" or ("FAIL " .. failures)) .. " (" .. count .. " checks)")
    if failures > 0 then
        os.exit(1)
    end
end
