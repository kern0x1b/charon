-- The Python oracle that is kept for `input` (tools/gen.py): its host probe passes the names to the constants oracle
-- (tools/gen-objc-constants-oracle.m) on the command line, as the oracle reads them, and builds the spec row of each name from the
-- value the host framework holds. Review r3 G2 found the callers still writing a names file, so `input` raised KeyError on any
-- framework with a probed string constant. This runs `gen.py input` on a fixture (a header, a ledger row each for a constant the
-- macOS Foundation exports and one it does not, and a constants table of the iOS cache with neither) and reads the rows it writes.
-- The expectations are the host's own: the value of NSMultipleUnderlyingErrorsKey is the string Foundation holds.
--
-- Needs python3, clang and a macOS Foundation: it is the one suite of this folder that runs the oracle. It is not part of the
-- build or of `gen`/`check`, which run no Python (clean_checkout_test). Run, from any folder: xmake l tests/gen/oracle_test.lua

local REPO = path.absolute(path.join(os.scriptdir(), "..", ".."))
local RUN = path.join(REPO, ".agent-work", "runs", "oracle-test")

local HEADER = table.concat({
    "FOUNDATION_EXPORT NSString * const NSMultipleUnderlyingErrorsKey;",
    "FOUNDATION_EXPORT NSString * const NSNoSuchNameForTheOracleTest;",
    ""}, "\n")

local LEDGER = table.concat({
    "kind\tlang\tapi\tintroduced\theader-introduced\tstatus\tneeds\treason",
    "constant\tobjc\tNSMultipleUnderlyingErrorsKey\t5.0\t5.0\tmissing\tcode+lift\tfixture",
    "constant\tobjc\tNSNoSuchNameForTheOracleTest\t5.0\t5.0\tmissing\tcode+lift\tfixture",
    ""}, "\n")

-- The iOS cache's constants table (symbol, value_kind, value): one unrelated row, so neither name has an iOS value.
local IOS_CONSTANTS = "symbol\tvalue_kind\tvalue\n_NSUnrelatedForTheOracleTest\tcfstring\tx\n"

-- The cells of a tab separated line.
local function cells(line)
    local out = {}
    for cell in (line .. "\t"):gmatch("([^\t]*)\t") do
        table.insert(out, cell)
    end
    return out
end

-- The rows of the spec table the oracle wrote, by api, each a table of its columns by name.
local function spec_rows(file)
    local rows, columns = {}, nil
    for line in io.lines(file) do
        if not columns then
            columns = cells(line)
        else
            local row, values = {}, cells(line)
            for i, name in ipairs(columns) do
                row[name] = values[i]
            end
            rows[row.api] = row
        end
    end
    return rows
end

local function cases()
    local failures = 0
    local function check(ok, label)
        if not ok then
            failures = failures + 1
            print("FAIL " .. label)
        end
    end

    local tree = path.join(RUN, "tree")
    local sdk = path.join(RUN, "sdk")
    local headers = path.join(sdk, "System", "Library", "Frameworks", "Foundation.framework", "Headers")
    os.mkdir(headers)
    os.mkdir(path.join(tree, "tools"))
    os.mkdir(path.join(RUN, "ledger"))
    io.writefile(path.join(headers, "Fixture.h"), HEADER)
    io.writefile(path.join(RUN, "ledger", "Foundation.tsv"), LEDGER)
    io.writefile(path.join(RUN, "constants.tsv"), IOS_CONSTANTS)
    -- the oracle compiles the probe from the tree's own tools folder
    os.cp(path.join(REPO, "tools", "gen-objc-constants-oracle.m"), path.join(tree, "tools", "gen-objc-constants-oracle.m"))

    local ok, message = true, ""
    try {
        function ()
            os.iorunv("python3", {path.join(REPO, "tools", "gen.py"), "input", "--tree", tree, "--framework", "Foundation",
                                  "--ledger", path.join(RUN, "ledger"), "--sdk", sdk, "--ios-constants", path.join(RUN, "constants.tsv")})
        end,
        catch {
            function (errors)
                ok = false
                message = tostring(errors)
            end
        }
    }
    check(ok, "gen.py input runs on the fixture (" .. message:sub(-300) .. ")")
    local spec = path.join(tree, "packages", "a", "apple-backports", "spec", "Foundation", "spec.sdk-26.2-headers.tsv")
    if ok and os.isfile(spec) then
        local rows = spec_rows(spec)
        local found, missing = rows.NSMultipleUnderlyingErrorsKey, rows.NSNoSuchNameForTheOracleTest
        check(found ~= nil and found.value_status == "found" and found.value == "NSMultipleUnderlyingErrorsKey",
              "a string constant the host exports is found, with the string the framework holds")
        check(found ~= nil and found.value_source == "host-macos", "its value comes from the host")
        check(missing ~= nil and missing.value_status == "missing", "a name the host does not export is missing, not an error")
    else
        check(false, "gen.py input wrote the spec table")
    end
    return failures
end

function main()
    os.tryrm(RUN)
    local failures, crashed = 0, nil
    try {
        function ()
            failures = cases()
        end,
        catch {
            function (errors)
                crashed = errors
            end
        }
    }
    os.tryrm(RUN)
    if crashed then
        raise("%s", tostring(crashed))
    end
    print("oracle test: " .. (failures == 0 and "OK" or ("FAIL " .. failures)))
    if failures > 0 then
        os.exit(1)
    end
end
