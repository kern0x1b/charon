-- The round trip's comparison and diagnostics (tools/gen/swift_roundtrip.lua), on our own fixture: the model of the fixture is the SDK's
-- side, and the other side is the same model with three known changes (one signature changed, one row dropped, one row added). A
-- compare that ignores a signature cell, or that loses a row, turns the test red. The compiler and the digester are not run here
-- (they need a toolchain); cmd_roundtrip runs them. Run: xmake l tests/gen/swift_roundtrip_test.lua

local TOOLS = path.join(os.scriptdir(), "..", "..", "tools")
local json = import("core.base.json")

function main()
    local model = import("gen.swift_model", {rootdir = TOOLS, anonymous = true})
    local roundtrip = import("gen.swift_roundtrip", {rootdir = TOOLS, anonymous = true})
    local failures = 0
    local function check(ok, label)
        if not ok then
            failures = failures + 1
            print("FAIL " .. label)
        end
    end

    local text = io.open(path.join(os.scriptdir(), "input", "fixtures", "swift", "model.json"), "rb"):read("a")
    local sdk_rows = assert(model.rows(json.decode(text).ABIRoot, "Fixture"))

    -- Ours is the same model with three changes: Box.describe() returns Int, Point.x is dropped, and a row nobody declared is added.
    local ours = {}
    for _, row in ipairs(sdk_rows) do
        if row.container == "Point" and row.name == "x" then
            -- dropped
        else
            local copy = {}
            for k, v in pairs(row) do
                copy[k] = v
            end
            if row.container == "Box" and row.name == "describe()" then
                copy.type = "Swift.Int"
            end
            table.insert(ours, copy)
        end
    end
    local extra = {}
    for k, v in pairs(sdk_rows[1]) do
        extra[k] = v
    end
    extra.usr, extra.container, extra.name, extra.kind = "s:7Fixture5ExtraV", "-", "Extra", "swift-struct"
    table.insert(ours, extra)

    local result = roundtrip.compare(sdk_rows, ours)
    check(result.sdk == #sdk_rows and result.ours == #ours, "the counts are the two sides' row counts")
    check(#result.missing == 1 and result.missing[1] == "swift-property Point.x", "a row the SDK has and ours lacks is missing")
    check(result.extra == 1, "a row ours has and the SDK lacks is extra")
    check(result.causes.type == 1 and string.find(result.examples.type, "Box.describe()", 1, true) ~= nil,
          "a changed result type is one cause, named by its row")
    check(result.equal == #sdk_rows - 2, "every matched row with no changed cell counts as equal")
    check(result.duplicates == 0, "no duplicate key is counted on a model without one")

    -- A duplicate key on our side is counted, not compared twice.
    local twice = {}
    for _, row in ipairs(sdk_rows) do
        table.insert(twice, row)
    end
    table.insert(twice, sdk_rows[1])
    check(roundtrip.compare(sdk_rows, twice).duplicates == 1, "a repeated key on our side is a duplicate")

    -- The compiler's diagnostics: the count of errors and the first one, in order; a note is not an error.
    local count, first = roundtrip.diagnostics("a.swift:1:2: error: boom\nb.swift: note: here\nc.swift:3:4: error: second\n")
    check(count == 2 and first == "a.swift:1:2: error: boom", "the first error and the error count are read in order")
    count, first = roundtrip.diagnostics("")
    check(count == 0 and first == nil, "no output is no error")

    print("swift roundtrip test: " .. (failures == 0 and "OK" or ("FAIL " .. failures)))
    if failures > 0 then
        os.exit(1)
    end
end
