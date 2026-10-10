-- The classes of the differing cells of the constant records (Round 14, decision 1): one fixed fixture per class of tools/gen/classify.lua.
-- A case is the header text its truth is read from, the cells of one name and the class its target cell must get. Each case is run
-- twice: the rules give the class, and with that class's rule switched off the target cell is no longer that class (so the fixture
-- depends on the rule). CLASSIFY_MUTANT=<class> switches that class's rule off for the whole run: the test must then fail.
-- Run from anywhere: xmake l tests/gen/classify_test.lua (exits 1 on failure). Every class of CLASSES has at least one case.

local ROOT = path.absolute(path.join(os.scriptdir(), "..", ".."))
local TOOLS = path.join(ROOT, "tools")
local classify = import("gen.classify", {rootdir = TOOLS, anonymous = true})

-- The digests are the record writer's: digest("constant", api, decl, availability), computed with shasum over the same parts
local H_DECL = "d313a8c89b2ef8b6"
local H_CS_LUA = "b83ebbb08756aead"
local H_CS_REF = "539cb819c69aebeb"

local COND_HEADER = [[
#if defined(TARGET_OS_VISION) && TARGET_OS_VISION
extern NSString *const SomeName API_AVAILABLE(ios(9.0)) API_UNAVAILABLE(visionos);
#else
extern NSString *const SomeName API_AVAILABLE(ios(9.0));
#endif
]]

-- CoreSpotlight's CSSuggestion.h, the statement of CSSuggestionHighlightAttributeName (its NS_SWIFT_NAME is on the line above)
local CS_HEADER = [[
NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(suggestionHighlight)
CORESPOTLIGHT_EXPORT NSAttributedStringKey const CSSuggestionHighlightAttributeName API_AVAILABLE(macos(13.0), ios(16.0)) CS_TVOS_UNAVAILABLE;
]]

local TWO_LINE_HEADER = "extern NSString *const SomeName API_AVAILABLE(macos(10.0))\nAPI_DEPRECATED(ios(12.0));"

