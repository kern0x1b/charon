-- The round trip of the headers renderer (tools/gen/render_headers.lua, cmd_headers.lua) on a small SDK of our own: its headers are
-- written here (no SDK text), decls reads them to give the IR, the headers command renders the IR into a tree, and decls reads the
-- tree (IR_FRAMEWORKS) and must give back the IR's rows by key and declhash. A mutant, the same IR with one nullability changed,
-- must come back with exactly that difference, named by its cause.
--
-- Needs the extractor built (xmake build -P tools/found). Run, from any folder: xmake l tests/gen/render_headers_test.lua
local REPO = path.directory(path.directory(path.absolute(os.scriptdir())))
local TOOLS = path.join(REPO, "tools")
local FOUND = path.join(TOOLS, "found")
local SCRATCH = path.join(REPO, "build", "gen", "headers-test")
local FRAMEWORK = "HeadersFixture"
local host = import("gen.host", {rootdir = TOOLS, anonymous = true})
local render = import("gen.render_headers", {rootdir = TOOLS, anonymous = true})
local cmd = import("gen.cmd_headers", {rootdir = TOOLS, anonymous = true})
local DECLS = host.target_product(REPO, FOUND, "decls")
local checks = 0

local function expect(condition, message)
    checks = checks + 1
    if not condition then raise("test failed: " .. message) end
end

local function write(filepath, text)
    os.mkdir(path.directory(filepath))
    local handle = assert(io.open(filepath, "wb"))
    handle:write(text)
    handle:close()
end

local function read(filepath)
    local handle = assert(io.open(filepath, "rb"), "cannot open " .. filepath)
    local text = handle:read("a")
    handle:close()
    return text
end

-- The fixture SDK: a framework with a module map (its header list), a root class, a protocol with a required and an optional member,
-- a subclass that conforms, a category, a block typedef, an enum with constants, a function with a nullable result, and a variable.
-- Every header is a system header, as the SDK's are (the typedef USRs of the IR depend on it).
local SYSTEM = "#pragma clang system_header\n"
local FIXTURE = {
    ["Headers/HFTypes.h"] = SYSTEM .. [[
typedef long HFInteger;
enum HFMode : HFInteger {
  HFModeFirst = 1,
  HFModeSecond = 2,
};
typedef enum HFMode HFMode;
typedef void (^HFBlock)(HFInteger value);
extern const HFInteger HFVersionValue;
HFInteger HFCompute(HFInteger a, HFInteger b);
]],
    ["Headers/HFObject.h"] = SYSTEM .. [[
#import "HFTypes.h"

@class HFRoot;

@protocol HFCopying
- (nullable HFRoot *)snapshot;
@optional
- (void)prepare;
@end

__attribute__((objc_root_class))
@interface HFRoot
@property (nonatomic, readonly, copy, nullable) HFRoot *parent;
- (nonnull instancetype)initWithValue:(HFInteger)value __attribute__((availability(macos,introduced=10.15)));
+ (nullable HFRoot *)rootNamed:(nonnull HFRoot *)other;
@end

__attribute__((availability(ios,introduced=17)))
@interface HFObject : HFRoot <HFCopying>
- (void)runWithBlock:(void (^ _Nonnull)(HFInteger value))block;
@end

extern HFRoot * _Nullable HFRootWithTag(HFInteger tag, HFRoot * _Nonnull fallback);
]],
    ["Headers/HFExtras.h"] = SYSTEM .. [[
#import "HFObject.h"

@interface HFRoot (HFExtras)
- (HFInteger)extraValue;
@end
]],
    ["Headers/HeadersFixture.h"] = SYSTEM .. [[
#import "HFTypes.h"
#import "HFObject.h"
#import "HFExtras.h"
]],
    ["Modules/module.modulemap"] = [[
framework module HeadersFixture {
  umbrella header "HeadersFixture.h"
  export *
  header "HFTypes.h"
  header "HFObject.h"
  header "HFExtras.h"
}
]],
}

local SDK = path.join(SCRATCH, "sdk")
local IR_SDK_ENV = {IR_SDK = SDK, IR_CONFIG = path.join(SCRATCH, "config")}
os.tryrm(SCRATCH)
for relative, text in pairs(FIXTURE) do
    write(path.join(SDK, "System", "Library", "Frameworks", FRAMEWORK .. ".framework", relative), text)
