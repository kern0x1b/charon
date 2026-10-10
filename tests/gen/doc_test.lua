-- Behaviour of `doc`: the page writer on a fixture framework. The header facts and the ObjC rows are injected (no SDK, no header
-- parse, no objc table), and the tree and the corpus are small folders written here. Run:
--   xmake l tests/gen/doc_test.lua
-- The folders live under the system temp directory and are removed when the test ends.

local TOOLS = path.join(os.scriptdir(), "..", "..", "tools")
local FIXTURE = "FixtureKit"
local files = import("gen.files", {rootdir = TOOLS, anonymous = true})
local tsv = import("gen.tsv", {rootdir = TOOLS, anonymous = true})
local swift = import("gen.swift", {rootdir = TOOLS, anonymous = true})
local emit = import("gen.emit", {rootdir = TOOLS, anonymous = true})
local headers = import("gen.headers", {rootdir = TOOLS, anonymous = true})
local doc_text = import("gen.doc_text", {rootdir = TOOLS, anonymous = true})

local function checks()
    local failures = 0
    local function check(ok, label)
        if not ok then
            failures = failures + 1
            print("FAIL " .. label)
        end
    end
    return check, function() return failures end
end

-- The text of a page, or nil when the page is absent.
local function page_text(filepath)
    return files.read_text(filepath)
end

-- True when text holds the plain substring.
local function has(text, plain)
    return text ~= nil and string.find(text, plain, 1, true) ~= nil
end

-- A fixture tree and corpus: the spec, the protocols, the registry, the pins, the trace's skipped list, the bucket, and the corpus
-- tables the pages read.
local function write_fixture(tree, corpus)
    local package = path.join(tree, "packages", "a", "apple-backports")
    local spec_header = {"kind", "api", "cls", "key", "introduced", "decl", "availability", "hash", "value_status", "value",
                         "host_value", "value_source", "owned", "tbd", "shape", "measured"}
    local function spec_row(kind, api, cls, decl, availability, value_status, value)
        return {kind, api, cls, "-", "-", decl, availability, "-", value_status or "-", value or "-", "-", "-", "-", "-", "-", "-"}
    end
    emit.file(path.join(package, "spec", FIXTURE, "spec.sdk-26.2-headers.tsv"), tsv.table_text(spec_header, {
        spec_row("method", "-[FKThing reset]", "FKThing", "- (void)reset", "-"),
        spec_row("method", "-[FKThing setName:age:]", "FKThing", "- (void)setName:(NSString *)n age:(int)a | sized",
                 "API_AVAILABLE(ios(12.0))"),
        spec_row("property", "-[FKThing title]", "FKThing", "@property (nonatomic) NSString *title", "-"),
        spec_row("method", "+[FKThing make]", "FKThing", "+ (instancetype)make", "-"),
        spec_row("constant", "FKConstant", "-", "extern NSString *const FKConstant", "-", "found", "fk"),
    }))
    emit.file(path.join(package, "spec", FIXTURE, "protocols.tsv"), tsv.table_text(
        {"protocol", "introduced", "status", "reasons", "bases", "section", "kind", "instance", "selector", "decl", "in16"}, {
        {"FKDelegate", "12.0", "transcribed", "", "NSObject", "-", "-", "-", "-", "-", "-"},
        {"FKDelegate", "12.0", "transcribed", "", "NSObject", "required", "method", "yes", "didFinish", "- (void)didFinish;", "yes"},
        {"FKDelegate", "12.0", "transcribed", "", "NSObject", "required", "method", "no", "make", "+ (instancetype)make;", "yes"},
        {"FKDelegate", "12.0", "transcribed", "", "NSObject", "optional", "property", "yes", "name", "@property NSString *name;", "no"},
    }))
    emit.file(path.join(package, "registry", FIXTURE, "ios.json"),
              '{"entries": [{"api": "-[FKThing reset]", "kind": "method", "status": "implemented", "owner": "hand"}]}\n')
    emit.file(path.join(package, "overrides", "hashes", FIXTURE .. ".tsv"),
              tsv.table_text({"api", "key", "pinned", "pinned-by", "registry"}, {
                  {"-[FKThing reset]", "FKThing_reset", "-", "fixture pin", "packages/a/apple-backports/registry/FixtureKit/ios.json"},
              }))
    emit.file(path.join(package, ".gen", FIXTURE, "trace", "skipped.tsv"),
              tsv.table_text({"api", "reason"}, {{"+[FKThing make]", "class method not stubbed in the fixture"}}))
    emit.file(path.join(package, "spec", "swift", "bucket.tsv"), swift.bucket_text({
        {FIXTURE, "method", "-[FKThing swiftOnly]", "13.0", "-", "fixture", "no", "-", "-", "-", "5", "9", "lead",
         "swift: needs the Swift interface source"},
    }))
    emit.file(path.join(corpus, "sdk-26.2-surface.tsv"), tsv.table_text(
        {"framework", "kind", "api", "lang", "introduced", "demand-rank", "demand-severity", "demand-apps", "impl-lead"}, {
        {FIXTURE, "method", "-[FKThing setName:age:]", "objc", "12.0", "3", "high", "40", "lead"},
        {FIXTURE, "method", "-[FKThing reset]", "objc", "12.0", "-", "-", "-", "-"},
        {FIXTURE, "protocol", "FKDelegate", "objc", "12.0", "-", "-", "-", "-"},
    }))
    emit.file(path.join(corpus, "ledger-w45", FIXTURE .. ".tsv"), tsv.table_text({"kind", "api", "status"}, {
        {"method", "-[FKThing setName:age:]", "missing"},
        {"method", "-[FKDelegate didFinish]", "header-ok"},
    }))
    emit.file(path.join(corpus, "ledger-w45-4.3", FIXTURE .. ".tsv"), tsv.table_text({"kind", "api", "status"}, {
        {"method", "-[FKThing reset]", "absent"},
    }))
    emit.file(path.join(corpus, "cache-26.2", "oracle-defaults.tsv"), tsv.table_text(
        {"kind", "framework", "class", "item", "value_kind", "value", "build", "host"}, {
        {"default", FIXTURE, "FKThing", "count", "value", "0 | zero", "host", "mac"},
        {"default", FIXTURE, "FKThing", "short"},
    }))
