import("fixtures")

-- A band below an object's registry minimum neither keeps nor re-exports it, so the minimum of each
-- object is read from the entries its names answer to: a registry with one function at 4.3 and one
-- at 6.0, a helper only the 6.0 object calls, and an installer that exports nothing and that nothing
-- names. For 4.3 the 6.0 object and its helper are left out and the installer is kept with no floor;
-- for 6.0 all four are kept. A helper the 4.3 object calls too is kept at 4.3. An object holding entries of two minimums is refused, and so is one whose
-- entries place it below an object it calls: it would not link in between. An installer that
-- calls into the 6.0 object takes its minimum, as it links only where that object is carried: the band
-- for 6.0 keeps it and the band for 4.3 leaves it out.
local function range_step(backports, folder, found)
    local work = path.join(folder, "range")
    os.mkdir(path.join(work, "registry"))
    local entries = {}
    for _, row in ipairs({{"range_early", "4.3"}, {"range_late", "6.0"}, {"range_both_early", "4.3"}, {"range_both_late", "6.0"}, {"range_caller", "4.3"}, {"range_sharer", "4.3"}}) do
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
    local sharer = fixtures.object(work, "sharer", "int range_shared(void);\n" .. api .. "int range_sharer(void) { return range_shared() + 4; }\n")
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
    -- a helper the 4.3 object calls as well as the 6.0 one takes the lower minimum, which bounds nothing at 4.3
    local shared = {early, late, helper, sharer}
    minimums, problems = backports.minimums(listed, shared, "armv7", "4.3")
    if #problems > 0 or minimums[helper] or minimums[sharer] or minimums[late] ~= "6.0" then
        table.insert(found, string.format("a helper called by the 4.3 and the 6.0 object is carried with the 4.3 one, not helper %s sharer %s late %s, refused %s",
                                          tostring(minimums[helper]), tostring(minimums[sharer]), tostring(minimums[late]), table.concat(problems, "; ")))
    end
    kept, _, left = backports.band({}, shared, nil, {release = "4.3", minimums = minimums})
    if table.concat(kept, ",") ~= table.concat({early, helper, sharer}, ",") or table.concat(left, ",") ~= late then
        table.insert(found, "the band for iOS 4.3 keeps the helper the 4.3 object calls and leaves only the 6.0 object out, not keep " .. table.concat(kept, ",") .. " and leave " .. table.concat(left, ","))
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
    -- The lookup a band places an API by. entry_of() tries every spelling the registry uses, so a
    -- function the registry spells with its parentheses is found by the bare name the symbol table
    -- gives, and a member by the class that owns it. releases_in() falls back to it when no held
    -- cache and no source place a name - an 18.2 function on a port whose caches end at 18.0 is that
    -- case - and a raw listed[name] there misses every function, which left its object unplaceable
    -- and the object refused. These were in backports_test, which the light guard does not run, so
    -- they could not be executed; they are here, in a suite the guard does run, and they fail by
    -- assertion rather than on a nil field.
    local spellings = {["SomeLateFunction()"] = {api = "SomeLateFunction()", kind = "function",
                                                 introduced = "18.2", status = "implemented"},
                       ["-[UIView tintColorDidChange]"] = {api = "-[UIView tintColorDidChange]",
                                                           kind = "method", introduced = "7.0",
                                                           status = "implemented"},
                       ["UIBlurEffect"] = {api = "UIBlurEffect", kind = "class", introduced = "8.0",
                                           status = "absent"}}
    local by_function = backports.entry_of(spellings, "SomeLateFunction")
    local by_member = backports.entry_of(spellings, "UIView.tintColorDidChange")
    if not by_function or by_function.introduced ~= "18.2" then
        table.insert(found, "the registry entry of a function must be found by the bare name the symbol table gives it, since the registry spells it with its parentheses")
    end
    if not by_member or by_member.introduced ~= "7.0" then
        table.insert(found, "the registry entry of a member must be found by the class that owns it, which is the shape check_registry is given")
    end
    if backports.entry_of(spellings, "NoSuchName") then
        table.insert(found, "a name the registry does not carry must be answered nil, not another entry")
    end
    -- And the call that regressed, asserted on the source so it needs no compiler: the fallback has
    -- to reach the registry through entry_of.
    local source = io.readfile(path.join(opt.modules, "apple", "backports.lua")) or ""
    local first = source:find("function releases_in", 1, true)
    local last = first and source:find("\nend\n", first, true)
    local body = (first and last) and source:sub(first, last) or ""
    if not body:find("entry_of(listed(opt.root), name)", 1, true) then
        table.insert(found, "releases_in must reach the registry through entry_of and not by a raw index that misses every function")
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
    spelling(backports, found)
    unreadable(backports, found)
    named_twice(backports, found)
    return found
