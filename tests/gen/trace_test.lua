-- Run test for the trace layer. The layer writes the stubs of a fixture framework, the host compiler builds them into a program, and
-- the program calls each stub through the Objective-C runtime. Each call logs its selector once to stderr and returns the safe
-- default: nil for an object, 0 for a scalar, NO for BOOL, a zeroed struct, and an NSError in the framework's own domain for an
-- NSError ** parameter. Setters are the selector the property names (setScope:). FKWidget is a class the release lacks: its class
-- object is generated, since every member is a stub. The fixture facts, superclasses included, are injected through headers.use, so no
-- header is parsed; the fixture header is written only so that the program compiles. The declaration rules and the stub text are
-- checked against the oracle's output.
-- Run: xmake l tests/gen/trace_test.lua (needs clang; exits 1 on any failure). Scratch files live in a folder under the system
-- temporary directory, removed when the test ends.

local TOOLS = path.join(os.scriptdir(), "..", "..", "tools")

local FRAMEWORK = "FixtureKit"
local FUNCTION_COLUMNS = {"api", "introduced", "status", "reasons", "returns", "params", "decl"}
local LEDGER_COLUMNS = {"kind", "lang", "api", "introduced", "header-introduced", "status", "needs", "reason"}
local SURFACE_COLUMNS = {"framework", "kind", "lang", "api", "introduced", "demand-rank", "demand-apps", "impl-lead"}

local HEADER = [==[#import <Foundation/Foundation.h>

@interface FKThing : NSObject
@property (nonatomic, readwrite) NSInteger scope;
@property (nonatomic, readwrite, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly, copy) NSString *name;
- (BOOL)setLevel:(NSInteger)level error:(NSError **)error;
- (NSArray *)items;
- (void)reset;
@end

NSInteger FKCountThings(NSInteger count, NSError **error);

// a class the release lacks: the trace layer defines it when every member is a stub
@interface FKWidget : NSObject
@property (nonatomic, readwrite) NSInteger count;
- (BOOL)refreshWithError:(NSError **)error;
@end
]==]

-- The members the header declares, as the oracle's member parse gives them: class, kind, api and declaration.
local MEMBERS = {
    {"FKThing", "property", "-[FKThing scope]", "@property (nonatomic, readwrite) NSInteger scope"},
    {"FKThing", "property", "-[FKThing enabled]", "@property (nonatomic, readwrite, getter=isEnabled) BOOL enabled"},
    {"FKThing", "property", "-[FKThing name]", "@property (nonatomic, readonly, copy) NSString *name"},
    {"FKThing", "method", "-[FKThing setLevel:error:]", "- (BOOL)setLevel:(NSInteger)level error:(NSError **)error"},
    {"FKThing", "method", "-[FKThing items]", "- (NSArray *)items"},
    {"FKThing", "method", "-[FKThing reset]", "- (void)reset"},
    {"FKWidget", "property", "-[FKWidget count]", "@property (nonatomic, readwrite) NSInteger count"},
    {"FKWidget", "method", "-[FKWidget refreshWithError:]", "- (BOOL)refreshWithError:(NSError **)error"},
}

-- The ledger rows of the release that lacks every member: the class and each member, by the api the ledger spells.
local LEDGER = {
    {"property", "FKThing.scope"}, {"property", "FKThing.enabled"}, {"property", "FKThing.name"},
    {"method", "-[FKThing setLevel:error:]"}, {"method", "-[FKThing items]"}, {"method", "-[FKThing reset]"},
    {"class", "FKWidget"}, {"property", "FKWidget.count"}, {"method", "-[FKWidget refreshWithError:]"},
}