end
write(path.join(SDK, "SDKSettings.json"), read(path.join(FOUND, "tests", "fixture", "sdk", "SDKSettings.json")))
write(path.join(SCRATCH, "config", "usr-modules.tsv"), "# no usr/include modules in this fixture\n")
write(path.join(SCRATCH, "config", "fallback.tsv"), "# no framework without a module map in this fixture\n")

-- 1. the IR of the fixture: decls' own rows for the framework (the census row included)
local ir_file = path.join(SCRATCH, "ir.tsv")
local ir_text = os.iorunv(DECLS, {FRAMEWORK}, {envs = IR_SDK_ENV})
write(ir_file, ir_text)
local ir_rows = render.rows_of(ir_text)
local declared = 0
for _, row in ipairs(ir_rows) do
    if row[2] ~= "census" then declared = declared + 1 end
end
expect(declared > 20, "the fixture's IR has its declarations (got " .. declared .. ")")

-- 2. the headers command writes the tree from the IR
local tree = path.join(SCRATCH, "tree")
expect(cmd.run({tree = REPO, ir = ir_file, sdk = SDK, out = tree}) == 0, "the headers command writes the tree")
local base = path.join(tree, "Frameworks", FRAMEWORK .. ".framework")
local module_map = read(path.join(base, "Modules", "module.modulemap"))
expect(module_map:find('umbrella header "HeadersFixture.h"', 1, true) ~= nil, "the generated module map names the umbrella")
expect(module_map:find('header "HFObject.h"', 1, true) ~= nil, "the generated module map lists HFObject.h")
local object = read(path.join(base, "Headers", "HFObject.h"))
expect(object:find("@interface HFObject : HFRoot <HFCopying>", 1, true) ~= nil,
    "the subclass names its superclass and its protocol")
expect(object:find("@optional", 1, true) ~= nil, "an optional member sits in an @optional section")
expect(read(path.join(base, "Headers", "HFTypes.h")):find("(^HFBlock)", 1, true) ~= nil,
    "a block typedef puts its name in the declarator")
expect(read(path.join(base, "Headers", "HFExtras.h")):find("@interface HFRoot (HFExtras)", 1, true) ~= nil,
    "a category is an interface of its class")

-- 3. the round trip: decls reads the tree and gives back the IR's rows by key and declhash
local decl_text = os.iorunv(DECLS, {FRAMEWORK}, {envs = {IR_SDK = SDK, IR_CONFIG = IR_SDK_ENV.IR_CONFIG, IR_FRAMEWORKS = tree}})
local report = render.compare(ir_rows, render.rows_of(decl_text))
expect(report.ir == report.decls and report.equal == report.ir,
    "the tree reads back every row (IR " .. report.ir .. ", decls " .. report.decls .. ", equal " .. report.equal .. ")")
local differences = 0
for _, n in pairs(report.causes) do differences = differences + n end
expect(differences == 0, "no difference between the IR and decls over the tree")

-- 4. the mutant: the same IR with the nullability of HFRootWithTag's result changed (l to n) is rendered, and the round trip names it
local mutant_text = ir_text:gsub("[^\n]*\tfunction\t[^\n]*HFRootWithTag[^\n]*", function (line)
    local changed = line:gsub("\tl|", "\tn|", 1)
    expect(changed ~= line, "the mutant changes a nullability cell")
    return changed
end, 1)
local mutant_file = path.join(SCRATCH, "mutant.tsv")
write(mutant_file, mutant_text)
local mutant_tree = path.join(SCRATCH, "mutant-tree")
expect(cmd.run({tree = REPO, ir = mutant_file, sdk = SDK, out = mutant_tree}) == 0, "the headers command writes the mutant tree")
local mutant_decls = os.iorunv(DECLS, {FRAMEWORK}, {envs = {IR_SDK = SDK, IR_CONFIG = IR_SDK_ENV.IR_CONFIG, IR_FRAMEWORKS = mutant_tree}})
local mutant_report = render.compare(ir_rows, render.rows_of(mutant_decls))
expect(mutant_report.causes["declhash differs, function: nullability"] == 1 and mutant_report.equal == mutant_report.ir - 1,
    "the mutant gives exactly one difference, its nullability (got " .. tostring(mutant_report.causes["declhash differs, function: nullability"]) .. ")")

os.tryrm(SCRATCH)
print("headers_test: " .. checks .. " checks passed")
