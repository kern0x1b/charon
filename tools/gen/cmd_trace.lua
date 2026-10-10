-- `trace`: the trace-only defaults of a framework, written into its build directory (trace/): the stubs of every declared member it
-- does not implement, one class per category (or one class object where the release lacks the class and every member is a stub),
-- the members left out with their reasons (skipped.tsv), one row per stub (stubs.tsv) and the class-object decisions (classes.tsv).
-- --all: every framework that has a snapshot. The stubs are compiled only with CHARON_TRACE_DEFAULTS and are never shipped.
-- The SDK is --sdk (required); the corpus of ledgers and the surface table is --coordination (required).

local layout = import("layout", {anonymous = true})
local snapshot = import("spec", {anonymous = true})
local surface = import("surface", {anonymous = true})
local headers = import("headers", {anonymous = true})
local decl = import("decl", {anonymous = true})
local stubs = import("stubs", {anonymous = true})
local classes = import("classes", {anonymous = true})
local hand = import("hand", {anonymous = true})
local functions = import("functions", {anonymous = true})
local trace_files = import("trace_files", {anonymous = true})
local emit = import("emit", {anonymous = true})
local tsv = import("tsv", {anonymous = true})
local strings = import("strings", {anonymous = true})
local gen = import("cmd_gen", {anonymous = true})

-- The release whose ledger lists the members the 6.1.3 release lacks.
local LEDGER_RELEASE = "ledger-w45"
-- The selectors whose bare form the surface does not list is the inherited NSObject behaviour, which a call reaches.
local INHERITED_SELECTORS = strings.set({"init", "new", "copy", "mutableCopy"})
local INHERITED_REASON = "init/new/copy the surface does not list: the inherited NSObject behaviour is what a call reaches"
-- The status of a C function the trace layer stubs.
local GENERABLE = "generable"
local NO_TYPE_TEXT = "no type text"

-- The first lines of a generated file: the mark, what the stubs are, and the import and the guard.
local function preamble(fw)
    return {
        layout.constants().MARK,
        "// Trace-only defaults: built only when CHARON_TRACE_DEFAULTS is set; never shipped. One class per category,",
        "// and a class the release lacks, when every member is a stub, is one @implementation (presence = full surface).",
        "// A stub logs once `unimplemented: " .. fw .. " <selector>`, returns the zero of its type, and sets an NSError an NSError ** names.",
        "// Block parameters are not invoked. Members with an override or a hand implementation are not stubbed.",
        "#ifdef CHARON_TRACE_DEFAULTS",
        "#import <" .. fw .. "/" .. fw .. ".h>",
        "#include <stdio.h>",
        "",
    }
end

-- The stub rows, each {api, kind}, unique and sorted by api and then kind (sorted(set(stub_rows)) of tools/gen.py).
local function sorted_stub_rows(rows)
    local seen, out = {}, {}
    for _, row in ipairs(rows) do
        local key = row[1] .. "\t" .. row[2]
        if not seen[key] then
            seen[key] = true
            table.insert(out, row)
        end
    end
    table.sort(out, function(a, b)
        if a[1] ~= b[1] then
            return a[1] < b[1]
        end
        return a[2] < b[2]
    end)
    return out
end

-- The members the spec names for one class, after the inherited selectors the surface does not list are left out. Returns the
-- classes in the order the spec names them, each with its members kept, and appends the members left out to skipped.
local function without_inherited(found, surface_methods, skipped)
    local order = {}
    for _, cls in ipairs(found.order) do
        local kept = {}
        for _, m in ipairs(found.members[cls]) do
            if m.kind == "method" and INHERITED_SELECTORS[m.selector] and not surface_methods[m.api] then
                table.insert(skipped, {api = m.api, reason = INHERITED_REASON})
            else
                table.insert(kept, m)
            end
        end
        if #kept > 0 then
            found.members[cls] = kept
            table.insert(order, cls)
        else
            found.members[cls] = nil
        end
    end
    found.order = order
end

-- The stub keys of the members: a method by its api, a property by the property it belongs to.
local function stub_keys_of(found)
    local keys = {}
    for _, cls in ipairs(found.order) do
        for _, m in ipairs(found.members[cls]) do
            if m.kind == "method" then
                keys[m.api] = true
            else
                keys["-[" .. cls .. " " .. decl.property_name(m.decl) .. "]"] = true
            end
        end
    end
    return keys
end

