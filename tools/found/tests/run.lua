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
os.runv("xmake", {"l", "./tools/found/ir.lua"}, {envs = {IR_SDK = path.join(ROOT, "fixture", "sdk"), IR_MODE = "check",
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

-- 2. the golden shards, decoded: one row per declaration, the name and the side as the IR has them
local rows = {}
for _, file in ipairs({path.join(SPEC, "Fixture", "declarations.tsv"), path.join(SPEC, "Fixture", "Inner", "declarations.tsv")}) do
    local framework = file:find("/Inner/", 1, true) and "Fixture/Inner" or "Fixture"
    for line in io.lines(file) do
        if not line:find("^#") then
            local c = {}
            for cell in (line .. "\t"):gmatch("([^\t]*)\t") do table.insert(c, cell) end
            expect(#c == 8, "every shard row has 8 columns: " .. line)
            local name, side = shard.decode(c[1], c[2], c[4], c[5])
            table.insert(rows, {framework = framework, kind = c[1], usr = c[2], container = c[3], name = name, side = side,
                avail = c[6], message = c[7], hash = c[8]})
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
-- two declarations of a C function that disagree are one merged row (avail.lua): the second declares no availability here (clang
-- drops an availability attribute that does not match the first declaration), so the first is not unrestricted and the rule
-- makes the function unannotated
count(function (r) return r.usr == "c:@F@FXVersioned" end, 1, "a merged C function is one row")
expect(find(function (r) return r.usr == "c:@F@FXVersioned" end)[1].avail == "-", "the merged availability of the C function")

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
-- a declaration that names no platform at all is available since the beginning, so an unrestricted platform stays unrestricted
eq(avail.merge({row("-"), row("ios=18.0/-/-/0")}).avail, "-", "an unannotated declaration makes the platform available since the beginning")
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

print(string.format("extractor tests passed: %d checks", checks))
