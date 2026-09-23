import("fixtures")

-- A band below an object's registry minimum neither keeps nor re-exports it, so the minimum of each
-- object is read from the entries its names answer to: a registry with one function at 4.3 and one
-- at 6.0, a helper only the 6.0 object calls, and an installer that exports nothing and that nothing
-- names. For 4.3 the 6.0 object and its helper are left out and the installer is kept with no floor;
-- for 6.0 all four are kept. An object holding entries of two minimums is refused, and so is one whose
-- entries place it below an object it calls: it would not link in between. An installer that
-- calls into the 6.0 object takes its minimum, as it links only where that object is carried: the band
-- for 6.0 keeps it and the band for 4.3 leaves it out.
local function range_step(backports, folder, found)
    local work = path.join(folder, "range")
    os.mkdir(path.join(work, "registry"))
    local entries = {}
    for _, row in ipairs({{"range_early", "4.3"}, {"range_late", "6.0"}, {"range_both_early", "4.3"}, {"range_both_late", "6.0"}, {"range_caller", "4.3"}}) do
        table.insert(entries, string.format('{"api": "%s", "kind": "function", "introduced": "9.0", "minimum": "%s", "status": "implemented"}', row[1], row[2]))
    end
    io.writefile(path.join(work, "registry", "range.json"), '{"framework": "Range", "entries": [' .. table.concat(entries, ", ") .. ']}\n')
    local listed = backports.registry(work)
    local api = "__attribute__((visibility(\"default\"))) "
    local early = fixtures.object(work, "early", api .. "int range_early(void) { return 4; }\n")
    local late = fixtures.object(work, "late", "int range_shared(void);\n" .. api .. "int range_late(void) { return range_shared() + 6; }\n")
    local helper = fixtures.object(work, "helper", "int range_shared(void) { return 0; }\n")
    local installer = fixtures.object(work, "installer", "static int installed;\n__attribute__((constructor)) static void install(void) { installed = 1; }\n")
    local mixed = fixtures.object(work, "mixed", api .. "int range_both_early(void) { return 4; }\n" .. api .. "int range_both_late(void) { return 6; }\n")
    local caller = fixtures.object(work, "caller", "int range_late(void);\n" .. api .. "int range_caller(void) { return range_late(); }\n")
    local upward = fixtures.object(work, "upward", "int range_late(void);\nstatic int installed;\n__attribute__((constructor)) static void install(void) { installed = range_late(); }\n")
    local objects = {early, late, helper, installer}
    local minimums, problems, unreached = backports.minimums(listed, objects, "armv7", "4.3")
    if #problems > 0 or minimums[early] or minimums[late] ~= "6.0" or minimums[helper] ~= "6.0" or minimums[installer] or table.concat(unreached, ",") ~= installer then
        table.insert(found, string.format("for iOS 4.3 the 6.0 object and the helper it calls are carried from 6.0 and the installer is unreached, not early %s late %s helper %s installer %s, unreached %s, refused %s",
                                          tostring(minimums[early]), tostring(minimums[late]), tostring(minimums[helper]), tostring(minimums[installer]), table.concat(unreached, ","), table.concat(problems, "; ")))
    end
    local kept, _, left = backports.band({}, objects, nil, {release = "4.3", minimums = minimums})
    if table.concat(kept, ",") ~= table.concat({early, installer}, ",") or table.concat(left, ",") ~= table.concat({late, helper}, ",") then
        table.insert(found, "the band for iOS 4.3 keeps the 4.3 object and the installer and leaves the 6.0 object and its helper out, not keep " .. table.concat(kept, ",") .. " and leave " .. table.concat(left, ","))
    end
    kept, _, left = backports.band({}, objects, nil, {release = "6.0", minimums = minimums})
    if #kept ~= 4 or #left ~= 0 then
        table.insert(found, string.format("the band for iOS 6.0 keeps all four objects, not %d with %d left out", #kept, #left))
    end
    _, problems = backports.minimums(listed, {mixed}, "armv7", "4.3")
    if #problems ~= 1 or not problems[1]:find("range_both_early", 1, true) or not problems[1]:find("range_both_late", 1, true) then
        table.insert(found, "an object holding entries of minimums 4.3 and 6.0 must be refused for iOS 4.3 naming both: " .. table.concat(problems, "; "))
    end
    _, problems = backports.minimums(listed, {mixed}, "armv7", "6.0")
    if #problems ~= 0 then
        table.insert(found, "for iOS 6.0 neither minimum bounds anything, so the mixed object is not refused: " .. table.concat(problems, "; "))
    end
    _, problems = backports.minimums(listed, {early, late, helper, caller}, "armv7", "4.3")
    if #problems ~= 1 or not problems[1]:find("caller.o", 1, true) or not problems[1]:find("_range_late", 1, true) then
        table.insert(found, "an object the registry carries at 4.3 that calls the 6.0 object must be refused naming both: " .. table.concat(problems, "; "))
    end
    local upwards = {early, late, helper, upward}
    local inherited
    minimums, problems, unreached, inherited = backports.minimums(listed, upwards, "armv7", "4.3")
    local from = inherited[upward]
    if #problems > 0 or #unreached > 0 or minimums[upward] ~= "6.0" or not from or from.from ~= late or from.symbol ~= "_range_late" then
        table.insert(found, string.format("an installer that calls the 6.0 object takes 6.0 from it by _range_late, not %s from %s by %s, unreached %s, refused %s",
                                          tostring(minimums[upward]), tostring(from and from.from), tostring(from and from.symbol), table.concat(unreached, ","), table.concat(problems, "; ")))
    end
    kept, _, left = backports.band({}, upwards, nil, {release = "4.3", minimums = minimums})
    if table.concat(kept, ",") ~= early or table.concat(left, ",") ~= table.concat({late, helper, upward}, ",") then
        table.insert(found, "the band for iOS 4.3 leaves the installer that calls the 6.0 object out with it, not keep " .. table.concat(kept, ",") .. " and leave " .. table.concat(left, ","))
    end
    kept, _, left = backports.band({}, upwards, nil, {release = "6.0", minimums = minimums})
    if #kept ~= 4 or #left ~= 0 then
        table.insert(found, string.format("the band for iOS 6.0 keeps the installer that calls the 6.0 object, not %d kept with %d left out", #kept, #left))
    end
end

-- The registry is what the backports say they carry, and the package build
-- refuses one that contradicts itself - after an hour of building. The suite
-- asks the registry of the repository the same question in a hundredth of a
-- second, so a duplicate entry is a failed test and not a failed release.
function failures(opt)
    local backports = import("apple.backports", {rootdir = opt.modules, anonymous = true})
    local found = {}
    local root = path.join(opt.modules, "..", "packages", "a", "apple-backports")
    if not os.isdir(path.join(root, "registry")) then
        table.insert(found, root .. " holds no registry to read")
        return found
    end
    local listed, incomplete = backports.registry(root)
    for index, complaint in ipairs(incomplete or {}) do
        if index <= 8 then
            table.insert(found, "the registry says: " .. complaint)
        end
    end
    if #(incomplete or {}) > 8 then
        table.insert(found, string.format("and %d more of the same", #incomplete - 8))
    end
    local named = 0
    for _ in pairs(listed or {}) do
        named = named + 1
    end
    if named == 0 then
        table.insert(found, "the registry of the repository names no API at all, which is not what it is for")
    end
    wiring(backports, root, found)
    range_step(backports, fixtures.scratch(), found)
    return found
end

-- The registry is checked against what the backports carry only when every library
-- is built, so a library that no config of the package builds keeps that check from
-- running for every config, and nothing says so. The recipe names each library in
-- the list of links and again in the list it builds, and each config in both.
function wiring(backports, root, found)
    local recipe = io.readfile(path.join(root, "xmake.lua"))
    local function count(text)
        local n, from = 0, 1
        while true do
            local at = recipe:find(text, from, true)
            if not at then
                return n
            end
            n = n + 1
            from = at + #text
        end
    end
    for _, library in ipairs(backports.libraries()) do
        if library.name ~= "FoundationBackports" and count('"' .. library.name .. '"') < 2 then
            table.insert(found, library.name .. " is named fewer than twice in the recipe of the package, so no config builds it and the registry is never checked against the backports")
        end
    end
    for name in recipe:gmatch('add_configs%("([%w]+)"') do
        if name ~= "sources" and count('package:config("' .. name .. '")') < 2 then
            table.insert(found, 'the config "' .. name .. '" is used fewer than twice in the recipe, so it builds no library, or does not link it')
        end
    end
end