-- The lines the program must log, each once, and nothing else.
local EXPECTED_LOG = {
    "unimplemented: FixtureKit -[FKWidget count]", "unimplemented: FixtureKit -[FKWidget setCount:]",
    "unimplemented: FixtureKit -[FKWidget refreshWithError:]",
    "unimplemented: FixtureKit -[FKThing setScope:]", "unimplemented: FixtureKit -[FKThing scope]",
    "unimplemented: FixtureKit -[FKThing isEnabled]", "unimplemented: FixtureKit -[FKThing setEnabled:]",
    "unimplemented: FixtureKit -[FKThing setLevel:error:]", "unimplemented: FixtureKit -[FKThing items]",
    "unimplemented: FixtureKit -[FKThing reset]", "unimplemented: FixtureKit -[FKThing name]",
    "unimplemented: FixtureKit FKCountThings",
}

local PROGRAM = [==[#import <FixtureKit/FixtureKit.h>
#include <stdio.h>

// the class itself is the framework's to define; every member is the trace layer's stub, in its category
@implementation FKThing
@end

// FKWidget is not defined here: the trace layer's class object is the only definition

static int failures = 0;

#define CHECK(cond, label) do { if (!(cond)) { failures++; printf("FAIL %s\n", label); } else { printf("ok   %s\n", label); } } while (0)

int main(void) {
    @autoreleasepool {
        FKThing *thing = [[FKThing alloc] init];
        CHECK([thing scope] == 0, "getter returns 0 for an integer property");
        [thing setScope:5];
        [thing setScope:6];
        CHECK([thing isEnabled] == NO, "getter with getter= returns NO for BOOL");
        [thing setEnabled:YES];
        NSError *error = nil;
        CHECK([thing setLevel:1 error:&error] == NO, "method with NSError ** returns NO");
        CHECK(error != nil && [[error domain] isEqualToString:@"FixtureKit.Unimplemented"] && [error code] == -1,
              "NSError ** is set in the framework's domain with code -1");
        CHECK([thing items] == nil, "method returning an object returns nil");
        [thing reset];
        CHECK([thing name] == nil, "readonly object property returns nil");
        NSError *countError = nil;
        FKWidget *widget = [[FKWidget alloc] init];
        CHECK([widget count] == 0, "class object: integer property returns 0");
        [widget setCount:2];
        NSError *widgetError = nil;
        CHECK([widget refreshWithError:&widgetError] == NO, "class object: method with NSError ** returns NO");
        CHECK(FKCountThings(3, &countError) == 0, "C function returns 0 for an integer result");
        CHECK(countError != nil && [[countError domain] isEqualToString:@"FixtureKit.Unimplemented"],
              "C function sets an NSError ** in the framework's domain");
    }
    return failures ? 1 : 0;
}
]==]

