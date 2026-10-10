-- host.json_of: the JSON object xmake prints is the one that opens a line, so a message with a brace before it does not decide the
-- start; an output with no such object, or an object that does not decode, is an error that names what was asked and shows the head
-- of the output (review r4 F7). Pure Lua: it runs no program. Run: xmake l tests/gen/host_json_test.lua (exits 1 on failure).

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

function main()
    local failures, count = 0, 0
    local function check(ok, label)
        count = count + 1
        if not ok then
            failures = failures + 1
            print("FAIL " .. label)
        end
    end
    local host = import("gen.host", {rootdir = TOOLS, anonymous = true})

    local warned = "warning: unused {x}\n{\n    \"project\": {\"builddir\": \"build\"}\n}\n"
    check(host.json_of(warned, "xmake show").project.builddir == "build",
          "an object is decoded after a message that holds a brace")
    check(host.json_of("{\"targetfile\": \"a/b\"}", "xmake show -t decls").targetfile == "a/b",
          "an object at the start of the output is decoded")

    local message = error_of(function()
        host.json_of("no object here", "xmake show -t decls")
    end)
    check(message ~= nil and string.find(message, "xmake show -t decls", 1, true) ~= nil
          and string.find(message, "printed no JSON object", 1, true) ~= nil
          and string.find(message, "no object here", 1, true) ~= nil,
          "an output with no object names the request and shows the output")

    message = error_of(function()
        host.json_of("\n{ \"project\": ", "xmake show")
    end)
    check(message ~= nil and string.find(message, "does not decode", 1, true) ~= nil
          and string.find(message, "{ \"project\":", 1, true) ~= nil,
          "an object that does not decode shows the head of the output, not a decoder message alone")

    print("host_json test: " .. (failures == 0 and "OK" or ("FAIL " .. failures)) .. " (" .. count .. " checks)")
    if failures > 0 then
        os.exit(1)
    end
end
