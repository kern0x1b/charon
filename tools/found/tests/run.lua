-- Tests of the declaration extractor: the driver (ir.lua) runs over tests/fixture/sdk, a small SDK with each case the extractor must
-- handle. Its output must equal the reviewed golden shards (tests/expected), the reviewed conflict list (tests/conflicts.tsv) and the
-- unparsed list (tests/unparsed.tsv), and named facts about the golden are checked. The golden records the libclang of the machine it
-- was made on; on another machine the check fails and names the difference, which is the toolchain pin working.
--
-- usage (from the repository root): xmake l ./tools/found/tests/run.lua
local ROOT = "tools/found/tests"
local SPEC = path.join(ROOT, "expected")
local shard = import("shard", {rootdir = path.join("tools", "found"), anonymous = true})
local checks = 0

local function expect(condition, message)
    checks = checks + 1
    if not condition then raise("test failed: " .. message) end
end

-- 1. the driver reproduces the golden exactly (check mode: nothing is written)
-- the full IR (the build product, with decl) is written to the build directory: the declaration text is checked there
local FULL = path.join("build", "found", "test-ir.tsv")
os.runv("xmake", {"l", "./tools/found/ir.lua"}, {envs = {IR_SDK = path.join(ROOT, "fixture", "sdk"), IR_USR_MODULES = "FixtureC", IR_MODE = "check",
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
            expect(#c == 11, "every shard row has 11 columns: " .. line)
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
-- the columns no committed stage reads stay in the full IR: the nullability and the value
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
local facts = import("facts", {rootdir = path.join("tools", "found"), anonymous = true})
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
local avail = import("avail", {rootdir = path.join("tools", "found"), anonymous = true})
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
local docs = os.iorunv("xmake", {"l", "./tools/found/ir.lua"}, {envs = {IR_SDK = path.join(ROOT, "fixture", "sdk"), IR_USR_MODULES = "FixtureC", IR_MODE = "docs"}})
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
expect(doc_of("c:Repeat.h@T@FXCount") ~= nil and doc_of("c:Repeat.h@T@FXCount")[9] == "", "a declaration with no comment has an empty raw text")
-- the doc comment forms are /// and /** */ only (ruling of 2026-10-10): FXCount's //! comment is not kept, FXDouble's /// is
local double_doc = doc_of("c:@F@FXDouble")
expect(double_doc ~= nil and double_doc[8] == "Doubles a value." and double_doc[9] == "/// Doubles a value.",
    "a /// doc comment is kept, with its brief")
expect(doc_of("c:Repeat.h@T@FXCount")[8] == "", "a //! comment is not a doc comment: no brief")

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
local DECLS = path.join("build", "macosx", "arm64", "release", "decls")
local fixture_env = {IR_SDK = path.join(ROOT, "fixture", "sdk"), IR_USR_MODULES = "FixtureC"}
local names = {}
for line in os.iorunv(DECLS, {"--list"}, {envs = fixture_env}):gmatch("[^\n]+") do
    table.insert(names, line:match("^([^\t]+)"))
end
expect(table.concat(names, " ") == "Broken Fixture Fixture/Inner FixtureC NoHeader Swiftonly", "decls --list names the sweep's frameworks")
expect(os.iorunv(DECLS, {"--target"}) == "arm64-apple-ios26.2\n", "decls --target is the pinned target")
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

print(string.format("extractor tests passed: %d checks", checks))
