import("fixtures")

local function object(folder, name, source)
    io.writefile(path.join(folder, name .. ".c"), source)
    fixtures.run(folder, "xcrun", {"clang", "-target", "armv7-apple-ios6.0", "-Wno-incompatible-sysroot", "-fvisibility=hidden", "-c", name .. ".c", "-o", name .. ".o"})
    return path.join(folder, name .. ".o")
end

function failures(opt)
    local backports = import("apple.backports", {rootdir = opt.modules, anonymous = true})
    local found = {}
    local folder = fixtures.scratch()
    local seven = object(folder, "seven", "__attribute__((visibility(\"default\"))) int arrived_seven = 7;\n__attribute__((visibility(\"default\"))) int also_seven(void) { return 7; }\nstatic int helper(void) { return 0; }\n")
    local eight = object(folder, "eight", "__attribute__((visibility(\"default\"))) int arrived_eight = 8;\n")
    local methods = object(folder, "methods", "static int added(void) { return 1; }\nint (*const hidden_table[])(void) = {added};\n")
    local mixed = object(folder, "mixed", "__attribute__((visibility(\"default\"))) int arrived_seven_too = 7;\n__attribute__((visibility(\"default\"))) int arrived_eight_too = 8;\n")
    local release_six = {}
    local release_seven = {_arrived_seven = true, _also_seven = true, _arrived_seven_too = true}
    local kept, reexported = backports.band(release_six, {seven, eight, methods})
    if #kept ~= 3 or #reexported ~= 0 then
        table.insert(found, string.format("a release that has none of the symbols must keep every object, not %d with %d re-exported", #kept, #reexported))
    end
    kept, reexported = backports.band(release_seven, {seven, eight, methods})
    table.sort(reexported)
    if table.concat(kept, ",") ~= table.concat({eight, methods}, ",") or table.concat(reexported, ",") ~= "_also_seven,_arrived_seven" then
        table.insert(found, "a release that exports every symbol of an object must drop the object and re-export its symbols, not keep " .. table.concat(kept, ",") .. " and re-export " .. table.concat(reexported, ","))
    end
    local errors = fixtures.refusal(function () backports.band(release_seven, {mixed}) end)
    if not errors or not errors:find("_arrived_seven_too", 1, true) or not errors:find("_arrived_eight_too", 1, true) then
        table.insert(found, "an object holding what a release exports beside what it does not must be refused naming both: " .. tostring(errors))
    end
    os.tryrm(folder)
    return found
end