end

-- A framework's rows live in registry/<Framework>.json or in registry/<Framework>/<part>.json, and both are read.
-- A name in two of them is a contradiction the gate cannot see through: whichever is read last decides the
-- status, so a name built and listed implemented in one file is listed absent in the other, and every check
-- that reads the status answers about the last one. It has to be refused by name, with both paths.
function named_twice(backports, found)
    local root = path.join(os.tmpdir(), "registry_test_named_twice")
    os.tryrm(root)
    os.mkdir(path.join(root, "registry"))
    os.mkdir(path.join(root, "registry", "Fix"))
    local function told()
        local _, incomplete = backports.registry(root)
        return table.concat(incomplete, "; ")
    end
    local function write(where, entries)
        io.writefile(path.join(root, "registry", where), string.format('{"framework": "Fix", "entries": [%s]}', table.concat(entries, ", ")))
    end
    local function entry(api, status)
        return string.format('{"api": "%s", "kind": "function", "introduced": "8.0", "status": "%s", "effect": "none", "reason": "because"}', api, status)
    end
    os.tryrm(root)
    os.mkdir(path.join(root, "registry"))
    os.mkdir(path.join(root, "registry", "Fix"))
    write("Fix.json", {entry("fix_one", "implemented"), entry("fix_both", "implemented")})
    write("Fix/part.json", {entry("fix_two", "absent")})
    if told() ~= "" then
        table.insert(found, "a name in one file and another in a second is refused, not reported: " .. told())
    end
    write("Fix/part.json", {entry("fix_two", "absent"), entry("fix_both", "absent")})
    local twice = told()
    if not twice:find("fix_both is named by both registry/Fix.json and registry/Fix/part.json", 1, true) then
        table.insert(found, "a name in registry/Fix.json and registry/Fix/part.json must be refused naming both paths, not '" .. twice .. "'")
    end
    write("Fix/part.json", {entry("fix_both", "absent"), entry("fix_both", "absent")})
    if not told():find("fix_both is named by both", 1, true) then
        table.insert(found, "a name twice in one file is refused as well, not '" .. told() .. "'")
    end
    -- one member has two legal spellings and they are two names: refusing them would refuse the registry itself
    os.tryrm(root)
    os.mkdir(path.join(root, "registry"))
    io.writefile(path.join(root, "registry", "Fix.json"),
                 '{"framework": "Fix", "entries": [{"api": "FixView.size", "kind": "property", "introduced": "8.0", "status": "implemented", "facts": "x"},'
                 .. '{"api": "-[FixView size]", "kind": "method", "introduced": "8.0", "status": "implemented", "facts": "x"}]}')
    if told() ~= "" then
        table.insert(found, "the two spellings of one property are two names and are not a duplicate: " .. told())
    end
    os.tryrm(root)
end

