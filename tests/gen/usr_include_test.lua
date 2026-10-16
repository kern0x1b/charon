-- The import of a usr/include header that no module map names (the 16.4 SDK's ObjectiveC: objc/NSObject.h and no ObjectiveC module map)
-- is the folder that holds the header, not the framework's name: a header that uses a typedef of NSObject.h imports <objc/NSObject.h>.
-- A framework the SDK holds as a framework is never resolved from usr/include. (A class is forward-declared, not imported.) Pure Lua: the fixture SDK lives under the system's temporary folder.
-- Run: xmake l tests/gen/usr_include_test.lua

local TOOLS = path.join(os.scriptdir(), "..", "..", "tools")

-- One IR row of the twenty-one columns: framework, kind, usr, container, name, side, header, line, availability, nullability, type,
-- params, then the columns the renderer reads and this fixture leaves empty.
local function row(framework, kind, usr, name, avail, typ, params, header)
    local out = {framework, kind, usr, "-", name, "-", header, "1", avail, "-", typ, params}
    for column = 13, 21 do
        out[column] = "-"
    end
    return out
end

local function write(filepath, text)
    os.mkdir(path.directory(filepath))
    local handle = assert(io.open(filepath, "wb"))
    handle:write(text)
    handle:close()
end

local function run()
    local cmd = import("gen.cmd_headers", {rootdir = TOOLS, anonymous = true})
    local failures = 0
    local function check(ok, label)
        if not ok then
            failures = failures + 1
            print("FAIL " .. label)
        end
    end

    local root = path.join(os.tmpdir(), "usr-include-test-" .. tostring(os.time()))
    local sdk = path.join(root, "sdk")
    write(path.join(sdk, "System", "Library", "Frameworks", "Fixture.framework", "Headers", "Fixture.h"), "")
    -- the usr/include folder holds the header and there is no module map for it
    write(path.join(sdk, "usr", "include", "objc", "NSObject.h"), "")
    local ir_rows = {
        row("Fixture", "function", "c:@F@FixtureObj", "FixtureObj", "ios=13.0/-/-/0", "FixtureAlias", "(void)", "Fixture.h"),
        row("ObjectiveC", "typedef", "c:@T@FixtureAlias", "FixtureAlias", "ios=2.0/-/-/0", "int", "-", "NSObject.h"),
    }
    local lines = {}
    for index, columns in ipairs(ir_rows) do
        lines[index] = table.concat(columns, "\t")
    end
    local ir = path.join(root, "full.tsv")
    write(ir, table.concat(lines, "\n") .. "\n")

    local out = path.join(root, "out")
    cmd.run({tree = root, ir = ir, sdk = sdk, out = out})
    local header = io.readfile(path.join(out, "Frameworks", "Fixture.framework", "Headers", "Fixture.h")) or ""
    check(string.find(header, "#import <objc/NSObject.h>", 1, true) ~= nil,
          "a header that uses a typedef of NSObject.h imports the folder that holds it, <objc/NSObject.h>")
    check(string.find(header, "ObjectiveC/NSObject.h", 1, true) == nil,
          "the framework's name is not the prefix of a header the SDK has under usr/include")

    os.rm(root)
    print("usr include test: " .. (failures == 0 and "OK" or ("FAIL " .. failures)))
    if failures > 0 then
        os.exit(1)
    end
end

function main()
    run()
end