-- The stub text the oracle's stub_text writes for each case: the framework, the api, the kind, the selector, the type text, the kind
-- of the zero, the declaration, and the text (the oracle's output, copied).
local STUB_TEXT = {
    {"-[FKThing setLevel:error:]", "method", "setLevel:error:", "BOOL", "scalar", "- (BOOL)setLevel:(NSInteger)level error:(NSError **)error",
     [==[- (BOOL)setLevel:(NSInteger)level error:(NSError **)error { static BOOL charon_logged = NO; if (!charon_logged) { charon_logged = YES; fprintf(stderr, "unimplemented: FixtureKit %s\n", "-[FKThing setLevel:error:]"); } if (error) { *error = [NSError errorWithDomain:@"FixtureKit.Unimplemented" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"-[FKThing setLevel:error:] is not implemented by the port"}]; } return 0; }]==]},
    {"-[FKThing items]", "method", "items", "NSArray *", "object", "- (NSArray *)items",
     [==[- (NSArray *)items { static BOOL charon_logged = NO; if (!charon_logged) { charon_logged = YES; fprintf(stderr, "unimplemented: FixtureKit %s\n", "-[FKThing items]"); } return nil; }]==]},
    {"-[FKThing reset]", "method", "reset", "void", "void", "- (void)reset",
     [==[- (void)reset { static BOOL charon_logged = NO; if (!charon_logged) { charon_logged = YES; fprintf(stderr, "unimplemented: FixtureKit %s\n", "-[FKThing reset]"); }  }]==]},
    {"-[FKThing scope]", "property-get", "scope", "NSInteger", "scalar", "@property (nonatomic, readwrite) NSInteger scope",
     [==[- (NSInteger)scope { static BOOL charon_logged = NO; if (!charon_logged) { charon_logged = YES; fprintf(stderr, "unimplemented: FixtureKit %s\n", "-[FKThing scope]"); } return 0; }]==]},
    {"-[FKThing setScope:]", "property-set", "setScope:", "NSInteger", "void", "@property (nonatomic, readwrite) NSInteger scope",
     [==[- (void)setScope:(NSInteger)value { static BOOL charon_logged = NO; if (!charon_logged) { charon_logged = YES; fprintf(stderr, "unimplemented: FixtureKit %s\n", "-[FKThing setScope:]"); }  }]==]},
    {"-[FKThing rect]", "method", "rect", "CGRect", "struct", "- (CGRect)rect",
     [==[- (CGRect)rect { static BOOL charon_logged = NO; if (!charon_logged) { charon_logged = YES; fprintf(stderr, "unimplemented: FixtureKit %s\n", "-[FKThing rect]"); } return (CGRect){0}; }]==]},
    {"-[FKThing blank]", "method", "blank", "", "struct", "- (void)blank",
     [==[- (void)blank { static BOOL charon_logged = NO; if (!charon_logged) { charon_logged = YES; fprintf(stderr, "unimplemented: FixtureKit %s\n", "-[FKThing blank]"); } return (){0}; }]==]},
    {"FKCountThings", "function", "FKCountThings", "NSInteger", "scalar", "NSInteger FKCountThings(NSInteger count, NSError **error)",
     [==[NSInteger FKCountThings(NSInteger count, NSError **error) { static BOOL charon_logged = NO; if (!charon_logged) { charon_logged = YES; fprintf(stderr, "unimplemented: FixtureKit %s\n", "FKCountThings"); } if (error) { *error = [NSError errorWithDomain:@"FixtureKit.Unimplemented" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"FKCountThings is not implemented by the port"}]; } return 0; }]==]},
    {"FKMake", "function", "FKMake", "FKThing *", "object", "FKThing *FKMake(void)",
     [==[FKThing *FKMake(void) { static BOOL charon_logged = NO; if (!charon_logged) { charon_logged = YES; fprintf(stderr, "unimplemented: FixtureKit %s\n", "FKMake"); } return NULL; }]==]},
    {"-[FKThing copyWithError:]", "method", "copyWithError:", "id", "object", "- (id)copyWithError:(NSError * _Nullable * _Nullable)error",
     [==[- (id)copyWithError:(NSError * _Nullable * _Nullable)error { static BOOL charon_logged = NO; if (!charon_logged) { charon_logged = YES; fprintf(stderr, "unimplemented: FixtureKit %s\n", "-[FKThing copyWithError:]"); } return nil; }]==]},
}

local function checks()
    local failures, count = 0, 0
    local function check(ok, label)
        count = count + 1
        if not ok then
            failures = failures + 1
            print("FAIL " .. label)
        end
    end
    return check, function() return failures end, function() return count end
end