-- The lines of one class: its declarations in a category when the release has the class, or its @implementation when generated,
-- then its stubs. Returns the number of stubs written; the rows of the stubs and the members left out are appended.
local function class_lines(fw, cls, members, generated, lines, stub_rows, skipped)
    if generated then
        table.insert(lines, "@implementation " .. cls)
    else
        table.insert(lines, "@interface " .. cls .. " (CharonTrace)")
        for _, m in ipairs(members) do
            if m.kind == "property-get" then
                table.insert(lines, "- (" .. m.type_text .. ")" .. m.selector .. ";")
            elseif m.kind == "property-set" then
                table.insert(lines, "- (void)" .. string.sub(m.selector, 1, #m.selector - 1) .. ":(" .. m.type_text .. ")value;")
            else
                table.insert(lines, strings.rstrip(m.decl, ";") .. ";")
            end
        end
        table.insert(lines, "@end")
        table.insert(lines, "@implementation " .. cls .. " (CharonTrace)")
    end
    local written = 0
    for _, m in ipairs(members) do
        if m.zero == "struct" and strings.strip(m.type_text) == "" then
            table.insert(skipped, {api = m.api, reason = NO_TYPE_TEXT})
        else
            table.insert(lines, stubs.stub_text(fw, m.api, m.kind, m.selector, m.type_text, m.zero, m.decl))
            written = written + 1
            local row = m.api
            if m.kind == "property-get" or m.kind == "property-set" then
                row = "-[" .. cls .. " " .. decl.property_name(m.decl) .. "]"
            end
            table.insert(stub_rows, {row, m.kind})
        end
    end
    table.insert(lines, "@end")
    return written
end

-- The C functions of the snapshot the trace layer stubs, sorted by api.
local function generable_functions(tree, fw)
    local rows = {}
    for _, row in pairs(functions.load(tree, fw)) do
        if row.status == GENERABLE then
            table.insert(rows, row)
        end
    end
    table.sort(rows, function(a, b)
        return a.api < b.api
    end)
    return rows
end

-- Writes the trace layer of one framework.
local function trace_one(args, fw)
    local tree, sdk, corpus = args.tree, args.sdk, args.coordination
    local spec = snapshot.load(tree, fw)
    local facts = headers.facts(tree, fw, sdk)
    local overridden = {}
    for canonical in pairs(surface.registry_entries(tree, fw)) do
        overridden[canonical] = true
    end
    -- the 6.1.3 ledger: the members the release lacks are the ones to stub; with no ledger every declared member is considered
    local led6 = surface.ledger_status(corpus, fw, LEDGER_RELEASE)
    local release_missing = nil
    if os.isfile(path.join(corpus, LEDGER_RELEASE, fw .. ".tsv")) then
        release_missing = led6
    end
    local found, skipped = stubs.members(spec, {
        index = facts.typedefs,
        declared = facts.declared,
        overridden = overridden,
        hand = hand.implementations(tree),
        release_missing = release_missing,
    })
    local stub_keys = stub_keys_of(found)
    -- the reasons the class decisions read: taken before the inherited-selector rule adds its own, as the oracle does
    local skip_reasons = {}
    for _, s in ipairs(skipped) do
        skip_reasons[s.api] = s.reason
    end
    local rows = surface.surface_rows(corpus, fw)
    local surface_methods = {}
    for _, row in pairs(rows) do
        if row.kind == "method" then
            surface_methods[surface.canonical_member(row.api, "method")] = true
        end
    end
    without_inherited(found, surface_methods, skipped)
    local decisions = {}
    if release_missing ~= nil then
        decisions = classes.decisions({
            tree = tree, fw = fw, spec = spec, stub_keys = stub_keys, overridden = overridden,
            surface = rows, led6 = led6, skip_reasons = skip_reasons, supers = facts.superclasses,
        })
    end
    local lines = preamble(fw)
    local stub_rows = {}
    local stubbed = 0
    local class_names = table.move(found.order, 1, #found.order, 1, {})
    table.sort(class_names)
    for _, cls in ipairs(class_names) do
        local generated = decisions[cls] ~= nil and decisions[cls].generated
        stubbed = stubbed + class_lines(fw, cls, found.members[cls], generated, lines, stub_rows, skipped)
    end
    for _, row in ipairs(generable_functions(tree, fw)) do
        local zero = decl.resolve_kind(row.returns, facts.typedefs)
        table.insert(lines, stubs.stub_text(fw, row.api, "function", row.api, row.returns, zero, row.decl))
        stubbed = stubbed + 1
        table.insert(stub_rows, {row.api .. "()", "function"})
    end
    table.insert(lines, "#endif")
    emit.file(trace_files.defaults_file(tree, fw), table.concat(lines, "\n") .. "\n")
    local skipped_rows = {}
    for _, s in ipairs(skipped) do
        table.insert(skipped_rows, {s.api, s.reason})
    end
    emit.file(trace_files.skipped_file(tree, fw), tsv.table_text({"api", "reason"}, skipped_rows))
    emit.file(trace_files.stubs_file(tree, fw), tsv.table_text({"api", "kind"}, sorted_stub_rows(stub_rows)))
    local class_rows = {}
    for cls, d in pairs(decisions) do
        table.insert(class_rows, {cls, d.generated and "yes" or "no", d.reason})
    end
    table.sort(class_rows, function(a, b)
        return a[1] < b[1]
    end)
    emit.file(trace_files.classes_file(tree, fw), tsv.table_text({"class", "generated", "reason"}, class_rows))
    print(string.format("trace %s: %d stubs in %d classes, %d members left out (skipped.tsv)", fw, stubbed, #found.order, #skipped))
end

-- The members the stub rule leaves out of one framework, with the reason each is left out, in the order they were decided: the scope's
-- reasons (stub_members of tools/gen.py, which runs before the inherited-selector rule trace_one adds). tree: the repository tree;
-- spec: the framework's spec rows; facts: the header facts of the framework (headers.facts); overridden: the set of the canonical keys
-- a registry row covers; release_missing: the 6.1.3 ledger's statuses keyed by surface.key, or nil when the rule considers every
-- declared member.
function members_left_out(tree, spec, facts, overridden, release_missing)
    local _, skipped = stubs.members(spec, {
        index = facts.typedefs,
        declared = facts.declared,
        overridden = overridden,
        hand = hand.implementations(tree),
        release_missing = release_missing,
    })
    return skipped
end

-- Returns the exit status.
function run(args)
    assert(args.sdk, "trace needs --sdk: the iOS SDK directory")
    assert(args.coordination, "trace needs --coordination: the corpus folder")
    local targets = args.all and gen.frameworks(args.tree) or {args.framework}
    for _, fw in ipairs(targets) do
        trace_one(args, fw)
    end
    return 0
end