end

-- The ObjC rows the fixture's pages read: a class row twice (the last one of the owner wins), a method row twice (the first wins),
-- a property row, and a class row of an owner the spec does not name.
local function fixture_rows(fw, fn)
    local function row(entity, owner, section, name, decl, types, address, superclass, protocols)
        return {entity = entity, owner = owner, section = section, name = name, decl = decl, types = types, address = address,
                superclass = superclass, protocols = protocols or "", category = ""}
    end
    if fw ~= FIXTURE then
        return
    end
    fn(fw, row("class", "FKThing", "class", "FKThing", "@interface FKThing : NSObject", "", "0x1", "NSObject"))
    -- the same key again: the first row of a key wins
    fn(fw, row("class", "FKThing", "class", "FKThing", "@interface FKThing : NSObject <FKDelegate>", "", "0x2", "NSObject",
               "FKDelegate"))
    -- a second key of the owner: the last class row of the owner wins (its protocols show)
    fn(fw, row("class", "FKThing", "instance", "FKThing", "@interface FKThing (Extra)", "", "0x7", "NSObject", "FKDelegate"))
    fn(fw, row("method", "FKThing", "instance", "reset", "- (void)reset", "v16@0:8", "0x3"))
    fn(fw, row("method", "FKThing", "instance", "reset", "- (void)reset", "v16@0:8", "0x4"))
    fn(fw, row("property", "FKThing", "instance", "title", "@property NSString *title", "@16@0:8", "0x5"))
    fn(fw, row("class", "Unrelated", "class", "Unrelated", "@interface Unrelated", "", "0x6", "NSObject"))
end