-- The oracle's answer for each declaration rule, from its regular expressions: the same inputs as tools/gen.py gives them.
local function test_declarations(check)
    local decl = import("gen.decl", {rootdir = TOOLS, anonymous = true})
    local function same(label, got, want)
        check(got == want, string.format("%s: got %q, the oracle's %q", label, tostring(got), want))
    end
    same("strip_nullability", decl.strip_nullability("- (NSString * _Nullable)name"), "- (NSString * )name")
    same("strip_nullability property", decl.strip_nullability("@property (nonatomic, readonly, nullable) NSString *title"),
         "@property (nonatomic, readonly, ) NSString *title")
    same("strip_nullability macro after parameter", decl.strip_nullability(
         "- (void)setX:(nullable NSString *)x API_AVAILABLE(ios(7.0)) __TVOS_PROHIBITED"), "- (void)setX:( NSString *)x API_AVAILABLE(ios(7.0))")
    same("strip_nullability keeps a lowercase run", decl.strip_nullability("- (BOOL)foo __IOS_AVAILABLE_foo(1)"), "- (BOOL)foo foo(1)")
    same("strip_nullability keeps attributes", decl.strip_nullability("NSInteger FK(void) __attribute__((x)) __CF_AVAILABLE_ME"),
         "NSInteger FK(void) __attribute__((x))")
    same("strip_nullability needs a word start", decl.strip_nullability("- (void)m__TVOS_PROHIBITED"), "- (void)m__TVOS_PROHIBITED")
    same("strip_nullability needs whole words", decl.strip_nullability("xnullable nullable_x _Null_unspecified"), "xnullable nullable_x")
    same("strip_nullability with a nested macro argument", decl.strip_nullability(
         "- (id _Nonnull)a __OSX_X(1) bar __IOS_NOTE(a (b)) c"), "- (id )a bar (a (b)) c")
    local trailing = {
        {"@property (nonatomic) NSInteger scope CS_TVOS_UNAVAILABLE", "@property (nonatomic) NSInteger scope"},
        {"@property NSInteger foo UI_APPEARANCE_SELECTOR", "@property NSInteger foo"},
        {"@property NSInteger foo FILEPROVIDER_API_AVAILABILITY_DESKTOP", "@property NSInteger foo"},
        {"@property NSInteger foo BAR_BAZ(x (y)) QUX_Y", "@property NSInteger foo"},
        {"@property BOOL enabled", "@property BOOL enabled"},
        {"@property NSString *name ABC", "@property NSString *name ABC"},
        {"@property int a_B", "@property int a_B"},
        {"@property int a_B_ C_D", "@property int a_B_"},
        {"@property NSInteger foo A_B( ) C_D(z)  ", "@property NSInteger foo"},
        {"@property NSInteger foo A_B((z)) ", "@property NSInteger foo"},
        {"@property NSInteger foo A_B(", "@property NSInteger foo A_B("},
    }
    for _, case in ipairs(trailing) do
        same("without_trailing_macros " .. case[1], decl.without_trailing_macros(case[1]), case[2])
    end
    same("property_name of a block", decl.property_name("@property (copy) void (^handler)(int)"), "handler")
    same("property_name before a macro", decl.property_name("@property (nonatomic, readwrite) NSInteger scope CS_TVOS_UNAVAILABLE"),
         "scope")
    same("property_name after a macro", decl.property_name("@property NSInteger foo UI_APPEARANCE_SELECTOR"), "foo")
    same("property_name as the last word", decl.property_name("@property (nonatomic) NSString *ab abc"), "abc")
    local selectors = {
        {"- (BOOL)setLevel:(NSInteger)level error:(NSError **)error", "setLevel:error:"},
        {"+ (id)make", "make"},
        {"- (void)reset", "reset"},
        {"-(void)foo:(int)a bar:(int)b", "foo:bar:"},
        {"- (void)1x", "x"},
        {"- (void (^)(int))block:(int)a", "block:"},
        {"- (void)a(b(c))d:(x)", "d:"},
        {"- (NSString *)nameWithNullable:(nullable NSString *)s", "nameWithNullable:"},
        {"- (void)9abc:(int)q", "abc:"},
        {"- (int)x3 y_z:(int)q", "y_z:"},
    }
    for _, case in ipairs(selectors) do
        same("selector_of " .. case[1], decl.selector_of(case[1]), case[2])
    end
    same("getter_of", decl.getter_of("@property (nonatomic, readwrite, getter=isEnabled) BOOL enabled", "enabled"), "isEnabled")
    same("getter_of without one", decl.getter_of("@property (nonatomic) BOOL on", "on"), "on")
    local types = {
        {"@property (nonatomic, readwrite) NSInteger scope", "scope", "NSInteger"},
        {"@property (nonatomic, readwrite, getter=isEnabled) BOOL enabled", "enabled", "BOOL"},
        {"@property (nonatomic, readonly, copy) NSString *name", "name", "NSString *"},
        {"@property (nonatomic) NSString *ab abc", "ab", "NSString *ab"},
        {"@property (nonatomic) NSString *ab abc", "abc", "NSString *ab"},
        {"@property (copy) void (^handler)(int)", "handler", "void"},
        {"@property NSString *(^h)(int)", "h", "NSString *"},
    }
    for _, case in ipairs(types) do
        same("property_type_text " .. case[1], decl.property_type_text(decl.strip_nullability(case[1]), case[2]), case[3])
    end
    local index = {FKFlags = "NS_OPTIONS(NSUInteger, FKFlags)", FKBox = "struct FKBoxS", FKAlias = "FKOther", FKOther = "long",
                   A = "B", B = "C", C = "D", D = "E", E = "F", F = "G", G = "long", FKEnumT = "NS_ENUM(NSInteger, FKEnumT)",
                   FKCount = "unsigned int", FKTypedefObj = "NSString *"}
    local kinds = {
        {"void", "void"}, {"NSInteger", "scalar"}, {"NSString *", "object"}, {"id", "object"}, {"instancetype", "object"},
        {"CGRect", "struct"}, {"FKFlags", "scalar"}, {"FKBox", "struct"}, {"FKAlias", "scalar"}, {"A", "struct"},
        {"NSUInteger", "scalar"}, {"NSSomeOptions", "scalar"}, {"FKEnumT", "scalar"}, {"FKCount", "scalar"},
        {"FKTypedefObj", "object"}, {"const NSInteger", "scalar"}, {"", "struct"}, {"NSArray<NSString *> *", "object"},
        {"BOOL", "scalar"}, {"char *", "object"}, {"enum Thing", "scalar"}, {"NS_OPTIONS(NSInteger, Q)", "scalar"},
    }
    for _, case in ipairs(kinds) do
        same("resolve_kind " .. case[1], decl.resolve_kind(case[1], index), case[2])
    end
