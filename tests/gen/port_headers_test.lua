-- The two outputs of the headers command (tools/gen/cmd_headers.lua): the faithful headers under D/Frameworks, as the SDK says, and the
-- port's under D/port/<release>/Frameworks, with the release rule applied to copies of the rows. On a hand-built IR and a fixture SDK
-- and registry, the port's mark is the release, the faithful mark is the SDK's, and the faithful headers are the same bytes whether or
-- not the registry names the declaration (the rule never reaches the rows the SDK's rendering reads). Run:
--   xmake l tests/gen/port_headers_test.lua
-- Pure Lua: the fixture lives under the system's temporary folder and is removed when the test ends.

local TOOLS = path.join(os.scriptdir(), "..", "..", "tools")

-- One IR row of the twenty-one columns: framework, kind, usr, container, name, side, header, line, availability, nullability, type,
-- params, then the columns the renderer reads and this fixture leaves empty.
local function row(kind, usr, name, avail, typ, params)
    local out = {"Fixture", kind, usr, "-", name, "-", "Fixture.h", "1", avail, "-", typ, params}
    for column = 13, 21 do
        out[column] = "-"
    end
    return out
end

-- One enumerator of an enum: its enum's name in the container column, its value in the value column (column 14).
local function constant(enum, name, value)
    local out = row("enumconst", "c:@E@" .. enum .. "@" .. name, name, "-", "-", "-")
    out[4], out[14] = enum, value
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
    local json = import("core.base.json")
    local failures = 0
    local function check(ok, label)
        if not ok then
            failures = failures + 1
            print("FAIL " .. label)
        end
    end

    local root = path.join(os.tmpdir(), "port-headers-test-" .. tostring(os.time()))
    local sdk = path.join(root, "sdk")
    write(path.join(sdk, "System", "Library", "Frameworks", "Fixture.framework", "Headers", "Fixture.h"), "")
    local ir_rows = {
        row("function", "c:@F@FixtureFn", "FixtureFn", "ios=13.0/-/-/0", "void", "(void)"),
        row("function", "c:@F@FixtureOther", "FixtureOther", "ios=13.0/-/-/0", "void", "(void)"),
        -- an NSInteger-like enum: its fixed type is a long, 64 bits in the IR's host and 32 on the port's armv7
        row("typedef", "c:@T@FixtureInteger", "FixtureInteger", "-", "long", "-"),
        row("enum", "c:@E@FixtureLimit", "FixtureLimit", "-", "FixtureInteger", "-"),
        constant("FixtureLimit", "FixtureLimitMax", "9223372036854775807"),
        constant("FixtureLimit", "FixtureLimitMin", "-9223372036854775808"),
        constant("FixtureLimit", "FixtureLimitWide", "4611686018427387904"),
    }
    local lines = {}
    for index, columns in ipairs(ir_rows) do
        lines[index] = table.concat(columns, "\t")
    end
    local ir = path.join(root, "full.tsv")
    write(ir, table.concat(lines, "\n") .. "\n")

    -- the same registry in two trees: one names FixtureFn (implemented from 6.0), the other names nothing
    local named = path.join(root, "named")
    local bare = path.join(root, "bare")
    write(path.join(named, "packages", "a", "apple-backports", "registry", "Fixture.json"),
          '{"framework": "Fixture", "entries": [{"api": "FixtureFn", "kind": "function", "status": "implemented", "minimum": "6.0"}]}')
    os.mkdir(path.join(bare, "packages", "a", "apple-backports", "registry"))

    local function header(out, release_folder)
        local dir = release_folder and path.join(out, "port", release_folder) or out
        return io.readfile(path.join(dir, "Frameworks", "Fixture.framework", "Headers", "Fixture.h"))
    end

    cmd.run({tree = named, ir = ir, sdk = sdk, out = path.join(root, "out-named")})
    cmd.run({tree = bare, ir = ir, sdk = sdk, out = path.join(root, "out-bare")})

    local faithful = header(path.join(root, "out-named"))
    local ported = header(path.join(root, "out-named"), "6.1.3")
    local bare_faithful = header(path.join(root, "out-bare"))

    check(faithful ~= nil and bare_faithful ~= nil, "the faithful header is written under Frameworks")
    check(ported ~= nil, "the port's header is written under port/<release>/Frameworks")
    check(faithful == bare_faithful, "the faithful headers are the same bytes with and without the registry")
    check(string.find(faithful or "", "introduced=13.0", 1, true) ~= nil and string.find(faithful or "", "FixtureFn", 1, true) ~= nil,
          "the faithful header keeps the SDK's mark for the declaration the registry names")
    check(string.find(ported or "", "introduced=6.1.3", 1, true) ~= nil, "the port's header carries the release for the implemented one")
    check(string.find(ported or "", "FixtureOther", 1, true) ~= nil, "a declaration no entry names is in the port's header too")
    -- the overlay maps the SDK's Headers folder to the port's file of the same name, and it is there beside the port folder
    local overlay = io.readfile(path.join(root, "out-named", "port", "6.1.3", "vfs.yaml"))
    local vfs = json.decode(overlay)
    local mapped = nil
    for _, dir in ipairs(vfs.roots) do
        if string.find(dir.name, "Fixture.framework/Headers", 1, true) then
            for _, file in ipairs(dir.contents) do
                if file.name == "Fixture.h" then mapped = file["external-contents"] end
            end
        end
    end
    check(mapped == path.absolute(path.join(root, "out-named", "port", "6.1.3", "Frameworks", "Fixture.framework", "Headers", "Fixture.h")),
          "the overlay maps the SDK's Fixture.h to the port's file")
    local other_mark = string.match(ported or "", "FixtureOther[^\n]*")
    check(other_mark ~= nil and string.find(other_mark, "introduced=13.0", 1, true) ~= nil,
          "a declaration no entry names keeps the SDK's mark in the port's header")
    -- the enum keeps its fixed type; the host's extremes of a long are the port's extremes (armv7 long is 32 bits), and the faithful
    -- header keeps the IR's values; a value no 32-bit long holds is left as the IR has it
    check(string.find(ported or "", "enum FixtureLimit : FixtureInteger {", 1, true) ~= nil, "the port's enum keeps its fixed type")
    check(string.find(ported or "", "FixtureLimitMax = 2147483647,", 1, true) ~= nil,
          "the port's enumerator at the long's maximum is 2147483647")
    check(string.find(ported or "", "FixtureLimitMin = -2147483648,", 1, true) ~= nil,
          "the port's enumerator at the long's minimum is -2147483648")
    check(string.find(ported or "", "FixtureLimitWide = 4611686018427387904,", 1, true) ~= nil,
          "a value the port's long cannot hold is written as the IR has it")
    check(string.find(faithful or "", "FixtureLimitMax = 9223372036854775807,", 1, true) ~= nil,
          "the faithful header keeps the IR's value of the enumerator")

    os.rm(root)
    print("port headers test: " .. (failures == 0 and "OK" or ("FAIL " .. failures)))
    if failures > 0 then
        os.exit(1)
    end
end

function main()
    run()
end
