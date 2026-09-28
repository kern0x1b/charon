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

-- A type, an enumeration or a struct has no symbol by nature: nothing exports MLMultiArrayDataType or
-- MLMultiArrayDataTypeDouble, so an implemented row of kind "type" or "case" can never be answered by a
-- symbol, and the check would hold it red forever. Such a row is implemented when a header the build reads
-- declares it - and the declaration is read, not taken on trust: a name no header declares is the same as a
-- class nothing exports, which is what this step measures both ways.
local function type_rows(backports, found)
    local root = fixtures.scratch()
    os.tryrm(root)
    os.mkdir(root)                       -- os.mkdir takes one directory: its parents must already be there
    os.mkdir(path.join(root, "Charon"))
    os.mkdir(path.join(root, "registry"))
    -- a Charon header of the tree's own, the shape a generated header declaring a type has
    io.writefile(path.join(root, "Charon", "CharonFixture.h"),
                 "#import <Foundation/Foundation.h>\ntypedef NSUInteger FixturedType;\ntypedef NS_ENUM(NSInteger, FixturedKind) {\n    FixturedCaseOne = 1,\n    FixturedCaseTwo = 2,\n};\n")
    -- xmake's try() returns values only when the block succeeds: it calls the catch and discards whatever
    -- that returns, so a message taken from try's second value is nil on a raise. The catch therefore writes
    -- into this, and told() says which of the two happened.
    local function told(rows)
        io.writefile(path.join(root, "registry", "Fix.json"), string.format('{"framework": "Fix", "entries": [%s]}', table.concat(rows, ", ")))
        local message
        local passed = try {
            function () backports.check_registry(root, {classes = {}, members = {}, symbols = {}}, true, "6.1.3", {}, nil) return true end,
            catch {function (errors) message = tostring(errors) end}
        }
        return (passed and "the check passed, nothing was held unbuilt") or message or "raised with no message"
    end
    -- the shape a real row has: an NS_ENUM or a typedef a port carries from the release it arrived in, so
    -- `ours` is true at 6.1.3 and `carried` is false (it arrived later), which is the case the check is about
    local function row(api, kind)
        return string.format('{"api": "%s", "kind": "%s", "introduced": "11.0", "minimum": "6.0", "status": "implemented", "facts": "f"}', api, kind)
    end
    local refused = told({row("FixturedType", "type"), row("FixturedKind", "type"), row("FixturedCaseOne", "case")})
    if refused ~= "the check passed, nothing was held unbuilt" then
        table.insert(found, "a type and an enumeration case a Charon header declares must not be held unbuilt: " .. refused)
    end
    -- the SDK pass: a type no header of the tree declares, that a header of an SDK declares, must pass
    -- through the tree's own headers and reach the SDK search, which is a grep into a file and a cached copy
    local sdk = path.join(root, "fake-sdk")
    os.mkdir(path.join(sdk, "usr"))
    os.mkdir(path.join(sdk, "usr", "include"))
    io.writefile(path.join(sdk, "usr", "include", "Fake.h"), "typedef int FixturedSdkType;\n")
    io.writefile(path.join(root, "registry", "Fix.json"), string.format('{"framework": "Fix", "entries": [%s]}', row("FixturedSdkType", "type")))
    local message
    local passed = try {
        function () backports.check_registry(root, {classes = {}, members = {}, symbols = {}}, true, "6.1.3", {}, nil, sdk) return true end,
        catch {function (errors) message = tostring(errors) end}
    }
    if (passed and "the check passed, nothing was held unbuilt") ~= "the check passed, nothing was held unbuilt" then
        table.insert(found, "a type the SDK's headers declare must not be held unbuilt, and the SDK search is not reaching that answer: " .. tostring(message))
    end

    local absent = told({row("FixturedAbsent", "type"), row("FixturedCaseAbsent", "case")})
    for _, name in ipairs({"FixturedAbsent", "FixturedCaseAbsent"}) do
        if not absent:find(name, 1, true) then
            table.insert(found, "a type no header declares is still red, and the run must name " .. name .. ": " .. absent)
        end
    end
    -- a function is registered with its parentheses and a symbol with none, so the fallback that reads the
    -- registry for the release a name arrived in has to try both spellings of one symbol
    local rows = backports.registry(root)
    told({string.format('{"api": "FixturedFree()", "kind": "function", "introduced": "11.0", "minimum": "6.0", "status": "implemented", "facts": "f"}')})
    rows = backports.registry(root)
    if (rows["FixturedFree()"] or {}).kind ~= "function" then
        table.insert(found, "a function is not read out of the registry at all, so nothing can look it up")
    end
    -- and the two kinds are read as themselves, not as methods: the spelling rule does not apply to them
    told({row("FixturedType", "type"), row("FixturedKind", "type"), row("FixturedCaseOne", "case")})
    local listed = backports.registry(root)
    for _, name in ipairs({"FixturedType", "FixturedKind", "FixturedCaseOne"}) do
        if (listed[name] or {}).kind == nil then
            table.insert(found, "the registry does not list " .. name .. " at all")
        end
    end
    os.tryrm(root)