end

-- A class with every member stubbed is generated unless its superclass is one of the framework's candidates that is not generated (the
-- oracle's rule: a superclass the framework does not list is taken to be in the release). The class decisions read the superclass
-- the header parse names (the injected supers), not a header.
local function test_superclass(check)
    local classes = import("gen.classes", {rootdir = TOOLS, anonymous = true})
    local surface = import("gen.surface", {rootdir = TOOLS, anonymous = true})
    local function decide(super)
        -- C1 has a stubbed member; Base, a candidate of the framework, has a member no stub answers, so Base is not generated
        local rows = {[surface.key("method", "-[C1 m]")] = {kind = "method", api = "-[C1 m]", lang = "objc"},
                      [surface.key("method", "-[Base m]")] = {kind = "method", api = "-[Base m]", lang = "objc"}}
        local led6 = {[surface.key("class", "C1")] = "missing", [surface.key("method", "-[C1 m]")] = "missing",
                      [surface.key("class", "Base")] = "missing", [surface.key("method", "-[Base m]")] = "missing"}
        local spec = {{kind = "method", api = "-[C1 m]", cls = "C1"}, {kind = "method", api = "-[Base m]", cls = "Base"}}
        return classes.decisions({tree = "/nonexistent-tree", fw = FRAMEWORK, spec = spec, stub_keys = {["-[C1 m]"] = true},
                                  overridden = {}, surface = rows, led6 = led6, skip_reasons = {}, supers = {C1 = super}})
    end
    local under_base = decide("Base").C1
    check(under_base.generated == false and under_base.reason == "superclass Base is neither in the release nor generated",
          "a class whose superclass is a candidate that is not generated is not generated: " .. under_base.reason)
    check(decide("NSObject").C1.generated == true, "a class under a superclass the framework does not list is generated")
