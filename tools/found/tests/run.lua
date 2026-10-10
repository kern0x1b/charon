-- Tests of the declaration extractor: the driver (ir.lua) runs over tests/fixture/sdk, a small SDK with each case the extractor must
-- handle. Its output must equal the reviewed golden shards (tests/expected), the reviewed conflict list (tests/conflicts.tsv) and the
-- unparsed list (tests/unparsed.tsv), and named facts about the golden are checked. The golden shards record no machine identity: the
-- header line of each holds the token <decls --version> where a shard records the libclang identity (the version, the digest of its
-- dylib, the target), and the suite writes the goldens to a scratch spec folder under build/ with the token replaced by the identity
-- the extractor under test prints. Which libclang the committed shards are pinned to is checked by ir.lua's check over the committed
-- spec (a re-pin is a reviewed event), not by this suite.
--
-- Needs the extractor built (xmake -P tools/found). Run, from any folder: xmake l tools/found/tests/run.lua
local ROOT = path.absolute(os.scriptdir())
local FOUND = path.directory(ROOT)
local REPO = path.directory(path.directory(FOUND))
local IR = path.join(FOUND, "ir.lua")
local GOLDEN = path.join(ROOT, "expected")
local SPEC = path.join(REPO, "build", "found", "test-spec")
local shard = import("shard", {rootdir = FOUND, anonymous = true})
local host = import("gen.host", {rootdir = path.join(REPO, "tools"), anonymous = true})
local checks = 0

local function expect(condition, message)
    checks = checks + 1
    if not condition then raise("test failed: " .. message) end
end

-- 0. the configuration (review F10): the sweep's usr/include modules are the top-level modules the maps declare, minus the reviewed
-- exclusions of IR_CONFIG's usr-modules.tsv, and a row that names no module is an error. The fixture's config excludes FixtureCExtra;
-- the checks here write their own configurations under build/ (scratch).
local FIXTURE_CONFIG = path.join(ROOT, "fixture", "config")
local DECLS = host.target_product(REPO, FOUND, "decls")
assert(os.isfile(DECLS), "the extractor is not built: " .. DECLS .. " (xmake -P tools/found)")
local FIXTURE_SDK = path.join(ROOT, "fixture", "sdk")