-- A method or a property is told by -[Class selector:], +[Class selector:] or Class.name, which is what lift() reads: one spelled Class.selector:
-- is asked for as a bare name, found nowhere and left as it was, so the registry refuses it (by name) and does not let a lift bless it.
function spelling(backports, found)
    local root = path.join(os.tmpdir(), "registry_test_spelling")
    os.tryrm(root)
    local function complaints(api, kind)
        io.writefile(path.join(root, "registry", "Fix.json"), string.format('[{"api": "%s", "kind": "%s", "introduced": "8.0", "minimum": "6.0", "status": "implemented"}]', api, kind))
        local _, incomplete = backports.registry(root)
        return table.concat(incomplete, "; ")
    end
    for _, spelled in ipairs({{"-[FixView draw:]", "method"}, {"+[FixView make:]", "method"}, {"FixView.size", "property"}, {"FixView.draw", "method"}, {"FixView.size()", "property"}}) do
        local told = complaints(spelled[1], spelled[2])
        if told ~= "" then
            table.insert(found, string.format("the %s %s is refused: %s", spelled[2], spelled[1], told))
        end
    end
    for _, spelled in ipairs({{"FixView.draw:", "method"}, {"FixView.size:", "property"}, {"[FixView draw:]", "method"}, {"-[FixView]", "method"}}) do
        local told = complaints(spelled[1], spelled[2])
        if not told:find(spelled[1] .. " is a " .. spelled[2] .. " not spelled", 1, true) then
            table.insert(found, string.format("the %s %s is not refused by name (says '%s')", spelled[2], spelled[1], told))
        end
    end
    os.tryrm(root)
end

-- The two ways a member is named, and the two ways one API is named twice, are both refused by name, because
-- each of them is a row the lift cannot carry and cannot say why: a class or a protocol is matched against an
-- interface or a protocol of that name and a member spelling is no name at all, and two spellings of one API
-- that answer differently have the lift lower the implemented one and then find the other lowered, which it
-- refuses over after the whole surface has been dumped. The two rows below are the ones a full lift of
-- 7bb678779 raised over, both of them, on both SDKs.
function unreadable(backports, found)
    local root = path.join(os.tmpdir(), "registry_test_unreadable")
    os.tryrm(root)
    os.mkdir(path.join(root, "registry"))
    local function complaints(rows)
        io.writefile(path.join(root, "registry", "Fix.json"), '{"framework": "Fix", "entries": [' .. table.concat(rows, ", ") .. ']}')
        local _, incomplete = backports.registry(root)
        return table.concat(incomplete, "; ")
    end
    local function row(api, kind, status, extra)
        return string.format('{"api": "%s", "kind": "%s", "introduced": "9.0", "minimum": "6.0", "status": "%s"%s}',
                             api, kind, status, extra or "")
    end
    local told = complaints({row("+[FixView isEnabledByDefault]", "class", "implemented")})
    if not told:find("is a class spelled +[FixView isEnabledByDefault]", 1, true) then
        table.insert(found, string.format("a class row spelled as a method is not refused by name (says '%s')", told))
    end
    told = complaints({row("FixView.size", "property", "implemented"), row("-[FixView size]", "method", "inert", ', "reason": "nothing draws it", "effect": "nothing"')})
    if not told:find("they are one API in two spellings", 1, true) then
        table.insert(found, string.format("two spellings of one API that answer differently are not refused (says '%s')", told))
    -- the pair is named in whichever order the table hands it over, so each half is looked for on its own
    elseif not told:find("FixView.size is implemented", 1, true) or not told:find("-[FixView size] is inert", 1, true) then
        table.insert(found, string.format("the refusal does not name both spellings with their statuses (says '%s')", told))
    end
    -- a property carried and its setter left out is an answer, not a contradiction: the setter is its own row
    told = complaints({row("FixView.size", "property", "implemented"),
                      row("-[FixView setSize:]", "method", "absent", ', "reason": "iOS 6 has no such setter", "effect": "nothing is resized"')})
    if told ~= "" then
        table.insert(found, string.format("a property carried and its setter absent are refused as one API in two spellings (says '%s')", told))
    end
    -- the same two spellings answering alike is the ordinary case and must stay silent
    told = complaints({row("FixView.size", "property", "implemented"), row("-[FixView size]", "method", "implemented", ', "facts": "facts/Fix.md"')})
    if told ~= "" then
        table.insert(found, string.format("two spellings of one API that answer alike are refused (says '%s')", told))
    end
    os.tryrm(root)
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