end

-- The stub text is the oracle's, byte for byte.
local function test_stub_text(check)
    local stubs = import("gen.stubs", {rootdir = TOOLS, anonymous = true})
    for _, case in ipairs(STUB_TEXT) do
        local got = stubs.stub_text(FRAMEWORK, case[1], case[2], case[3], case[4], case[5], case[6])
        check(got == case[7], "stub text of " .. case[1] .. " is the oracle's: " .. got)
    end
end

-- Writes the fixture: the SDK header, the spec and the functions snapshot, the ledger and the surface table of the corpus, and the
-- injected facts. Returns the tree, the SDK and the corpus.
local function write_fixture(root)
    local emit = import("gen.emit", {rootdir = TOOLS, anonymous = true})
    local layout = import("gen.layout", {rootdir = TOOLS, anonymous = true})
    local tsv = import("gen.tsv", {rootdir = TOOLS, anonymous = true})
    local headers = import("gen.headers", {rootdir = TOOLS, anonymous = true})
    local sdk = path.join(root, "sdk")
    emit.file(path.join(sdk, "System", "Library", "Frameworks", FRAMEWORK .. ".framework", "Headers", FRAMEWORK .. ".h"), HEADER)
    local tree = path.join(root, "tree")
    local rows = {}
    for _, m in ipairs(MEMBERS) do
        local cells = {}
        for _, column in ipairs(layout.constants().SPEC_COLUMNS) do
            cells[column] = "-"
        end
        cells.kind, cells.api, cells.cls, cells.decl = m[2], m[3], m[1], m[4]
        cells.key = (string.gsub(m[3], "[^%w]+", "_"))
        cells.hash = string.rep("0", 16)
        local row = {}
        for i, column in ipairs(layout.constants().SPEC_COLUMNS) do
            row[i] = cells[column]
        end
        table.insert(rows, row)
    end
    emit.file(layout.spec_path(tree, FRAMEWORK), tsv.table_text(layout.constants().SPEC_COLUMNS, rows))
    emit.file(path.join(layout.snap_dir(tree, FRAMEWORK), "functions.tsv"), tsv.table_text(FUNCTION_COLUMNS, {
        {"FKCountThings", "-", "generable", "", "NSInteger", "NSInteger count; NSError **error",
         "NSInteger FKCountThings(NSInteger count, NSError **error)"},
    }))
    local corpus = path.join(root, "corpus")
    local ledger, surface = {}, {}
    for _, row in ipairs(LEDGER) do
        table.insert(ledger, {row[1], "objc", row[2], "7.0", "7.0", "missing", "-", "fixture"})
        table.insert(surface, {FRAMEWORK, row[1], "objc", row[2], "7.0", "-", "-", "-"})
    end
    emit.file(path.join(corpus, "ledger-w45", FRAMEWORK .. ".tsv"), tsv.table_text(LEDGER_COLUMNS, ledger))
    emit.file(path.join(corpus, "sdk-26.2-surface.tsv"), tsv.table_text(SURFACE_COLUMNS, surface))
    headers.use(function(fw, sdk_dir)
        local members = {}
        for _, m in ipairs(MEMBERS) do
            table.insert(members, {cls = m[1], kind = m[2], api = m[3], decl = m[4]})
        end
        return {members = members, declared = {FKThing = true, FKWidget = true, NSObject = true},
                typedefs = {NSInteger = "long", NSUInteger = "unsigned long", BOOL = "signed char"},
                superclasses = {FKThing = "NSObject", FKWidget = "NSObject"}}
    end)
    return tree, sdk, corpus