-- The header facts the fixture injects: a superclass. The pages take their comments and declarations from the doc rows below (the
-- extractor's doc mode), and the spec's decl column is never shown.
local function fixture_headers(fw, sdk)
    return {members = {}, declared = {}, typedefs = {}, superclasses = {FKThing = "NSObject", FKDelegate = "NSObject"}}
end

-- The extractor's escaping of a cell (decls.cc): a backslash, a tab, a line feed and a carriage return.
local function escape(text)
    return (string.gsub(text, "[\\\t\n\r]", {["\\"] = "\\\\", ["\t"] = "\\t", ["\n"] = "\\n", ["\r"] = "\\r"}))
end

-- A doc row of the fixture as the extractor writes it: ten escaped cells, tab separated.
local function doc_row(usr, kind, name, side, params, brief, comment, decl)
    local cells = {FIXTURE, kind, usr, "-", name, side, params, brief, comment, decl}
    for i, cell in ipairs(cells) do
        cells[i] = escape(cell)
    end
    return table.concat(cells, "\t")
end

-- The raw comment of reset: a tab, a line feed, a backslash and a non-ASCII apostrophe (UTF-8).
local RESET_COMMENT = "/// Resets the thing.\n/// Keeps a\\b and a\tTAB\n/// Don\226\128\153t"

-- The doc rows the fixture's extractor gives (the rows of FixtureKit; nil for any other framework, which it does not list). The
-- literal row has a tab, a line feed and a backslash in its comment, written as the extractor writes them.
local function fixture_doc_rows(fw, sdk)
    if fw ~= FIXTURE then
        return nil
    end
    return {
        doc_row("c:objc(cs)FKThing(im)reset", "method", "reset", "-", "", "Resets the thing.", RESET_COMMENT, "- (void)reset"),
        -- the same USR again: the first row of a USR is the one kept
        doc_row("c:objc(cs)FKThing(im)reset", "method", "reset", "-", "", "", "", "- (void)reset NS_SWIFT_UNAVAILABLE(\"x\")"),
        -- no raw comment: the brief is the comment
        doc_row("c:objc(cs)FKThing(im)setName:age:", "method", "setName:age:", "-", "n | a", "Sets the name.", "",
                "- (void)setName:(NSString *)n age:(int)a | pipe"),
        -- a declaration that quotes backticks, as an API_DEPRECATED message does
        doc_row("c:objc(cs)FKThing(py)title", "property", "title", "-", "", "", "",
                "@property (nonatomic, copy) NSString *title API_DEPRECATED(\"Use `other`\", ios(1.0, 2.0))"),
        -- a row with no USR is no member
        doc_row("-", "super", "NSObject", "-", "", "", "", "-"),
        -- a class property: its side is "+" as the shard reader gives it, whatever the extractor's side column says
        doc_row("c:objc(cs)FKThing(cpy)shared", "property", "shared", "-", "", "", "", "@property (class, readonly) FKThing *shared"),
        doc_row("c:objc(pl)FKDelegate(im)didFinish", "method", "didFinish", "-", "", "", "", "- (void)didFinish;"),
        doc_row("c:objc(pl)FKDelegate(cm)make", "method", "make", "+", "", "", "/// Makes one.", "+ (instancetype)make;"),
        -- the literal row: its comment holds a tab, a line feed and a backslash
        "FixtureKit\tmethod\tc:objc(cs)FKThing(im)tabbed\t-\ttabbed\t-\t\t\t/// one\\ttwo\\nthree\\\\four\t- (void)tabbed",
    }
end

-- The text of a page, or nil when the page is absent.
local function page_of(dir, name)
    return page_text(path.join(dir, name))
end

local function test_pages(check)
    local root = path.join(os.tmpdir(), "charon-doc-test-" .. tostring(os.time()))
    local tree, corpus = path.join(root, "tree"), path.join(root, "corpus")
    local out, out_marked = path.join(root, "out"), path.join(root, "out-marked")
    local cmd_doc = import("gen.cmd_doc", {rootdir = TOOLS, anonymous = true})
    write_fixture(tree, corpus)
    headers.use(fixture_headers)
    cmd_doc.use_objc(function(_, frameworks, fn) fixture_rows(FIXTURE, fn) end)

    -- the decoding of the escaped cells: the literal row's comment is its tab, line feed and backslash
    local fixture_rows_list = fixture_doc_rows(FIXTURE)
    local literal = fixture_rows_list[#fixture_rows_list]
    local cells = doc_text.decode(literal)
    check(#cells == 10, "a doc row has ten cells")
    check(cells[9] == "/// one\ttwo\nthree\\four", "a comment cell decodes its escaped tab, line feed and backslash")
    check(cells[10] == "- (void)tabbed" and cells[5] == "tabbed", "the other cells decode as written")
    check(#doc_text.decode("a\t\t-") == 3 and doc_text.decode("a\t\t-")[2] == "", "an empty cell is an empty string")
    doc_text.use(fixture_doc_rows)
    local doc = doc_text.rows(tree, FIXTURE, "/nonexistent")
    local rows_usr, rows_api = doc.usr, doc.api
    check(rows_usr ~= nil and rows_usr["c:objc(cs)FKThing(im)tabbed"].comment == cells[9],
          "the rows give the decoded comment of a USR")
    check(rows_usr["c:objc(cs)FKThing(im)reset"].decl == "- (void)reset", "a USR written twice keeps its first row")
    check(rows_usr["c:objc(cs)FKThing(im)setName:age:"].from_brief == true
          and rows_usr["c:objc(cs)FKThing(im)setName:age:"].comment == "Sets the name.",
          "a row with an empty raw comment takes its brief, and says so")
    check(rows_usr["c:objc(cs)FKThing(im)reset"].from_brief == false, "a row with a raw comment does not take its brief")
    check(rows_api["method -[FKThing reset]"] == rows_usr["c:objc(cs)FKThing(im)reset"], "the rows are keyed by kind and api")
    check(rows_api["method +[FKDelegate make]"] ~= nil and rows_api["property -[FKThing title]"] ~= nil,
          "a class member of a protocol is keyed with its sign")
    check(rows_api["property +[FKThing shared]"] ~= nil and rows_api["property -[FKThing shared]"] == nil,
          "a class property is keyed with the sign of a class member, as the shard reader gives it")
    check(rows_usr["-"] == nil, "a row with no USR is not kept")

    check(cmd_doc.run({tree = tree, all = true, sdk = "/nonexistent", coordination = corpus, out = out}) == 0,
          "doc --all on the fixture succeeds")

    local dir = path.join(out, FIXTURE)
    local index = page_of(dir, "index.md")
    check(has(index, "## Classes (1)"), "the index counts one class")
    check(has(index, "| FKThing | NSObject | 4 | 1 | 2 | [FKThing.md](FKThing.md) |"),
          "the index row counts members, overridden and stubbed (the skipped member is not stubbed)")
    check(has(index, "| FKDelegate | transcribed | 3 | [FKDelegate.md](FKDelegate.md) |"), "the index lists the protocol with its members")
    check(has(index, "Constants: [Constants.md](Constants.md) (1 rows)."), "the index counts the constant rows")

    local class = page_of(dir, "FKThing.md")
    check(has(class, "Superclass: NSObject. Status at 6.1.3 and 4.3 is per member below."), "the class page names its superclass")
    check(has(class, "| method | `- (void)setName:(NSString *)n age:(int)a \\| pipe` | API_AVAILABLE(ios(12.0)) | missing | implemented | rank 3, high, 40 apps | lead | - | stub |"),
          "a member row shows its extractor declaration (its pipes escaped), its ledger status and its demand, and is a stub")
    check(has(class, "| method | `not derived: not in the doc rows` | - | implemented | implemented | - | - | - | not stubbed: class method not stubbed in the fixture |"),
          "a member the extractor does not list is marked, and a member the trace left out reports its reason")
    check(has(class, "| method | `- (void)reset` | - | implemented | absent | rank -, -, - apps | - | implemented: packages/a/apple-backports/registry/FixtureKit/ios.json, pin fixture pin | hand/override |"),
          "an overridden member shows its extractor declaration, its registry row, its pin and the hand override")
    check(has(class, "| property | `` @property (nonatomic, copy) NSString *title API_DEPRECATED(\"Use `other`\", ios(1.0, 2.0)) `` | - |"),
          "a property row shows its extractor declaration, in a code span that can hold a backtick")
    check(has(class, "## Header comments\n\n### `-[FKThing reset]`\n\n```\n/// Resets the thing.\n/// Keeps a\\b and a\tTAB\n/// Don\\u{2019}t\n```\n"),
          "a member with a raw comment shows it in a block, with the non-ASCII character as an escape")
    check(has(class, "### `-[FKThing setName:age:]`\n\n```\nSets the name.\n```\n"),
          "a member with only a brief shows the brief as its comment")
    check(has(class, "- `+[FKThing make]`: not derived: not in the doc rows\n- `-[FKThing title]`: no comment in the doc rows\n"),
          "the members the extractor does not list, and those with no comment, are listed under the blocks")
    check(not has(class, "@property (nonatomic) NSString *title") and not has(class, "(instancetype)make") and not has(class, "sized"),
          "no declaration text of the spec shows on the page")
    check(has(class, "| item | kind | value | build |"), "the host oracle table is there")
    check(has(class, "| count | value | 0 \\| zero | host |"), "an oracle value escapes its pipe")
    check(has(class, "| short | None | None | None |"), "a short oracle row shows None for its missing cells")
    check(has(class, "Superclass in the binary: NSObject. Protocols: FKDelegate."), "the binary's superclass and protocols show")
    check(has(class, "| `-[FKThing reset]` | v16@0:8 | 0x3 |"), "the binary's type encoding of the first row of a key shows")
    check(has(class, "| `-[FKThing title]` | @16@0:8 | 0x5 |"), "a property's binary row is found by its name")
    check(has(class, "| `+[FKThing make]` | not in the table | - |"), "a member the binary does not hold says so")

    local protocol = page_of(dir, "FKDelegate.md")
    check(has(protocol, "Status in the transcriber's facts: transcribed. Introduced 12.0. Bases: NSObject."), "the protocol page gives its record")
    check(has(protocol, "| required | method | `- (void)didFinish;` | yes | header-ok | - | - |"),
          "a protocol member row shows its extractor declaration, its section and its status at 6.1.3")
    check(has(protocol, "| required | method | `+ (instancetype)make;` | yes | implemented | - | - |"),
          "a class member of a protocol takes its doc row by its sign")
    check(has(protocol, "| optional | property | `not derived: not in the doc rows` | no |"),
          "a protocol member the extractor does not list is marked")
    check(has(protocol, "## Header comments\n\n### `+[FKDelegate make]`\n\n```\n/// Makes one.\n```\n\n- `-[FKDelegate name]`: not derived: not in the doc rows\n- `-[FKDelegate didFinish]`: no comment in the doc rows\n"),
          "a protocol's comments: the block of the member with a comment, the bullets of the others")
    check(not has(protocol, "@property NSString *name;"), "no declaration text of the spec shows on the protocol page")

    local constants = page_of(dir, "Constants.md")
    check(has(constants, "| FKConstant | `not derived: decl (ruling D8)` | fk | - | implemented | implemented | generated |"),
          "the constants page is unchanged: a constant row shows its value and its ownership")
    local swift_page = page_of(dir, "Swift.md")
    check(has(swift_page, "| method | `-[FKThing swiftOnly]` | 13.0 | - | no | 5 | lead |"), "the Swift page lists the bucket row")
    check(has(swift_page, "- Whether an armv7 Swift module or runtime loads on iOS 6.1.3: only a device run can show it."),
          "the Swift page ends with the overlay needs")

    -- a second run on the unchanged output writes nothing: the pages are compared before they are written
    local before = emit.count()
    check(cmd_doc.run({tree = tree, all = true, sdk = "/nonexistent", coordination = corpus, out = out}) == 0
          and emit.count() == before, "a second doc run on the same output writes no file")

    -- a framework the extractor gives no rows for keeps the marked text
    doc_text.use(function() return nil end)
    check(cmd_doc.run({tree = tree, all = true, sdk = "/nonexistent", coordination = corpus, out = out_marked}) == 0,
          "doc --all with no doc rows succeeds")
    local marked = page_of(path.join(out_marked, FIXTURE), "FKThing.md")
    check(has(marked, "| method | `not derived: decl (ruling D8)` | API_AVAILABLE(ios(12.0)) | missing |"),
          "without doc rows a member keeps the marked declaration")
    check(has(marked, "## Header comments\n\n- not derived: the extractor does not run for this framework\n"),
          "without doc rows the header comments section is marked, not derived")
    local marked_protocol = page_of(path.join(out_marked, FIXTURE), "FKDelegate.md")
    check(has(marked_protocol, "| required | method | `not derived: decl (ruling D8)` | yes | header-ok | - | - |"),
          "without doc rows a protocol member keeps the marked declaration")
    check(has(marked_protocol, "## Header comments\n\n- not derived: the extractor does not run for this framework\n"),
          "without doc rows the protocol's header comments are marked, not derived")

    -- an extractor that is not built is an error, not marked text: the tree has no tools/found project to build it from
    doc_text.use(nil)
    local raised = false
    try {
        function()
            doc_text.rows(tree, FIXTURE, "/nonexistent")
        end,
        catch {
            function(e)
                raised = string.find(tostring(e), "decls", 1, true) ~= nil
            end
        }
    }
    check(raised, "a doc run with no built extractor raises: the pages do not take marked text for it")
    os.rm(root)
end

function main()
    local check, failures = checks()
    test_pages(check)
    print("doc test: " .. (failures() == 0 and "OK" or ("FAIL " .. failures())))
    if failures() > 0 then
        os.exit(1)
    end
end
