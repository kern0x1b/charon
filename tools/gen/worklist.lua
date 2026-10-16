-- The work list of an sdk run (design-sdk-generator.md step 3d): one row per surface declaration of each framework, with its state. The
-- state is the one cmd_scope gives the row: its row_state (over the context of the framework, built as cmd_scope builds it) and, for an
-- open state, the work queue_item names. The design's state of the row ("in 6.1.3", "overridden", "generated stub", "header only") is
-- read from that state by design_of; "-" where the state names none of the four. Writes --out/<module>.tsv per module (a "/" of a nested
-- framework's name is written "+"), and --out/totals.tsv: per module and in all, the rows, each design state's count, the queued rows
-- and by_hand (the generated stubs and the queued rows: the rows somebody writes or decides by hand). The per-state counts tie to the
-- scope's v-gen-scope.tsv of the same run (--scope): a difference fails the step. Returns the exit status and a line of counts.

local layout = import("layout", {anonymous = true})
local snapshot = import("spec", {anonymous = true})
local surface = import("surface", {anonymous = true})
local functions = import("functions", {anonymous = true})
local protocols = import("protocols", {anonymous = true})
local trace = import("cmd_trace", {anonymous = true})
local scope = import("cmd_scope", {anonymous = true})
local trace_files = import("trace_files", {anonymous = true})
local headers = import("headers", {anonymous = true})
local coverage = import("coverage", {anonymous = true})
local swift_shard = import("swift_shard", {anonymous = true})
local emit = import("emit", {anonymous = true})
local order = import("order", {anonymous = true})
local strings = import("strings", {anonymous = true})
local sdk_info = import("sdk", {anonymous = true})
local project = import("project", {anonymous = true})

-- The ledgers the rows are checked against, as cmd_scope names them.
local LEDGER_6_1_3 = surface.ledger_6_1_3()
local LEDGER_4_3 = surface.ledger_4_3()
-- The kinds a row is counted under (cmd_scope's SCOPE_KINDS): a surface row of another kind has no state.
local SCOPE_KINDS = strings.set({"class", "method", "property", "constant", "function", "enum", "struct", "typealias", "protocol"})
-- The state of a row the framework has no snapshot for (cmd_scope's NO_SNAPSHOT).
local NO_SNAPSHOT = "no snapshot"
-- The design's four states, and the scope states each one reads. A scope state no prefix here names is "-" (the design names it no
-- category). "not checked at 6.1.3" has no scope state: no row takes it.
local DESIGN_IN_RELEASE = "in 6.1.3"
local DESIGN_OVERRIDDEN = "overridden"
local DESIGN_GENERATED = "generated stub"
local DESIGN_HEADER_ONLY = "header only"
local DESIGN_NONE = "-"
local IN_RELEASE_STATE = "implemented at 6.1.3: the release answers"
local OVERRIDDEN_PREFIXES = {"overridden", "registry decision", "hand implementation", "class object: hand code covers it",
                             "protocol object: hand header", "protocol member: declared by a hand header"}
local GENERATED_PREFIXES = {"generable stub", "C function: generable stub", "generable constant", "class object: generated",
                            "protocol object: generated from", "protocol member: in the "}
local HEADER_ONLY_PREFIX = "header-only (lift)"

local function starts_with(text, prefix)
    return string.sub(text, 1, #prefix) == prefix
end

-- The design's state of a scope state, one of the four design states or DESIGN_NONE.
function design_of(state)
    if state == IN_RELEASE_STATE then
        return DESIGN_IN_RELEASE
    end
    for _, prefix in ipairs(OVERRIDDEN_PREFIXES) do
        if starts_with(state, prefix) then
            return DESIGN_OVERRIDDEN
        end
    end
    for _, prefix in ipairs(GENERATED_PREFIXES) do
        if starts_with(state, prefix) then
            return DESIGN_GENERATED
        end
    end
    if starts_with(state, HEADER_ONLY_PREFIX) then
        return DESIGN_HEADER_ONLY
    end
    return DESIGN_NONE
end

-- The context cmd_scope's row_state reads for one framework: the same fields cmd_scope's new_context builds (that function is local to
-- cmd_scope, so it is built here from the same loaders). owner is the framework whose ledgers and registry the rows are checked
-- against; skipped is the extractor's skip list of the framework (coverage.skipped[fw]); rows are the group's rows.
local function context_of(args, fw, owner, rows, states, skipped)
    local tree, corpus = args.tree, args.coordination
    local led6 = surface.ledger_status(corpus, owner, LEDGER_6_1_3)
    local led43 = surface.ledger_status(corpus, owner, LEDGER_4_3)
    local snap = os.isfile(layout.shard_path(tree, fw))
    local registry = trace.overrides_of(tree, owner, headers.shard_facts(tree, fw))
    local stub_keys = trace_files.load_stub_keys(tree, fw)
    if stub_keys ~= nil then
        -- a class property's stub is keyed by its class accessor; the surface names it by its dotted name, so the instance key is added
        for _, api in pairs(trace.class_property_apis(headers.shard_facts(tree, fw))) do
            if stub_keys[api] then
                stub_keys["-" .. string.sub(api, 2)] = true
            end
        end
    end
    local ctx = {
        states = states, led6 = led6, led43 = led43, snap = snap, registry = registry, stub_keys = stub_keys,
        swift = swift_shard.index(tree, fw), spec_by_api = {}, functions = {}, class_decisions = {}, proto = {}, protocols = {},
        stub_reason_of = function() return nil end,
    }
    if snap then
        ctx.proto = protocols.records(tree, fw)
        ctx.functions = functions.load(tree, owner)
        ctx.class_decisions = trace_files.load_class_decisions(tree, fw)
        ctx.spec_by_api = snapshot.index(snapshot.load(tree, fw))
        local parsed = nil
        local reasons = nil
        ctx.stub_reason_of = function(key)
            if reasons == nil then
                if parsed == nil then
                    parsed = headers.shard_facts(tree, fw)
                end
                reasons = scope.reasons_by_key(trace_files.load_skip_reasons(tree, fw), parsed)
            end
            return reasons[key]
        end
        ctx.gap_of = function(api)
            return scope.gap_reason(api, skipped[fw], states)
        end
    end
    for _, row in ipairs(rows) do
        if row.kind == "protocol" and row.lang == "objc" then
            ctx.protocols[row.api] = true
        end
    end
    for name in pairs(ctx.proto) do
        ctx.protocols[name] = true
    end
    return ctx
end

-- Counts one row into a module's counts: its scope state, its design state, and whether it is queued.
local function count_row(counts, state, design, queued)
    counts.rows = counts.rows + 1
    counts.states[state] = (counts.states[state] or 0) + 1
    counts.design[design] = counts.design[design] + 1
    if queued then
        counts.queued = counts.queued + 1
    end
end

local function new_counts()
    return {rows = 0, states = {}, design = {[DESIGN_IN_RELEASE] = 0, [DESIGN_OVERRIDDEN] = 0, [DESIGN_GENERATED] = 0,
                                             [DESIGN_HEADER_ONLY] = 0, [DESIGN_NONE] = 0}, queued = 0}
end

-- The rows of one module as its TSV text, and the module's counts. The states are scope's (row_state, queue_item), never a guess.
local function module_of(args, group, states, skipped, lines)
    local owner = group.owner or group.fw
    local ctx = context_of(args, group.fw, owner, group.rows, states, skipped)
    local counts = new_counts()
    table.insert(lines, "kind\tapi\tlang\tstate\tdesign\twork")
    for _, row in ipairs(group.rows) do
        if SCOPE_KINDS[row.kind] then
            local lang = row.lang or "objc"
            local state = (ctx.snap or lang == "swift") and scope.row_state(row.kind, row.api, lang, ctx) or NO_SNAPSHOT
            local design = design_of(state)
            local work = scope.queue_item(state, states)
            count_row(counts, state, design, work ~= nil)
            table.insert(lines, table.concat({row.kind, row.api, lang, state, design, work or "-"}, "\t"))
        end
    end
    return counts
end

-- The scope's per-framework counts, read from its v-gen-scope.tsv: framework -> {rows, states = state -> n}.
function scope_counts_of(filepath)
    local out = {}
    local header = true
    for line in io.lines(filepath) do
        if header then
            header = false
        elseif line ~= "" then
            local cells = {}
            for cell in string.gmatch(line .. "\t", "([^\t]*)\t") do
                table.insert(cells, cell)
            end
            local fw = cells[1]
            out[fw] = out[fw] or {rows = 0, states = {}}
            out[fw].rows = out[fw].rows + tonumber(cells[3])
            for pair in string.gmatch(cells[8] or "", "[^;]+") do
                local text = string.match(pair, "^%s*(.-)%s*$")
                local state, n = string.match(text, "^(.*)=(%d+)$")
                if state ~= nil then
                    out[fw].states[state] = (out[fw].states[state] or 0) + tonumber(n)
                end
            end
        end
    end
    return out
end

-- The first difference between the worklist's counts and the scope's, as text, or nil when they tie.
function difference_of(worklist, from_scope)
    local names = order.keys(worklist)
    for _, fw in ipairs(order.keys(from_scope)) do
        if worklist[fw] == nil then
            return fw .. ": in the scope, not in the work list"
        end
    end
    for _, fw in ipairs(names) do
        local w, s = worklist[fw], from_scope[fw]
        if s == nil then
            return fw .. ": in the work list, not in the scope"
        end
        if w.rows ~= s.rows then
            return string.format("%s: %d rows in the work list, %d in the scope", fw, w.rows, s.rows)
        end
        for _, state in ipairs(order.keys(w.states)) do
            if (s.states[state] or 0) ~= w.states[state] then
                return string.format("%s: state '%s' %d in the work list, %s in the scope", fw, state, w.states[state],
                                     tostring(s.states[state]))
            end
        end
        for _, state in ipairs(order.keys(s.states)) do
            if (w.states[state] or 0) ~= s.states[state] then
                return string.format("%s: state '%s' %s in the work list, %d in the scope", fw, state,
                                     tostring(w.states[state]), s.states[state])
            end
        end
    end
    return nil
end

local TOTALS_HEADER = "framework\trows\tin_6_1_3\toverridden\tgenerated_stub\theader_only\tnot_named\tqueued\tby_hand"

-- One totals line: the module's name and its counts, by_hand being the generated stubs and the queued rows.
function totals_line(name, counts)
    local d = counts.design
    return table.concat({name, counts.rows, d[DESIGN_IN_RELEASE], d[DESIGN_OVERRIDDEN], d[DESIGN_GENERATED], d[DESIGN_HEADER_ONLY],
                         d[DESIGN_NONE], counts.queued, d[DESIGN_GENERATED] + counts.queued}, "\t")
end

-- Adds a module's counts into the run's total.
local function add_counts(total, counts)
    total.rows = total.rows + counts.rows
    total.queued = total.queued + counts.queued
    for design, n in pairs(counts.design) do
        total.design[design] = total.design[design] + n
    end
end

-- Returns the exit status and a line of counts; 0 when the counts tie to the scope, else 1 (the files are written either way).
function run(args)
    assert(args.sdk, "worklist needs --sdk: the iPhoneOS SDK (the release names the surface table)")
    assert(args.coordination, "worklist needs --coordination: the corpus folder (the surface table and the ledgers)")
    assert(args.tree, "worklist needs --tree: the repository")
    assert(args.out, "worklist needs --out: the folder the work list is written to")
    assert(args.scope, "worklist needs --scope: the scope's v-gen-scope.tsv the counts tie to")
    local release = sdk_info.discover(args.sdk).version
    local compile = sdk_info.discover(project.sdk16(args)).version
    local states = scope.states_of(release, compile)
    local all = surface.all_rows(args.coordination, release)
    local skipped = coverage.skipped(args.tree)
    os.mkdir(args.out)
    local lines_of_totals = {TOTALS_HEADER}
    local total = {rows = 0, queued = 0, design = {[DESIGN_IN_RELEASE] = 0, [DESIGN_OVERRIDDEN] = 0, [DESIGN_GENERATED] = 0,
                                                    [DESIGN_HEADER_ONLY] = 0, [DESIGN_NONE] = 0}}
    local worklist = {}
    for _, group in ipairs(scope.counted_groups(args.tree, all)) do
        local lines = {}
        local counts = module_of(args, group, states, skipped, lines)
        emit.file(path.join(args.out, (string.gsub(group.fw, "/", "+")) .. ".tsv"),
                  strings.backslash_replace(table.concat(lines, "\n") .. "\n"))
        table.insert(lines_of_totals, totals_line(group.fw, counts))
        add_counts(total, counts)
        worklist[group.fw] = {rows = counts.rows, states = counts.states}
    end
    table.insert(lines_of_totals, totals_line("all", total))
    emit.file(path.join(args.out, "totals.tsv"), table.concat(lines_of_totals, "\n") .. "\n")

    local difference = difference_of(worklist, scope_counts_of(args.scope))
    local detail = string.format("%d modules, %d rows: %d in 6.1.3, %d overridden, %d generated stub, %d header only, %d not named, %d queued",
                                 #lines_of_totals - 2, total.rows, total.design[DESIGN_IN_RELEASE], total.design[DESIGN_OVERRIDDEN],
                                 total.design[DESIGN_GENERATED], total.design[DESIGN_HEADER_ONLY], total.design[DESIGN_NONE], total.queued)
    if difference ~= nil then
        return 1, detail .. "; DOES NOT TIE to the scope: " .. difference
    end
    return 0, detail .. "; ties to the scope"
end