local CASES = {
    {class = "decl-whitespace", api = "SomeName", cells = {{column = "type", lval = "NSString *const", rval = "NSString*const"}}},
    {class = "decl-const-order", api = "SomeName",
     cells = {{column = "type", lval = "const NSAttributedStringKey", rval = "NSAttributedStringKey const"}}},
    {class = "decl-typedef-const", api = "SecKeyAlgorithm", header = "typedef NSString *const SecKeyAlgorithm;",
     cells = {{column = "type", lval = "const SecKeyAlgorithm", rval = "SecKeyAlgorithm"}}},
    {class = "decl-oracle-no-decl", api = "SomeName", header = "extern NSString *const SomeName;",
     cells = {{column = "type", lval = "NSString *const", rval = "-"}}},
    {class = "decl-oracle-no-decl", api = "SomeName", header = "extern NSString *const SomeName;", target = 2,
     cells = {{column = "type", lval = "NSString *const", rval = "-"}, {column = "availability", lval = "API_AVAILABLE(ios(9.0))", rval = "-"}}},
    {class = "decl-oracle-macro-prefix", api = "SomeName", header = "CORESPOTLIGHT_EXPORT NSString *const SomeName;",
     cells = {{column = "type", lval = "NSString *const", rval = "CORESPOTLIGHT_EXPORT NSString *const"}}},
    {class = "decl-oracle-macro-trailing", api = "SomeName", header = "extern NSString *const CV_NONNULL SomeName;",
     cells = {{column = "type", lval = "NSString *const", rval = "NSString *const CV_NONNULL"}}},
    {class = "decl-oracle-bleed", api = "SomeName", header = "NSString *const SomeName;",
     cells = {{column = "type", lval = "NSString *const", rval = 'NSString *const OtherName API_DEPRECATED("SomeName is it", ios(1.0))'}}},
    {class = "decl-ir-macro-token", api = "SomeName", header = "extern NSString *const CV_NONNULL SomeName;",
     cells = {{column = "type", lval = "NSString *const CV_NONNULL", rval = "NSString *const"}}},
    {class = "avail-next-line", api = "SomeName", header = "extern NSString *const SomeName\nAPI_AVAILABLE(macos(10.0));",
     cells = {{column = "availability", lval = "API_AVAILABLE(macos(10.0))", rval = "-"}}},
    {class = "avail-reference-missed", api = "SomeName", header = "extern NSString *const SomeName API_AVAILABLE(macos(10.0));",
     cells = {{column = "availability", lval = "API_AVAILABLE(macos(10.0))", rval = "-"}}},
    {class = "avail-string-literal", api = "SomeName", header = 'extern NSString *const SomeName API_DEPRECATED("SomeName", ios(1.0));',
     cells = {{column = "availability", lval = 'API_DEPRECATED("SomeName", ios(1.0))', rval = 'API_DEPRECATED("OtherName replaces SomeName", ios(2.0))'}}},
    {class = "avail-name-line-prefix", api = "SomeName", header = TWO_LINE_HEADER,
     cells = {{column = "availability", lval = "API_AVAILABLE(macos(10.0)) API_DEPRECATED(ios(12.0))", rval = "API_AVAILABLE(macos(10.0))"}}},
    {class = "avail-name-line-subset", api = "SomeName", header = TWO_LINE_HEADER,
     cells = {{column = "availability", lval = "API_AVAILABLE(macos(10.0)) API_DEPRECATED(ios(12.0))", rval = "API_DEPRECATED(ios(12.0))"}}},
    {class = "avail-conditional-branch", api = "SomeName", header = COND_HEADER,
     cells = {{column = "availability", lval = "API_AVAILABLE(ios(9.0))", rval = "API_AVAILABLE(ios(9.0)) API_UNAVAILABLE(visionos)"}}},
    {class = "hash-follows-inputs", api = "SomeName", target = 2,
     cells = {{column = "type", lval = "NSString *const", rval = "NSString*const"},
              {column = "hash", lval = "aaaaaaaaaaaaaaaa", rval = "bbbbbbbbbbbbbbbb", lrow = {availability = "-", hash = "aaaaaaaaaaaaaaaa"}}}},
    {class = "hash-declared-text", api = "SomeName", header = "extern NSString *const SomeName API_AVAILABLE(ios(9.0));",
     cells = {{column = "hash", lval = H_DECL, rval = "0000000000000000", lrow = {availability = "API_AVAILABLE(ios(9.0))", hash = H_DECL}}}},
    {class = "hash-leading-macro", fw = "CoreSpotlight", api = "CSSuggestionHighlightAttributeName", header = CS_HEADER,
     cells = {{column = "hash", lval = H_CS_LUA, rval = H_CS_REF, lrow = {availability = "API_AVAILABLE(macos(13.0), ios(16.0))", hash = H_CS_LUA}}}},
    {class = "value-status-decl", api = "SomeName", header = "extern NSString *const SomeName;",
     cells = {{column = "value_status", lval = "found", rval = "numeric"}}},
    {class = "value-follows-status", api = "SomeName", header = "extern NSString *const SomeName;", target = 2,
     cells = {{column = "value_status", lval = "found", rval = "numeric"}, {column = "value", lval = "NSString", rval = "-"}}},
    {class = "owned-input", api = "SomeName", owned = {SomeName = "v-avmidi"},
     cells = {{column = "value_status", lval = "owned:v-avmidi", rval = "-"}}},
    {class = "owned-input", api = "SomeName", owned = {SomeName = "v-avmidi"},
     cells = {{column = "owned", lval = "v-avmidi", rval = "-"}}},
    {class = "measured-input", api = "SomeName", held = {SomeName = "16.0"},
     cells = {{column = "measured", lval = "16.0", rval = "-"}}},
    {class = "cache-drift", api = "SomeName", cells = {{column = "value_source", lval = "host-macos", rval = "ios-26.2-cache"}}},
    {class = "cache-drift", api = "SomeName", cache = {SomeName = "NSString"},
     cells = {{column = "value_source", lval = "ios-26.2-cache", rval = "host-macos"}}},
    {class = "shape-follows-decl", api = "SomeName", header = "extern NSString *const SomeName;", target = 2,
     cells = {{column = "value_status", lval = "found", rval = "numeric"}, {column = "shape", lval = "cf", rval = "ns"}}},
}

local mutant = os.getenv("CLASSIFY_MUTANT")
local failures = 0
local covered = {}

local function fail(what)
    failures = failures + 1
    print("classify FAIL: " .. what)
end

-- The cells of a case classified with one rule switched off (disabled), and the case's target cell
local function run(case, ctx, disabled)
    local fw = case.fw or "Fixture"
    local cells = {}
    for _, c in ipairs(case.cells) do
        table.insert(cells, {fw = fw, api = case.api, column = c.column, lval = c.lval, rval = c.rval, lrow = c.lrow})
    end
    classify.classify(cells, ctx, disabled)
    return cells[case.target or 1]
end

for i, case in ipairs(CASES) do
    local fw = case.fw or "Fixture"
    local ctx = classify.context({headers = {[fw] = case.header or ""}, cache = case.cache, held = case.held, owned = case.owned})
    local target = run(case, ctx, mutant)
    if target.cls ~= case.class then
        fail(string.format("case %d (%s): the target cell is %s", i, case.class, tostring(target.cls)))
    end
    if run(case, ctx, case.class).cls == case.class then
        fail(string.format("case %d (%s): the target cell is still %s with the rule switched off", i, case.class, case.class))
    end
    covered[case.class] = true
end

local classes = classify.class_list()
if #classes == 0 then
    fail("the class list is empty")
end
for _, def in ipairs(classes) do
    if not covered[def[1]] then
        fail("no case for class " .. def[1])
    end
end

print("classify test: " .. (failures == 0 and "OK" or ("FAIL " .. failures)) .. " (" .. #CASES .. " cases"
      .. (mutant and (", mutant " .. mutant) or "") .. ")")
if failures > 0 then
    os.exit(1)
end