end



-- A member the port adds to a class the release itself carries needs a row of its own: UIView's row says
-- nothing about -[UIView foo]. And a protocol has no accessors, so its row is implemented when the objects
-- carry its metadata and named. Each is asked both ways here, with the inventory and the objects' symbols
-- built by hand, so neither depends on a build.
local function member_and_protocol_rows(backports, found)
    local root = fixtures.scratch()
    os.tryrm(root)
    os.mkdir(root)
    os.mkdir(path.join(root, "registry"))
    local function rows(text)
        io.writefile(path.join(root, "registry", "Fix.json"), '{"framework": "Fix", "entries": [' .. text .. ']}')
    end
    -- the release has FixClass and FixProtocol; the port defines neither
    local inventory = {classes = {FixClass = {image = true, instance = {}, ["+"] = {}},
                                   FixProtocol = {image = true, instance = {}, ["+"] = {}}}}
    -- what the build carries: FixClass, which the release has and the port defines, and FixProtocol, which
    -- neither the release nor the objects carry unless a case below says so
    local function asked(members, symbols, defined, withProtocol)
        -- FixClass only: the objects define a protocol's metadata, not a class of the protocol's name, so
        -- putting FixProtocol in found.classes would make `built` true and the row would never be unbuilt -
        -- which is how this case passed in every shape before
        local classes = {FixClass = withProtocol and true or true}
        if withProtocol then
            classes = {FixClass = true}
        end
        local message
        local ok = try {
            function () backports.check_registry(root, {classes = classes, members = members,
                                                        symbols = symbols or {}, defined = defined or {}},
                                                  true, "6.1.3", {}, inventory) return true end,
            catch {function (errors) message = tostring(errors) end}
        }
        return (ok and "passed" or message or "raised with no message")
    end
    local class = '{"api": "FixClass", "kind": "class", "introduced": "9.0", "minimum": "6.0", "status": "implemented", "facts": "f"}'
    local protocol = '{"api": "FixProtocol", "kind": "protocol", "introduced": "9.0", "minimum": "6.0", "status": "implemented", "facts": "f"}'
    rows(class)
    local member = {["-[FixClass extra]"] = true}
    if not asked(member):find("FixClass", 1, true) then
        table.insert(found, "a category method on a class the release carries must be red without a row of its own, and it is not: " .. asked(member))
    end
    rows(class .. ',{"api": "-[FixClass extra]", "kind": "method", "introduced": "9.0", "minimum": "6.0", "status": "implemented", "facts": "f"}')
    local said = asked(member)
    if said:find("FixClass") then
        table.insert(found, "a category method with a row of its own must pass, and it is red: " .. said)
    end
    rows(protocol)
    -- the metadata symbol is one the object *defines*, so the rule reads the defined set: with the symbol in
    -- the imported set instead - where a class's names live - the row stays unbuilt, which is how 73 rows
    -- stayed red while the objects carried 91 of their metadata symbols (measured 2026-09-28, nm on
    -- build/objects/*/protocols/*.o)
    said = asked({}, nil, {["_OBJC_PROTOCOL_$_FixProtocol"] = true}, true)
    if said:find("FixProtocol") then
        table.insert(found, "a protocol row whose objects define the protocol's metadata must pass, and it is red: " .. said)
    end
    said = asked({}, {["_OBJC_PROTOCOL_$_FixProtocol"] = true}, nil, true)
    if not said:find("FixProtocol", 1, true) then
        table.insert(found, "a protocol row whose metadata is only an import must not pass, and it does: " .. said)
    end
    said = asked({}, {})
    if not said:find("FixProtocol", 1, true) then
        table.insert(found, "a protocol row nothing in the objects carries must be red, and it is not: " .. said)
    end
    os.tryrm(root)
end


-- Two readers of a category's members, and they answer two different questions. The band machinery places an
-- object by what it *defines*, so a member the port adds in a category belongs to that class, not to the object
-- carrying it; check_registry asks what the port *carries*, which is wider. A synthetic inventory is enough:
-- one class the object defines, one class the release carries, one of the port's own, and a category member on
-- each. At 2fde39f4's shape - one reader for both - the first assertion fails, which is the bisect's finding.
local function two_readers(backports, found)
    local inventory = {classes = {
        -- the inventory's own shape: a key is the selector with its kind, and the reader strips that
        FixDefined = {image = true, instance = {["-definedOne"] = true}, ["+"] = {}},
        FixCarried = {image = true, instance = {["-carriedOne"] = true}, ["+"] = {}},
        CharonHelper = {image = false, instance = {["-helperOne"] = true}, ["+"] = {}}}}
    local function read(list)
        table.sort(list)
        return table.concat(list, " ")
    end
    local band = read(backports.added_members(inventory, {FixDefined = true, FixCarried = true}))
    if band ~= "-[CharonHelper helperOne]" then
        table.insert(found, "the band reader must return only what the object defines, not a member a category adds to a class the release carries, and it says: " .. band)
    end
    local api = read(backports.carried_api(inventory))
    if not api:find("%-%[FixCarried carriedOne%]", 1, false) or api:find("CharonHelper", 1, true) or not api:find("FixDefined", 1, true) then
        table.insert(found, "the API reader must return the members of every class but the port's own, and it says: " .. api)
    end
end


-- protocol_sources is a library's own reader: a synthetic registry with two libraries' folders, and each
-- generates only the rows of its own folder. Reading the whole registry put all 73 rows into every library.
local function own_rows(backports, found)
    local root = fixtures.scratch()
    os.tryrm(root)
    os.mkdir(path.join(root, "registry"))
    os.mkdir(path.join(root, "registry", "Alpha"))
    os.mkdir(path.join(root, "registry", "Beta"))
    local function rows(folder, name)
        io.writefile(path.join(root, "registry", folder, "rows.json"),
                     string.format('{"framework": "%s", "entries": [{"api": "%s", "kind": "protocol", "introduced": "9.0", "status": "implemented", "facts": "f"}]}', folder, name))
    end
    rows("Alpha", "AlphaOne")
    rows("Beta", "BetaOne")
    local out = path.join(root, "out")
    os.mkdir(out)
    for _, pair in ipairs({{"Alpha", "AlphaOne"}, {"Beta", "BetaOne"}}) do
        local folder, name = pair[1], pair[2]
        local library = {name = folder .. "Backports", folder = folder}
        local written = backports.protocol_sources(root, library, out, folder)
        local text = written[1] and io.readfile(written[1]) or ""
        if not text:find("@protocol(" .. name .. ")", 1, true) then
            table.insert(found, folder .. " does not generate its own protocol row: " .. text:gsub("\n", " "):sub(1, 90))
        end
        local other = folder == "Alpha" and "BetaOne" or "AlphaOne"
        if text:find("@protocol(" .. other .. ")", 1, true) then
            table.insert(found, folder .. " generates the other library's protocol row, so every library carries every protocol")
        end
    end
    os.tryrm(root)
end


-- A source this build generated sits in the build directory, and its quoted import reaches a header of the
-- tree only when the tree is on the path: the generated protocol source imports its library's Charon header,
-- and without this the gate stopped on "CharonFoundationProtocols.h file not found" for every library. The
-- case is the flags a job would be compiled with, and it fails when the include loop is gone.
local function generated_includes(backports, found)
    local folder = "/somewhere/packages/a/apple-backports/Foundation"
    local flags = table.concat(backports.compile_arguments({includes = {folder}}, "Protocols.m"), " ")
    if not flags:find("-I" .. folder, 1, true) then
        table.insert(found, "a generated source's job must add the library's own folder to its include path, and it does not: " .. flags)
    end
    local bare = table.concat(backports.compile_arguments({}, "Protocols.m"), " ")
    if bare:find("-I/somewhere", 1, true) then
        table.insert(found, "a job that names no include root must not have one, and it does: " .. bare)
    end
end

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
    type_rows(backports, found)
    member_and_protocol_rows(backports, found)
    two_readers(backports, found)
    own_rows(backports, found)
    generated_includes(backports, found)
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