-- The golden shards, with the identity of the extractor under test where their header holds the token.
local TOKEN = "#libclang=<decls --version>"
local fixture_identity = (os.iorunv(DECLS, {"--version"}, {envs = {IR_SDK = FIXTURE_SDK}}):gsub("%s+$", ""))
os.tryrm(SPEC)
for _, file in ipairs(os.files(path.join(GOLDEN, "**", "declarations.tsv"))) do
    local golden = io.readfile(file)
    local name = path.relative(file, GOLDEN)
    expect(golden:sub(1, #TOKEN) == TOKEN, "the golden shard " .. name .. " holds the token, not an identity of its own")
    local target = path.join(SPEC, name)
    os.mkdir(path.directory(target))
    io.writefile(target, "#libclang=" .. fixture_identity .. golden:sub(#TOKEN + 1))
end
local function write_config(name, usr_rows, fallback_rows)
    local dir = path.join(REPO, "build", "found", "test-config", name)
    os.runv("mkdir", {"-p", dir})
    local usr = io.open(path.join(dir, "usr-modules.tsv"), "w")
    usr:write(usr_rows or "# (no exclusions)\n")
    usr:close()
    local fallback = io.open(path.join(dir, "fallback.tsv"), "w")
    fallback:write(fallback_rows or "# (no fallbacks)\n")
    fallback:close()
    return dir
end
local function module_names(config)
    local names = {}
    for line in os.iorunv(DECLS, {"--list"}, {envs = {IR_SDK = FIXTURE_SDK, IR_CONFIG = config}}):gmatch("[^\n]+") do
        table.insert(names, line:match("^([^\t]+)"))
    end
    return table.concat(names, " ")
end
-- (ruling 1) System/Library/SubFrameworks is part of the SDK and of the sweep: a framework there is listed and its declarations read
expect(os.iorunv(DECLS, {"FixtureSub"}, {envs = {IR_SDK = FIXTURE_SDK, IR_CONFIG = FIXTURE_CONFIG}}):find("sub_value", 1, true) ~= nil,
    "a framework of System/Library/SubFrameworks is in the sweep (derived from the SDK layout) and its declarations are read")
-- (ruling 4) a framework with no module map reads every header of its Headers/ folder, not only its umbrella: a header the umbrella does
-- not include is read too (RealityKit's and vecLib's umbrellas leave headers out)
expect(os.iorunv(DECLS, {"FixtureFallback"}, {envs = {IR_SDK = FIXTURE_SDK, IR_CONFIG = FIXTURE_CONFIG}}):find("extra_value", 1, true) ~= nil,
    "a framework with no module map reads every header of its Headers/ folder, not only its umbrella")
expect(module_names(FIXTURE_CONFIG) == "Broken Fixture Fixture/Inner FixtureC FixtureFallback FixtureSub FixtureUmbrella FixtureUmbrella/FixtureNested NoHeader Plain Swiftonly",
    "the fixture's config lists FixtureC and leaves out its excluded module FixtureCExtra")
expect(module_names(write_config("no-exclusions")) == "Broken Fixture Fixture/Inner FixtureC FixtureCExtra FixtureFallback FixtureRoot FixtureSub FixtureUmbrella FixtureUmbrella/FixtureNested NoHeader Plain Swiftonly",
    "a config with no exclusion lists every top-level module the maps declare (FixtureCExtra and FixtureRoot too)")
-- (b) a usr/include module whose header sits in the include root owns that header alone: the root holds other modules' headers too (the
-- MacTypes case: its one header is in the root, and every header of the root counted as its own). FixtureRoot.h includes a header of the
-- root that its map does not name; that header's declarations are not FixtureRoot's.
local root_rows = os.iorunv(DECLS, {"FixtureRoot"}, {envs = {IR_SDK = FIXTURE_SDK, IR_CONFIG = write_config("no-exclusions")}})
expect(root_rows:find("FixtureRootInt", 1, true) ~= nil, "a usr/include module owns the declarations of its own header in the include root")
expect(root_rows:find("root_other_function", 1, true) == nil and root_rows:find("FixtureRootOtherLong", 1, true) == nil,
    "a header of the include root that the module does not name is not the module's own (its declarations are left out)")
local stale_failure = nil
try {
    function () os.iorunv(DECLS, {"--list"}, {envs = {IR_SDK = FIXTURE_SDK, IR_CONFIG = write_config("stale", "NoSuchModule\tnamed by no map\n")}}) end,
    catch {
        function (errors) stale_failure = tostring(errors) end
    }
}
expect(stale_failure ~= nil and stale_failure:find("NoSuchModule", 1, true) ~= nil,
    "an exclusion that no usr/include map declares is an error that names it")

-- F29 (review-v-gen): a framework with no module-map header is read from its Headers/ folder only when fallback.tsv lists it, and a
-- listed row that does not fit (no such framework, or a framework that has a module map) is an error that names the row
local function failure_of(args, config)
    local text = nil
    try {
        function () os.iorunv(DECLS, args, {envs = {IR_SDK = FIXTURE_SDK, IR_CONFIG = config}}) end,
        catch {
            function (errors) text = tostring(errors) end
        }
    }
    return text or ""
end
local refused = failure_of({"Plain"}, write_config("no-fallbacks"))
expect(refused:find("Plain", 1, true) ~= nil and refused:find("fallback.tsv", 1, true) ~= nil,
    "a framework with no module map that fallback.tsv does not list is refused, and the error names it and the list (got " .. refused .. ")")
expect(os.iorunv(DECLS, {"Plain"}, {envs = {IR_SDK = FIXTURE_SDK, IR_CONFIG = FIXTURE_CONFIG}}):find("plain_value", 1, true) ~= nil,
    "a framework that fallback.tsv lists is read from its Headers/ folder")
expect(failure_of({"--list"}, write_config("stale-name", nil, "NoSuchFramework\tnamed by no framework\n")):find("NoSuchFramework", 1, true) ~= nil,
    "a fallback row that names no framework of the SDK is an error that names it")
expect(failure_of({"Fixture"}, write_config("stale-map", nil, "Fixture\tFixture has a module map\n")):find("module map", 1, true) ~= nil,
    "a fallback row for a framework that has a module map is an error (the row is stale)")

-- (b, ruling 3) the base typedefs the sweep's shards lack (BOOL, NSInteger and NSUInteger in ObjectiveC's objc/, UInt32, SInt32, OSStatus,
-- Float32, Float64 and Boolean in MacTypes.h) are declared by those usr/include modules, so the committed exclusion list must not name
-- them: a reviewed list that leaves out the module that declares a type leaves the type out of every shard
local committed = {}
for line in io.lines(path.join(FOUND, "config", "usr-modules.tsv")) do
    local name = line:match("^([^\t#][^\t]*)\t")
    if name then committed[name] = true end
end
expect(not committed.ObjectiveC and not committed.MacTypes,
    "the committed sweep covers ObjectiveC and MacTypes, which declare the base typedefs no shard has")

-- (a) a header of a nested framework, reached through its umbrella's Headers/ folder (#import "../Frameworks/..."), is not the umbrella's
-- own: the umbrella declares nothing, so its census has no own declaration and no nested declaration is one of its rows. The own rule
-- compares the path as written (Headers/../Frameworks/...), which the Headers/ prefix matches.
local umbrella_census = os.iorunv(DECLS, {"FixtureUmbrella"}, {envs = {IR_SDK = FIXTURE_SDK, IR_CONFIG = FIXTURE_CONFIG}})
expect(umbrella_census:find("own=0", 1, true) ~= nil and umbrella_census:find("nested_value", 1, true) == nil,
    "a nested framework's declaration reached through ../Frameworks is not the umbrella's own (census own=0; got " .. umbrella_census:gsub("\n", " | ") .. ")")

-- (a, ruling 3 and 4) a framework of the sweep with no shard is classified, so none is lost silently: unparsed (tests/unparsed.tsv) or
-- one whose headers declare nothing of its own (no-own.tsv: name, class, target, reason, the umbrella of Accelerate's shape). Each row of
-- no-own.tsv names such a framework.
local function named_rows(file)
    local names = {}
    for line in io.lines(file) do
        local name = line:match("^([^\t#][^\t]*)\t")
        if name then names[name] = true end
    end
    return names
end
local unparsed_names = named_rows(path.join(ROOT, "unparsed.tsv"))
local own_rows = named_rows(path.join(FIXTURE_CONFIG, "no-own.tsv"))
local swept, unclassified = {}, {}
for line in os.iorunv(DECLS, {"--list"}, {envs = {IR_SDK = FIXTURE_SDK, IR_CONFIG = FIXTURE_CONFIG}}):gmatch("[^\n]+") do
    local name = line:match("^([^\t]+)")
    swept[name] = true
    if not os.isfile(path.join(SPEC, name, "declarations.tsv")) and not unparsed_names[name] and not own_rows[name] then
        table.insert(unclassified, name)
    end
end
table.sort(unclassified)
expect(#unclassified == 0, "a framework with no shard is classified (unparsed.tsv or no-own.tsv); unclassified: " .. table.concat(unclassified, " "))
for name in pairs(own_rows) do
    expect(swept[name] and not os.isfile(path.join(SPEC, name, "declarations.tsv")),
        name .. " is listed in no-own.tsv but is not a framework of the sweep without a shard")
end

-- (ruling 2) a shard carries the value of each enum constant, as clang evaluates it, in a value column appended to the shard's columns;
-- the enum constant's row has its value, and every other row has "-" there (the cell is empty, as the IR writes an empty cell)
local value_lines = {}
for line in io.lines(path.join(SPEC, "Fixture", "declarations.tsv")) do table.insert(value_lines, line) end
expect(value_lines[1]:match("columns=([^\t\n]*)") == "kind,usr,container,name,side,type,params,attrs,availability,message,declhash,value",
    "the shard header names a value column, after declhash")
local enum_value, others_dash = {}, true
for i = 2, #value_lines do
    local cells = {}
    for c in (value_lines[i] .. "\t"):gmatch("([^\t]*)\t") do table.insert(cells, c) end
    if cells[1] == "enumconst" then
        enum_value[cells[2]] = cells[12]
    elseif cells[12] ~= "-" then
        others_dash = false
    end
end
expect(enum_value["c:@E@FXState@FXStateOn"] == "1" and enum_value["c:@E@FXState@FXStateOff"] == "2" and others_dash,
    "an enum constant's row carries its clang value (FXStateOn 1, FXStateOff 2) and every other row has - in the value column")
-- (review r3 G3) the value is clang's own for the enum's integer type: an unsigned enum's constant is not sign-extended (it read as -1
-- for 255 of an unsigned char enum), and a signed enum keeps its negative value. The expected texts are the header's own numbers.
for usr, want in pairs({
    ["c:@E@FXByte@FXByteTop"] = "255",                        -- enum : unsigned char { = 255 }
    ["c:@E@FXWord@FXWordAll"] = "18446744073709551615",       -- enum : unsigned long { = ~0UL }
    ["c:@E@FXWide@FXWideTop"] = "9223372036854775808",        -- enum : unsigned long long { = 1ULL << 63 }
    ["c:@E@FXMask@FXMaskClass"] = "4026531840",               -- enum { = 15U << 28 }: C picks unsigned int
    ["c:@E@FXSigned@FXSignedBelow"] = "-1"}) do               -- enum : int { = -1 }
    expect(enum_value[usr] == want, "the enum constant " .. usr .. " has the value " .. want .. " (got " .. tostring(enum_value[usr]) .. ")")
end

-- (ruling 5) ir.lua enforces the contract "every framework with no shard is in unparsed.tsv or no-own.tsv": with an empty no-own list,
-- the fixture's FixtureUmbrella (no shard, not unparsed) must make the check fail, and the error names it
os.runv("mkdir", {"-p", path.join(REPO, "build", "found", "test-config")})
local empty_no_own = path.join(REPO, "build", "found", "test-config", "no-own-empty.tsv")
local empty_file = assert(io.open(empty_no_own, "w")); empty_file:write("# none\n"); empty_file:close()
local refusal = nil
try {
    function ()
        os.runv("xmake", {"l", IR}, {envs = {IR_SDK = path.join(ROOT, "fixture", "sdk"), IR_CONFIG = FIXTURE_CONFIG,
            IR_MODE = "check", IR_SPEC = SPEC, IR_CONFLICTS = path.join(ROOT, "conflicts.tsv"), IR_UNPARSED = path.join(ROOT, "unparsed.tsv"),
            IR_NO_OWN = empty_no_own}})
    end,
    catch {
        function (errors) refusal = tostring(errors) end
    }
}
expect(refusal ~= nil and refusal:find("FixtureUmbrella", 1, true) ~= nil,
    "ir.lua refuses a framework with no shard that is neither unparsed nor in no-own.tsv, and the error names it")

-- 1. the driver reproduces the golden exactly (check mode: nothing is written)
-- the full IR (the build product, with decl) is written to the build directory: the declaration text is checked there
local FULL = path.join(REPO, "build", "found", "test-ir.tsv")
os.runv("xmake", {"l", IR}, {envs = {IR_SDK = path.join(ROOT, "fixture", "sdk"), IR_CONFIG = FIXTURE_CONFIG, IR_NO_OWN = path.join(FIXTURE_CONFIG, "no-own.tsv"), IR_MODE = "check",
    IR_SPEC = SPEC, IR_CONFLICTS = path.join(ROOT, "conflicts.tsv"), IR_UNPARSED = path.join(ROOT, "unparsed.tsv"),
    IR_FULL = FULL}})
checks = checks + 1

-- the declaration text of a usr, from the full IR
local function decl_of(usr)
    for line in io.lines(FULL) do
        local c = {}
        for cell in (line .. "\t"):gmatch("([^\t]*)\t") do table.insert(c, cell) end
        if c[3] == usr then return c[17] end
    end
    return nil
end

-- every cell of the full IR row of a usr (the parameters, the nullability and the value included)
local function full_of(usr)
    for line in io.lines(FULL) do
        local c = {}
        for cell in (line .. "\t"):gmatch("([^\t]*)\t") do table.insert(c, cell) end
        if c[3] == usr then return c end
    end
    return nil
end

-- 2. the golden shards, decoded: one row per declaration, the name and the side as the IR has them
local rows = {}
for _, file in ipairs({path.join(SPEC, "Fixture", "declarations.tsv"), path.join(SPEC, "Fixture", "Inner", "declarations.tsv")}) do
    local framework = file:find("/Inner/", 1, true) and "Fixture/Inner" or "Fixture"
    for line in io.lines(file) do
        if not line:find("^#") then
            local c = {}
            for cell in (line .. "\t"):gmatch("([^\t]*)\t") do table.insert(c, cell) end
            expect(#c == 12, "every shard row has 12 columns (the value is the twelfth): " .. line)
            local name, side = shard.decode(c[1], c[2], c[4], c[5])
            table.insert(rows, {framework = framework, kind = c[1], usr = c[2], container = c[3], name = name, side = side,
                type = c[6], params = c[7], attrs = c[8], avail = c[9], message = c[10], hash = c[11]})
        end
    end
end

local function find(predicate)
    local out = {}
    for _, r in ipairs(rows) do
        if predicate(r) then table.insert(out, r) end
    end
    return out
end

local function count(predicate, expected, message)
    expect(#find(predicate) == expected, message .. " (found " .. #find(predicate) .. ")")
end

-- repeated declarations: emitted once (Repeat.h precedes Fixture.h in the translation unit)
count(function (r) return r.usr == "c:@F@FXRun" end, 1, "FXRun is one function")
expect(decl_of("c:@F@FXRun") == "void FXRun(int total)", "FXRun is emitted from Repeat.h")
count(function (r) return r.usr == "c:Repeat.h@T@FXCount" and r.kind == "typedef" end, 1, "FXCount is one typedef")
-- the typed columns (ruling of 2026-10-10, per column): the type of every row and the attributes of a property are in the shard
expect(find(function (r) return r.usr == "c:Repeat.h@T@FXCount" end)[1].type == "int", "a typedef row keeps its underlying type")
expect(find(function (r) return r.usr == "c:Fixture.h@T@FXOpaque" end)[1].type == "struct FXOpaque",
    "an opaque typedef keeps the struct it names")
local widget_named = find(function (r) return r.usr == "c:objc(cs)FXWidget(cm)widgetNamed:" end)[1]
expect(widget_named.type == "instancetype", "a method keeps its return type")
expect(find(function (r) return r.usr == "c:@F@FXRun" end)[1].params == "int total", "a function keeps its parameter types and names")
-- the type of a declared variable (ruling of 2026-10-10, the const fix): the top-level const of the declared type is in it, a pointer's
-- const follows the star, and an attribute macro in front of the type is not part of it
local function type_of_var(usr)
    return find(function (r) return r.usr == usr end)[1].type
end
expect(type_of_var("c:@FXConstName") == "const FXStringRef", "a const variable of a typedef keeps its const")
expect(type_of_var("c:@FXConstPointer") == "const char *const", "a const pointer to const keeps both")
expect(type_of_var("c:@FXPointerConst") == "char *const", "a const pointer keeps its const after the star")
expect(type_of_var("c:@FXPointerToConst") == "const char *", "a pointer to const keeps its const before the star")
expect(type_of_var("c:@FXConstInt") == "const int", "a const integer keeps its const")
expect(type_of_var("c:@FXMacroConst") == "const FXStringRef", "an attribute macro in front of a variable's type is not part of the type")
expect(type_of_var("c:@FXMacroPointer") == "char *const", "an attribute macro does not hide a pointer's const")
expect(type_of_var("c:@FXRefinedName") == "const FXStringRef", "a Swift attribute macro in front of the type is not part of it")
expect(full_of("c:@FXConstName")[10] == "n", "a nullability word stays in the nullability column, not the type")
-- the macro words of the declared types of methods, properties, parameters, functions and typedefs (the rule of 2026-10-10)
local function type_of_usr(usr)
    return find(function (r) return r.usr == usr end)[1].type
end
expect(type_of_usr("c:Repeat.h@T@FXStringAlias") == "FXStringRef", "a typedef's underlying type is spelled without its macro")
expect(type_of_usr("c:@F@FXFetch") == "FXStringRef (const char *)", "a function's result and parameters are spelled without their macros")
expect(find(function (r) return r.usr == "c:@F@FXFetch" end)[1].params == "const char * key", "a function's parameter keeps its type and name")
expect(type_of_usr("c:objc(cs)FXMacroBox(py)macroProperty") == "const FXStringRef", "a property's type is spelled without its macro, const kept")
expect(type_of_usr("c:objc(cs)FXMacroBox(im)macroReturn") == "FXStringRef", "a method's result is spelled without its macro")
local take = find(function (r) return r.usr == "c:objc(cs)FXMacroBox(im)macroTake:" end)[1]
expect(take.params == "const char * value", "a method's parameter is spelled without its macro")
expect(type_of_usr("c:Repeat.h@T@FXBlock") == "id ((^))(int)", "a block typedef is spelled with its block marker, without macros or nullability")
-- the columns no committed stage reads stay in the full IR: the nullability (the value is in the shard, ruling 2)
expect(full_of("c:objc(cs)FXWidget(cm)widgetNamed:")[10] == "-|l",
    "a method's nullability is the result, then the parameters (full IR)")
expect(full_of("c:@E@FXState@FXStateOn")[14] == "1", "an enum constant keeps its value (full IR)")
expect(find(function (r) return r.usr == "c:@FXScale" end)[1].type == "const double", "a qualifier is part of the type")
local enabled_row = find(function (r) return r.usr == "c:objc(cs)FXWidget(py)enabled" end)[1]
expect(enabled_row.attrs == "readonly,nonatomic,getter=isEnabledNow" and enabled_row.type == "_Bool",
    "a property keeps its attributes and its type")
count(function (r) return r.type == "" end, 0, "every row fills its type cell")
count(function (r) return r.usr == "c:@E@FXState" end, 1, "FXState is one enum (definition only)")
count(function (r) return r.usr == "c:@S@FXOpaque" end, 1, "FXOpaque is one struct")

-- declarations outside the module's header set, or in a branch the target does not compile
count(function (r) return r.usr == "c:@F@FXPrivateOnly" or r.usr == "c:@F@FXTextualOnly" end, 0,
    "private and textual headers are not emitted")
count(function (r) return r.usr:find("FXOnlyIntel", 1, true) ~= nil end, 0, "the x86_64 branch is not emitted")
count(function (r) return r.usr == "c:@F@FXSubtract" end, 1, "a submodule header is emitted")

-- a macro-produced declaration: written as the macro, its availability kept
local init = find(function (r) return r.usr == "c:objc(cs)FXWidget(im)init" end)
expect(#init == 1 and init[1].avail == "*unavailable" and decl_of("c:objc(cs)FXWidget(im)init") == "FX_NO_INIT",
    "the macro-produced init is as spelled")
local widget = find(function (r) return r.usr == "c:objc(cs)FXWidget(cm)widgetNamed:" end)
expect(widget[1].avail == "ios=16.0/-/-/0", "the availability version is read (" .. widget[1].avail .. ")")
expect(widget[1].side == "+" and widget[1].name == "widgetNamed:", "a class method's side and selector are read back")
local enabled = find(function (r) return r.usr == "c:objc(cs)FXWidget(py)enabled" end)
expect(decl_of("c:objc(cs)FXWidget(py)enabled"):find("getter=isEnabledNow", 1, true) ~= nil, "the property declaration keeps its getter")

-- a getter clang synthesises from a property is an accessor in the full IR, and it is no row of the shards
count(function (r) return r.usr == "c:objc(cs)FXWidget(im)isEnabledNow" end, 0, "a synthesised getter is not in the shards")
local accessor = false
for line in io.lines(FULL) do
    if line:find("\taccessor\tc:objc%(cs%)FXWidget%(im%)isEnabledNow\t") then accessor = true end
end
expect(accessor, "a synthesised getter is an accessor row of the full IR")

-- the messages: a deprecation and an unavailability, as the message column carries them
local old_fn = find(function (r) return r.usr == "c:@F@FXOld" end)
expect(#old_fn == 1 and old_fn[1].message == "deprecated: Use newWay", "the deprecation message of an availability attribute")
local gone = find(function (r) return r.usr == "c:@F@FXGone" end)
expect(#gone == 1 and gone[1].message == "unavailable: removed in 2.0", "the unavailability message of an unavailable attribute")

-- resolution of repeated declarations (ruling D3): the stricter extension, the defining declaration, and the unresolved C function
local old = find(function (r) return r.usr == "c:objc(cs)FXLegacy(im)old" end)
expect(#old == 1 and old[1].avail == "ios=16.0/-/-/0", "a later extension availability overrides the class's")
local tweak = find(function (r) return r.usr == "c:objc(cs)FXLegacy(im)tweak" end)
expect(#tweak == 1 and tweak[1].avail == "ios=14.0/-/-/0", "an earlier extension availability is ignored")
-- two declarations of a C function that disagree are one merged row (avail.lua): the second names no availability in the IR (clang
-- drops an availability attribute that does not match the first declaration), so it carries no fact and the annotated one decides
count(function (r) return r.usr == "c:@F@FXVersioned" end, 1, "a merged C function is one row")
expect(find(function (r) return r.usr == "c:@F@FXVersioned" end)[1].avail == "ios=17.0/-/-/0",
    "the merged availability of the C function is the annotated declaration's")

-- categories: a class extension is keyed by its class name (no file or offset), its protocols belong to the class, and a named
-- category's members carry the category as their container
count(function (r) return r.usr == "c:objc(ext)FXWidget" and r.kind == "category" and r.name == "-" end, 1,
    "the class extension is keyed by its class name and has no name")
count(function (r) return r.kind == "conforms" and r.container == "FXWidget" and r.name == "FXSource" end, 1,
    "the class extension's protocol belongs to the class")
local extras = find(function (r) return r.usr == "c:objc(cs)FXWidget(im)extraAction" end)
expect(extras[1].container == "Extras", "a named category's member carries the category as its container")
expect(widget[1].container == "-", "a class member has no container")

-- a forward declaration of a protocol is not a declaration of the framework
count(function (r) return r.name == "FXLater" end, 0, "a forward-declared protocol is not emitted")

-- a nested framework is its own framework, labelled by its outer framework
count(function (r) return r.framework == "Fixture/Inner" and r.usr == "c:objc(cs)FXInner" end, 1,
    "the nested framework is labelled Fixture/Inner")

-- the reviewed lists: three conflicts, three unparsed frameworks, each reason without a host path
local conflicts = 0
for line in io.lines(path.join(ROOT, "conflicts.tsv")) do
    if not line:find("^framework\t") then conflicts = conflicts + 1 end
end
expect(conflicts == 3, "three conflicts are listed (found " .. conflicts .. ")")
local reasons = {}
for line in io.lines(path.join(ROOT, "unparsed.tsv")) do
    if not line:find("^#") then
        local name, reason = line:match("^([^\t]*)\t(.*)$")
        reasons[name] = reason
        expect(not reason:find("/Users/", 1, true) and not reason:find(".sdk", 1, true), "an unparsed reason carries no host path")
    end
end
expect(reasons.Broken and reasons.Broken:find("Missing.h", 1, true) ~= nil, "the broken header's reason names the missing header")
expect(reasons.NoHeader == "no public header in Headers/ and no module map header", "a framework with no header says so")
expect(reasons.Swiftonly == "no Objective-C or C header; Swift interface only", "a Swift-only framework says so")

-- the shard header records the libclang and the SDK
local header = io.lines(path.join(SPEC, "Fixture", "declarations.tsv"))()
expect(header:find("^#libclang=") ~= nil and header:find("sdk=sdk", 1, true) ~= nil, "the shard header records libclang and the SDK")

-- the facts the generator reads from the shards (facts.lua): the spec keys and the availability of the members, the superclass, and
-- the protocol conformance of the class extension
local facts = import("facts", {rootdir = FOUND, anonymous = true})
local members = facts.members(SPEC, "Fixture")
local byapi = {}
for _, m in ipairs(members) do byapi[m.api] = m end
expect(byapi["+[FXWidget widgetNamed:]"] ~= nil and byapi["+[FXWidget widgetNamed:]"].avail == "ios=16.0/-/-/0",
    "a class method's spec key and availability")
expect(byapi["-[FXWidget enabled]"] ~= nil and byapi["-[FXWidget enabled]"].alias == "FXWidget.enabled",
    "a property's spec key and alias")
expect(byapi["-[FXWidget extraAction]"] ~= nil and byapi["-[FXWidget extraAction]"].key == "Extras",
    "a category member keeps its category as key, under its class")
expect(byapi["-[FXLegacy old]"] ~= nil and byapi["-[FXLegacy old]"].avail == "ios=16.0/-/-/0", "the resolved availability is the fact")
expect(byapi["+[FXWidget widgetNamed:]"].text == "API_AVAILABLE(ios(16.0))", "a member's availability text is rendered from its fields")
expect(byapi["-[FXWidget isEnabledNow]"] == nil and byapi["+[FXWidget label]"] == nil and byapi["-[FXWidget setLabel:]"] == nil,
    "the accessors synthesised from a property are not members: the property is")
local conforms = facts.conformances(SPEC, "Fixture")
expect(#conforms == 1 and conforms[1].cls == "FXWidget" and conforms[1].protocol == "FXSource", "the conformance fact")
local typedef_fact = nil
for _, t in ipairs(facts.typedefs(SPEC, "Fixture")) do
    if t.name == "FXCount" then typedef_fact = t end
end
expect(typedef_fact ~= nil and typedef_fact.type == "int", "the typedef fact carries the underlying type")

-- the availability rule for the merged conflicts (introduced: the earliest declaration; deprecated and obsoleted: the latest, and only
-- when every declaration that is available on the platform says so; unavailable only when every declaration says so; a declaration
-- that names no platform is available since the beginning) and the render contract (ruling D7), on synthetic inputs
local avail = import("avail", {rootdir = FOUND, anonymous = true})
local function eq(actual, expected, message)
    expect(actual == expected, message .. " (got [" .. tostring(actual) .. "], want [" .. expected .. "])")
end
local function row(a, m) return {avail = a, message = m or ""} end

-- the OpenGLES entry point: introduced 2.0 on iOS (the earliest), deprecated 12.0 everywhere
eq(avail.merge({row("ios=2.0/12.0/-/0,tvos=9.0/12.0/-/0"), row("tvos=9.0/12.0/-/0"), row("ios=3.0/12.0/-/0,tvos=9.0/12.0/-/0")}).avail,
    "ios=2.0/12.0/-/0,tvos=9.0/12.0/-/0", "introduced is the earliest, deprecated is kept when every declaration deprecates")
-- a platform one declaration does not name keeps the other's introduction; the unnamed one says nothing about it
eq(avail.merge({row("ios=-/-/-/1,macos=13.3/-/-/0,tvos=-/-/-/1,watchos=-/-/-/1"),
    row("ios=17.4/-/-/0,maccatalyst=16.6/-/-/0,macos=13.5/-/-/0,tvos=-/-/-/1,watchos=-/-/-/1")}).avail,
    "ios=17.4/-/-/0,maccatalyst=16.6/-/-/0,macos=13.3/-/-/0,tvos=-/-/-/1,watchos=-/-/-/1",
    "an unavailable declaration does not introduce; the earliest available introduction wins")
eq(avail.merge({row("ios=2.0/-/-/0,watchos=-/-/-/1"), row("ios=17.0/-/-/0,tvos=17.0/-/-/0,watchos=-/-/-/1")}).avail,
    "ios=2.0/-/-/0,tvos=17.0/-/-/0,watchos=-/-/-/1", "a platform named by one declaration takes that declaration's introduction")
-- deprecated only when every available declaration says so
eq(avail.merge({row("ios=2.0/9.0/-/0"), row("ios=3.0/-/-/0")}).avail, "ios=2.0/-/-/0", "one declaration not deprecating: not deprecated")
eq(avail.merge({row("ios=2.0/9.0/-/0"), row("ios=3.0/12.0/-/0")}).avail, "ios=2.0/12.0/-/0", "every declaration deprecating: the latest deprecation")
-- obsoleted follows deprecated
eq(avail.merge({row("ios=2.0/-/9.0/0"), row("ios=2.0/-/11.0/0")}).avail, "ios=2.0/-/11.0/0", "obsoleted: the latest, when every declaration obsoletes")
-- available if any declaration is available; unavailable only when every declaration is
eq(avail.merge({row("ios=-/-/-/1"), row("ios=5.0/-/-/0")}).avail, "ios=5.0/-/-/0", "available if any declaration is available")
eq(avail.merge({row("ios=-/-/-/1"), row("ios=-/-/-/1")}).avail, "ios=-/-/-/1", "unavailable when every declaration is")
-- a declaration that names no platform at all carries no availability fact: it does not vote, and the annotated one decides
-- (ruling of 2026-10-10: the OpenGLES entry point glResolveMultisampleFramebufferAPPLE and the PDFKit typedef PDFSelectionGranularity)
eq(avail.merge({row("-"), row("ios=4.0/12.0/-/0,tvos=9.0/12.0/-/0")}).avail, "ios=4.0/12.0/-/0,tvos=9.0/12.0/-/0",
    "an unannotated declaration is ignored: the annotated OpenGLES entry decides")
eq(avail.merge({row("-"), row("ios=18.0/-/-/0")}).avail, "ios=18.0/-/-/0",
    "an unannotated declaration is ignored: the annotated PDFKit typedef decides")
eq(avail.merge({row("-"), row("-")}).avail, "-", "when no declaration is annotated the key has no availability")
-- F7 (review-v-gen): an unannotated row carries no flag and no platform, so it does not vote in the flags either
eq(avail.merge({row("*unavailable"), row("-")}).avail, "*unavailable", "an unannotated row does not clear the unavailable flag")
eq(avail.merge({row("*deprecated"), row("-")}).avail, "*deprecated", "an unannotated row does not clear the deprecated flag")
eq(avail.merge({row("*unavailable"), row("ios=5.0/-/-/0")}).avail, "ios=5.0/-/-/0",
    "a row that names a platform without the flag still clears the flag for it")
eq(avail.merge({row("-"), row("ios=4.0/12.0/-/0", "deprecated: Gone"), row("-", "deprecated: Other")}).message,
    "deprecated: Gone", "an unannotated declaration's message is not the key's message")
-- the message follows the latest deprecation
eq(avail.merge({row("ios=2.0/9.0/-/0", "deprecated: A"), row("ios=2.0/12.0/-/0", "deprecated: B")}).message, "deprecated: B",
    "the message of the declaration that gives the latest deprecation")

-- the render contract (D7): the macros in a fixed order, the platforms sorted, the deprecation message quoted
eq(avail.render("ios=16.0/-/-/0,macos=13.0/-/-/0", ""), "API_AVAILABLE(ios(16.0), macos(13.0))", "available platforms")
eq(avail.render("ios=2.0/9.0/-/0", "deprecated: Use Y"), 'API_DEPRECATED("Use Y", ios(2.0, 9.0))', "a deprecation with its message")
eq(avail.render("ios=-/-/-/1", ""), "API_UNAVAILABLE(ios)", "an unavailable platform")
eq(avail.render("ios=2.0/-/9.0/0", ""), "API_OBSOLETED(ios(2.0, 9.0))", "an obsoleted platform")
eq(avail.render("ios=2.0/-/-/0,macos=10.0/12.0/-/0,tvos=-/-/-/1", "deprecated: M"),
    'API_AVAILABLE(ios(2.0)) API_DEPRECATED("M", macos(10.0, 12.0)) API_UNAVAILABLE(tvos)', "the four macros in order")
eq(avail.render("-", ""), "", "an unannotated declaration renders nothing")
eq(avail.render("*deprecated", "deprecated: Gone"), 'API_DEPRECATED("Gone")', "a deprecation of every platform, without platforms")
eq(avail.render("*unavailable", ""), "API_UNAVAILABLE", "an unavailability of every platform, without platforms")
eq(avail.render("*unavailable ios=-/-/-/1", ""), "API_UNAVAILABLE(ios)", "a flagged unavailability that names its platforms renders them")

-- the message cell: a deprecation text may itself contain " | " (a replacement list), so the unavailability text is the suffix
local dep, unav = avail.split_message("deprecated: Use A | B instead")
expect(dep == "Use A | B instead" and unav == nil, "a deprecation text that contains the separator stays whole")
dep, unav = avail.split_message("deprecated: X | unavailable: Y")
expect(dep == "X" and unav == "Y", "a deprecation and an unavailability text, in that order")
dep, unav = avail.split_message("unavailable: removed in 2.0")
expect(dep == nil and unav == "removed in 2.0", "an unavailability text alone")

-- the doc-time mode (ir.lua's docs mode, which runs decls --doc over the fixture): one line per declaration of ten escaped cells, the
-- doc comment's brief and raw text, the parameter names and the declaration as written; nothing is written
local docs = os.iorunv("xmake", {"l", IR}, {envs = {IR_SDK = path.join(ROOT, "fixture", "sdk"), IR_CONFIG = FIXTURE_CONFIG, IR_MODE = "docs"}})
local doc_lines = {}
for line in docs:gmatch("[^\n]+") do
    if line:find("\t", 1, true) then table.insert(doc_lines, line) end
end
local function doc_cells(line)
    local c = {}
    for cell in (line .. "\t"):gmatch("([^\t]*)\t") do table.insert(c, cell) end
    return c
end
for _, line in ipairs(doc_lines) do
    expect(#doc_cells(line) == 10, "every doc row has 10 cells: " .. line)
end
local function doc_of(usr)
    for _, line in ipairs(doc_lines) do
        local c = doc_cells(line)
        if c[3] == usr then return c end
    end
    return nil
end
local run_doc = doc_of("c:@F@FXRun")
expect(run_doc ~= nil and run_doc[8] == "Runs the total. The total is added to the sum.", "a doc row carries the brief as clang parses it")
expect(run_doc ~= nil and run_doc[9]:find("\\n", 1, true) ~= nil, "the raw doc comment is one cell, its line breaks escaped")
expect(run_doc ~= nil and run_doc[7] == "total" and run_doc[10] == "void FXRun(int total)",
    "a doc row carries the parameter names and the declaration as written")
local widget_doc = doc_of("c:objc(cs)FXWidget(cm)widgetNamed:")
expect(widget_doc ~= nil and widget_doc[7] == "name" and widget_doc[8] == "", "a method with no doc comment has an empty brief")
expect(doc_of("c:@FXPointerToConst") ~= nil and doc_of("c:@FXPointerToConst")[9] == "", "a declaration with no comment has an empty raw text")
-- the doc comments are the ones clang attaches: ///, //!, /** */ and /*! (the forms the SDK's headers use); an ordinary // comment above
-- FXCount is not one of them, so the raw text is the //! line alone
local double_doc = doc_of("c:@F@FXDouble")
expect(double_doc ~= nil and double_doc[8] == "Doubles a value." and double_doc[9] == "/// Doubles a value.",
    "a /// doc comment is kept, with its brief")
local count_doc = doc_of("c:Repeat.h@T@FXCount")
expect(count_doc ~= nil and count_doc[8] == "Counts the items." and count_doc[9] == "//! Counts the items.",
    "a //! doc comment is kept, and an ordinary // comment above it is not")
local halve_doc = doc_of("c:@F@FXHalve")
expect(halve_doc ~= nil and halve_doc[8] == "Halves a value." and halve_doc[9] == "/*! Halves a value. */",
    "a /*! doc comment is kept, with its brief")

-- the usr/include module (ruling of 2026-10-10): its shard holds the declarations written in its own directory; the module map's
-- other module (FixtureCExtra) and a header of another directory (FixtureOther) are not the module's own
local usr_shard = {}
for line in io.lines(path.join(SPEC, "FixtureC", "declarations.tsv")) do
    if not line:find("^#") then table.insert(usr_shard, line) end
end
local function shard_has(name)
    for _, line in ipairs(usr_shard) do
        if doc_cells(line)[2] == name then return true end
    end
    return false
end
expect(shard_has("c:@F@fc_add") and shard_has("c:@T@fc_count"), "a usr/include module's shard holds the declarations of its own directory")
expect(not shard_has("c:@F@fc_other") and not shard_has("c:@F@fc_extra"),
    "a declaration of another directory, or of another module in the same map, is not in the module's shard")
local usr_doc = false
for _, line in ipairs(doc_lines) do
    if line:find("^FixtureC\t") then usr_doc = true end
end
expect(usr_doc, "the doc mode covers the usr/include module")

-- the extractor takes a framework name and resolves its headers itself (decls --doc <Framework>): the list, the target and the doc rows of
-- one framework are the ones the sweep and the doc pass use
local fixture_env = {IR_SDK = path.join(ROOT, "fixture", "sdk"), IR_CONFIG = FIXTURE_CONFIG}
local names = {}
for line in os.iorunv(DECLS, {"--list"}, {envs = fixture_env}):gmatch("[^\n]+") do
    table.insert(names, line:match("^([^\t]+)"))
end
expect(table.concat(names, " ") == "Broken Fixture Fixture/Inner FixtureC FixtureFallback FixtureSub FixtureUmbrella FixtureUmbrella/FixtureNested NoHeader Plain Swiftonly", "decls --list names the sweep's frameworks")
-- F11 (review-v-gen): a directory the walk cannot read is an error that names its path, not a shorter framework list. The fixture's
-- nested Frameworks/ folder is made unreadable for this check, and its mode is restored after it.
local nested_frameworks = path.join(ROOT, "fixture", "sdk", "System", "Library", "Frameworks", "Fixture.framework", "Frameworks")
os.iorunv("chmod", {"000", nested_frameworks})
local unreadable_failure = nil
try {
    function () os.iorunv(DECLS, {"--list"}, {envs = fixture_env}) end,
    catch {
        function (errors) unreadable_failure = tostring(errors) end
    }
}
os.iorunv("chmod", {"755", nested_frameworks})
expect(unreadable_failure ~= nil and unreadable_failure:find("Frameworks", 1, true) ~= nil,
    "an unreadable framework folder is an error that names its path")
-- F10 (review-v-gen): the target comes from the SDK's version (SDKSettings.json: arm64, the SDK's vendor and system, its deployment
-- target), not from a literal; the fixture's SDK is version 26.4
expect(os.iorunv(DECLS, {"--target"}, {envs = fixture_env}) == "arm64-apple-ios26.4\n", "decls --target is derived from the SDK's version")
-- F8 (review-v-gen): the libclang that runs is identified by the SHA-256 of its dylib, which the shard headers record
local identity = os.iorunv(DECLS, {"--version"})
local dylib_sha = identity:match("dylib%-sha256=(%x+)")
expect(dylib_sha ~= nil and #dylib_sha == 64, "decls --version names the SHA-256 of the libclang it runs (got " .. identity:gsub("\n", " ") .. ")")
local function rows_of(text, name)
    local out = {}
    for line in text:gmatch("[^\n]+") do
        if line:sub(1, #name + 1) == name .. "\t" then table.insert(out, line) end
    end
    return table.concat(out, "\n")
end
local direct = os.iorunv(DECLS, {"--doc", "Fixture"}, {envs = fixture_env})
expect(direct ~= "" and rows_of(direct, "Fixture") == rows_of(docs, "Fixture"),
    "decls --doc Fixture gives the rows the doc pass gives for Fixture")

-- F24 (review-v-gen): the platform records of a declaration are all kept: clang reports at most 14 on this compiler (measured: 17 attributes,
-- 14 records; repeated attributes of one platform give one record), so the extractor sizes the array from the count, not a fixed 16
local many_avail = find(function (r) return r.usr == "c:@F@FXManyPlatforms" end)[1].avail
local many_count = 0
for _ in string.gmatch(many_avail, "[^,]+") do many_count = many_count + 1 end
expect(many_count == 14, "every platform record clang reports is kept (got " .. many_count .. ")")

-- F9 (review-v-gen): the declaration hash is the SHA-256 of the canonical text of the cells the IR writes: the ten fields, each followed
-- by the unit separator (0x1f), first 16 hex digits (design-foundation.md 5.3). Recomputed here with shasum, through a pipe, for every
-- declaration row of the full IR; the hash must not depend on whether a field is empty in the extractor's memory.
local function shasum16(text)
    local out = os.iorunv("/bin/sh", {"-c", "printf '%s' \"$1\" | shasum -a 256 | cut -c1-16", "sh", text})
    return (out:gsub("%s+$", ""))
end
local hash_checked, hash_mismatch = 0, {}
for line in io.lines(FULL) do
    local c = {}
    for cell in (line .. "\t"):gmatch("([^\t]*)\t") do table.insert(c, cell) end
    if c[2] ~= "census" and c[2] ~= "unparsed" and c[2] ~= "conflict" and c[2] ~= "meta" and c[15] and c[15] ~= "" then
        local canonical = {}
        for _, i in ipairs({2, 3, 4, 5, 6, 11, 12, 10, 13, 14}) do table.insert(canonical, c[i] .. "\31") end
        hash_checked = hash_checked + 1
        local expected = shasum16(table.concat(canonical))
        if expected ~= c[15] then table.insert(hash_mismatch, c[2] .. " " .. c[3] .. " " .. c[15] .. " != " .. expected) end
    end
end
expect(hash_checked > 0 and #hash_mismatch == 0,
    string.format("every declaration hash is the SHA-256 of its canonical cells (%d checked, %d differ: %s)",
        hash_checked, #hash_mismatch, table.concat(hash_mismatch, "; ", 1, math.min(3, #hash_mismatch))))

print(string.format("extractor tests passed: %d checks", checks))
