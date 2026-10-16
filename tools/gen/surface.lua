-- The corpus the trace layer, the docs and the scope read beside the snapshot: the surface (computed from the model by
-- surface_model.lua, not read from a table), the ledgers of the release each band measured, the host oracle's defaults, and the
-- registry rows of a framework whatever their status. The corpus is the coordination folder's corpus/ directory, passed in by the
-- command (--coordination); the tree is --tree. Nothing here names a host path.

local layout = import("layout", {anonymous = true})
local sdk = import("sdk", {anonymous = true})
local tsv = import("tsv", {anonymous = true})
local files = import("files", {anonymous = true})
local order = import("order", {anonymous = true})
local surface_model = import("surface_model", {anonymous = true})
local json = import("core.base.json")

local surface_memo = {}

-- The key of a (kind, api) pair in the maps below.
function key(kind, api)
    return kind .. "\t" .. api
end

-- The key a member has in the trace layer's stub list: a property written 'Class.name' is '-[Class name]'.
function canonical_member(api, kind)
    if kind == "property" and string.sub(api, 1, 2) ~= "-[" and string.sub(api, 1, 2) ~= "+[" and string.find(api, ".", 1, true) then
        local cls, name = string.match(api, "^([^.]*)%.(.*)$")
        return "-[" .. cls .. " " .. name .. "]"
    end
    return api
end

-- The corpus folders of the two ledgers the generator reads: the 6.1.3 release (ledger-w45) and the 4.3 release.
local LEDGER_6_1_3 = "ledger-w45"
local LEDGER_4_3 = "ledger-w45-4.3"

function ledger_6_1_3()
    return LEDGER_6_1_3
end

function ledger_4_3()
    return LEDGER_4_3
end

