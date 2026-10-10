-- `gen`: writes the generated files of a framework (or of every framework with a snapshot) into the build directory, through emit,
-- so a file the tree already holds is not rewritten. --record also writes the manifest of digests and the members record that
-- `check` compares with.

local layout = import("layout", {anonymous = true})
local snapshot = import("spec", {anonymous = true})
local render = import("render", {anonymous = true})
local emit = import("emit", {anonymous = true})
local digest = import("digest", {anonymous = true})
local files = import("files", {anonymous = true})
local tsv = import("tsv", {anonymous = true})

-- The frameworks that have a committed snapshot, sorted.
function frameworks(tree)
    local names = {}
    for _, spec in ipairs(files.glob(path.join(tree, layout.constants().SNAP_ROOT, "*", "spec." .. layout.constants().SDK_ID .. ".tsv"))) do
        table.insert(names, files.parent_name(spec))
    end
    table.sort(names)
    return names
end

-- The sorted names of a table's keys.
local function names_of(map)
    local out = {}
    for name in pairs(map) do
        table.insert(out, name)
    end
    table.sort(out)
    return out
end

-- The declaration hash of a spec row: the hash the row records. A member's is the extractor's declhash (the canonical fields of its
-- declaration, design-foundation.md 5.3), a constant's the hash its row records. The spec holds no declaration text, so no digest is
-- recomputed here from it.
function spec_hash(r)
    return r.hash
end

-- The constants objects a previous generation wrote and this one no longer emits.
function stale_constants(base, fw, emitted)
    local out = {}
    for _, found in ipairs(files.glob(path.join(base, fw .. "Constants*.m"))) do
        local name = path.filename(found)
        if emitted[name] == nil then
            table.insert(out, name)
        end
    end
    table.sort(out)
    return out
end

-- The members the snapshot records against the spec: changed (declaration hash differs from the record), new (no record) and
-- removed (recorded, no longer in the spec). nil when no record is committed yet.
function member_changes(tree, fw)
    local recorded = snapshot.members(tree, fw)
    if recorded == nil then
        return nil
    end
    local current = {}
    for _, r in ipairs(snapshot.load(tree, fw)) do
        current[r.api] = spec_hash(r)
    end
    local result = {changed = {}, new = {}, removed = {}}
    for api in pairs(current) do
        if recorded[api] == nil then
            table.insert(result.new, api)
        end
    end
    for api in pairs(recorded) do
        if current[api] == nil then
            table.insert(result.removed, api)
        end
    end
    for _, api in ipairs(names_of(current)) do
        if recorded[api] ~= nil and recorded[api] ~= current[api] then
            table.insert(result.changed, {api, recorded[api], current[api]})
        end
    end
    table.sort(result.new)
    table.sort(result.removed)
    return result
end

local function record(tree, fw, emitted)
    local manifest = {}
    for _, name in ipairs(names_of(emitted)) do
        table.insert(manifest, {name, digest.digest_of(emitted[name])})
    end
    emit.file(layout.manifest_path(tree, fw), tsv.table_text({"file", "sha256"}, manifest))
    local members = {}
    for _, r in ipairs(snapshot.load(tree, fw)) do
        if r.kind == "method" or r.kind == "property" or r.kind == "constant" then
            table.insert(members, {r.api, spec_hash(r)})
        end
    end
    emit.file(layout.members_path(tree, fw), tsv.table_text({"api", "hash"}, members))
end

-- Returns the exit status: 1 when a member declaration changed since the record and --record was not given.
function run(args)
    local targets = args.all and frameworks(args.tree) or {args.framework}
    for _, fw in ipairs(targets) do
        local emitted = render.render(args.tree, fw)
        local base = layout.gen_dir(args.tree, fw)
        for _, name in ipairs(stale_constants(base, fw, emitted)) do
            os.rm(path.join(base, name))
        end
        local before = emit.count()
        local names = names_of(emitted)
        for _, name in ipairs(names) do
            emit.file(path.join(base, name), emitted[name])
        end
        local changes = member_changes(args.tree, fw)
        if changes and #changes.changed > 0 and not args.record then
            for _, change in ipairs(changes.changed) do
                print(string.format("CHANGED %s: declaration hash %s -> %s (review the override or the stub, then gen --record)",
                    change[1], change[2], change[3]))
            end
            print(string.format("gen %s: refused, %d member declaration(s) changed since the record", fw, #changes.changed))
            return 1
        end
        if args.record then
            record(args.tree, fw, emitted)
        end
        print(string.format("gen %s: %d files in %s%s (%d written)", fw, #names, layout.constants().OUT_ROOT .. "/" .. fw,
            args.record and " (manifest recorded)" or "", emit.count() - before))
    end
    return 0
end