end

-- Compiles the stubs with the program, runs it, and returns the compile status, the run status and the program's lines (stdout and
-- stderr together).
local function build_and_run(root, tree, sdk)
    local emit = import("gen.emit", {rootdir = TOOLS, anonymous = true})
    local stream = import("gen.stream", {rootdir = TOOLS, anonymous = true})
    local trace_files = import("gen.trace_files", {rootdir = TOOLS, anonymous = true})
    local program = path.join(root, "main.m")
    emit.file(program, PROGRAM)
    local binary = path.join(root, "run")
    local frameworks = path.join(sdk, "System", "Library", "Frameworks")
    local compiled = stream.lines("clang", {"-fobjc-arc", "-DCHARON_TRACE_DEFAULTS", "-F", frameworks, "-I",
                                             path.join(frameworks, FRAMEWORK .. ".framework", "Headers"), "-framework", "Foundation",
                                             "-w", program, trace_files.defaults_file(tree, FRAMEWORK), "-o", binary},
                                  function() end)
    local output = {}
    if compiled ~= 0 then
        return compiled, nil, output
    end
    local ran = stream.lines("sh", {"-c", "'" .. binary .. "' 2>&1"}, function(line)
        table.insert(output, line)
    end)
    return compiled, ran, output
end

local function test_trace_run(check, root)
    local trace = import("gen.cmd_trace", {rootdir = TOOLS, anonymous = true})
    local tsv = import("gen.tsv", {rootdir = TOOLS, anonymous = true})
    local files = import("gen.files", {rootdir = TOOLS, anonymous = true})
    local trace_files = import("gen.trace_files", {rootdir = TOOLS, anonymous = true})
    local tree, sdk, corpus = write_fixture(root)
    local status = trace.run({tree = tree, framework = FRAMEWORK, sdk = sdk, coordination = corpus})
    check(status == 0, "the trace layer writes the fixture")
    local compiled, ran, output = build_and_run(root, tree, sdk)
    check(compiled == 0, "the stubs compile with CHARON_TRACE_DEFAULTS")
    if compiled ~= 0 then
        return
    end
    local logged, seen = {}, {}
    for _, line in ipairs(output) do
        if string.sub(line, 1, #"unimplemented:") == "unimplemented:" then
            table.insert(logged, line)
            seen[line] = (seen[line] or 0) + 1
        else
            print(line)
        end
    end
    local expected = {}
    for _, line in ipairs(EXPECTED_LOG) do
        expected[line] = true
        check(seen[line] == 1, string.format("log line logged %d times, expected once: %s", seen[line] or 0, line))
    end
    for _, line in ipairs(logged) do
        check(expected[line] == true, "unexpected log line: " .. line)
    end
    local decided = {}
    for _, row in ipairs(tsv.records(files.read_text(trace_files.classes_file(tree, FRAMEWORK)))) do
        decided[row.class] = row.generated
    end
    check(decided.FKWidget == "yes", "FKWidget is a generated class object: " .. tostring(decided.FKWidget))
    check(ran == 0, "the program reported no failures (exit " .. tostring(ran) .. ")")
end

function main()
    local check, failures, count = checks()
    test_declarations(check)
    test_superclass(check)
    test_stub_text(check)
    local root = path.join(os.tmpdir(), "charon-trace-test-" .. tostring(os.time()) .. "-" .. tostring(math.random(1000000)))
    os.mkdir(root)
    local err = nil
    try {
        function() test_trace_run(check, root) end,
        catch {
            function(e) err = e end
        }
    }
    os.rm(root)
    if err ~= nil then
        error(err)
    end
    local verdict = failures() == 0 and "OK" or ("FAIL " .. failures())
    print(string.format("trace run test: %s (%d checks)", verdict, count()))
    if failures() > 0 then
        os.exit(1)
    end
end