-- The ledger file of a framework in a release folder. A nested framework (include/AppleArchive, the surface's name) has its ledger as
-- include_AppleArchive.tsv: the slash of its name is an underscore in the file name, as the corpus writes it. Every reader of a
-- ledger goes through this one mapping.
function ledger_file(corpus, release_dir, fw)
    return path.join(corpus, release_dir, (string.gsub(fw, "/", "_")) .. ".tsv")
end

-- True when the release folder has a ledger for the framework (without one every member is considered).
function has_ledger(corpus, release_dir, fw)
    return os.isfile(ledger_file(corpus, release_dir, fw))
end

-- The frameworks `input --all` skips, each with the reason it names: spec/input-skips.tsv (framework, reason), committed. input builds
-- every other surface framework, so the ledger is the record of what has no constant record and no functions to read (the oracle's
-- functions command reads the build table input writes; the Lua reads this list instead). Returns name -> reason.
function skip_ledger(tree)
    local file = path.join(tree, layout.constants().SNAP_ROOT, "input-skips.tsv")
    assert(os.isfile(file), "the skip ledger is not found: " .. file)
    local known = {}
    for _, row in ipairs(tsv.records(files.read_text(file))) do
        known[row.framework] = row.reason
    end
    return known
end

-- (kind, api) -> status for the framework's rows the ledger of a release lists; a row it does not list is implemented in it.
function ledger_status(corpus, fw, release_dir)
    local out = {}
    local text = files.read_text(ledger_file(corpus, release_dir, fw))
    if not text then
        return out
    end
    for _, row in ipairs(tsv.records(text)) do
        if row.kind and row.kind ~= "" and row.api and row.api ~= "" then
            out[key(row.kind, row.api)] = row.status
        end
    end
    return out
end

-- The surface, read once from the model (surface_model.lua: the declaration and Swift shards of the tree, with the corpus's demand and
-- file lists): framework -> (kind, api) key -> the surface row (demand, impl-lead, deprecation), and framework -> the keys in the order
-- the surface first names them. A key that the surface names again keeps its first place and takes the later row, as a Python dict
-- does. Also every row in its order, a row named twice included (all_rows).
local function surface(tree, corpus, release)
    local memo_key = tree .. "\t" .. corpus .. "\t" .. release
    if surface_memo[memo_key] then
        return surface_memo[memo_key]
    end
    local rows, order, sequence = {}, {}, {}
    local every = {rows = {}, order = {}}
    for _, row in ipairs(surface_model.rows(tree, corpus, release)) do
        if rows[row.framework] == nil then
            rows[row.framework] = {}
            sequence[row.framework] = {}
            table.insert(order, row.framework)
        end
        local k = key(row.kind, row.api)
        if rows[row.framework][k] == nil then
            table.insert(sequence[row.framework], k)
        end
        rows[row.framework][k] = row
        if every.rows[row.framework] == nil then
            every.rows[row.framework] = {}
            table.insert(every.order, row.framework)
        end
        table.insert(every.rows[row.framework], row)
    end
    surface_memo[memo_key] = {rows = rows, order = order, sequence = sequence, every = every}
    return surface_memo[memo_key]
end

-- (kind, api) -> the surface row for one framework.
function surface_rows(tree, corpus, release, fw)
    return surface(tree, corpus, release).rows[fw] or {}
end

-- The surface rows of one framework as a list, in the order the surface names each (kind, api); each is the row the surface gives
-- that key last. The bucket of bucket.tsv is written in this order.
function ordered_rows(tree, corpus, release, fw)
    local data = surface(tree, corpus, release)
    local out = {}
    for _, k in ipairs(data.sequence[fw] or {}) do
        table.insert(out, data.rows[fw][k])
    end
    return out
end

-- Every framework the surface names, in the order the surface first names them.
function surface_frameworks(tree, corpus, release)
    local known = surface(tree, corpus, release).order
    return table.move(known, 1, #known, 1, {})
end

-- Every row of the surface, a row named twice included: {rows = fw -> the framework's rows in the surface's order, order = the
-- frameworks in the order the surface first names them}. The scope counts each row, so it cannot use the map of surface_rows, which
-- keeps one row per key.
function all_rows(tree, corpus, release)
    return surface(tree, corpus, release).every
end

-- class -> the list of {item, value_kind, value, build} from the host oracle capture, for one framework.
function oracle_defaults(corpus, release, fw)
    local out = {}
    local text = files.read_text(path.join(corpus, sdk.names(release).oracle_defaults))
    if not text then
        return out
    end
    for _, row in ipairs(tsv.records(text)) do
        if row.framework == fw then
            out[row.class] = out[row.class] or {}
            table.insert(out[row.class], {row.item, row.value_kind, row.value, row.build})
        end
    end
    return out
end

-- Every row of a framework's registry files, whatever its status, in the files' order (sorted by name): {registry = path, entry = row}.
function registry_rows(tree, fw)
    local out = {}
    local single = path.join(tree, layout.constants().REGISTRY, fw .. ".json")
    local candidates = files.glob(path.join(tree, layout.registry_dir(fw), "*.json"))
    if os.isfile(single) then
        table.insert(candidates, single)
    end
    table.sort(candidates, order.less)
    for _, filepath in ipairs(candidates) do
        local data = json.decode(files.read_text(filepath))
        local entries = data.entries or data
        local relative = path.join(layout.registry_dir(fw), path.filename(filepath))
        if filepath == single then
            relative = path.join(layout.constants().REGISTRY, fw .. ".json")
        end
        for _, entry in ipairs(entries) do
            table.insert(out, {registry = relative, entry = entry})
        end
    end
    return out
end

-- The registry rows of a framework, whatever their status: canonical key -> {registry = path, entry = row}, the first row of a
-- key winning over the files sorted by name.
function registry_entries(tree, fw)
    local found = {}
    for _, row in ipairs(registry_rows(tree, fw)) do
        local canonical = canonical_member(row.entry.api, row.entry.kind or "method")
        if found[canonical] == nil then
            found[canonical] = row
        end
    end
    return found
end

-- The constants the registry names, by name, in any status: a row of any registry file, of kind constant, whose owner is not the
-- generator. The generator does not emit these: a name the registry holds is either defined by hand (an inert or implemented row
-- says so) or refused by the registry check, which names a generated row twice (registry() in modules/apple/backports.lua).
function registry_constants(tree, fw)
    local names = {}
    for _, row in ipairs(registry_rows(tree, fw)) do
        local entry = row.entry
        if entry.kind == "constant" and string.sub(entry.owner or "", 1, 10) ~= "generator:" then
            names[entry.api] = true
        end
    end
    return names
end
