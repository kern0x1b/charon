-- The corpus the trace layer, the docs and the scope read beside the snapshot: the 26.2 surface table, the ledgers of the release
-- each band measured, the host oracle's defaults, and the registry rows of a framework whatever their status. The corpus is the
-- coordination folder's corpus/ directory, passed in by the command (--coordination); nothing here names a host path.

local layout = import("layout", {anonymous = true})
local tsv = import("tsv", {anonymous = true})
local files = import("files", {anonymous = true})
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

-- (kind, api) -> status for the framework's rows the ledger of a release lists; a row it does not list is implemented in it.
function ledger_status(corpus, fw, release_dir)
    local out = {}
    local text = files.read_text(path.join(corpus, release_dir, fw .. ".tsv"))
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

-- The surface table, read once: framework -> (kind, api) key -> the surface row (demand, impl-lead, deprecation), and framework -> the
-- keys in the order the table first names them. A key that the table names again keeps its first place and takes the later row, as
-- a Python dict does. Read a line at a time from the file, so the 16 MB table is never held as one string.
local function surface(corpus)
    if surface_memo[corpus] then
        return surface_memo[corpus]
    end
    local rows, order, sequence = {}, {}, {}
    local header = nil
    for line in io.lines(path.join(corpus, "sdk-26.2-surface.tsv")) do
        local cells = tsv.fields(line)
        if header == nil then
            header = cells
        else
            local row = {}
            for column, name in ipairs(header) do
                row[name] = cells[column]
            end
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
        end
    end
    surface_memo[corpus] = {rows = rows, order = order, sequence = sequence}
    return surface_memo[corpus]
end

-- (kind, api) -> the surface row for one framework.
function surface_rows(corpus, fw)
    return surface(corpus).rows[fw] or {}
end

-- The surface rows of one framework as a list, in the order the table first names each (kind, api); each is the row the table
-- gives that key last. The bucket of bucket.tsv is written in this order.
function ordered_rows(corpus, fw)
    local data = surface(corpus)
    local out = {}
    for _, k in ipairs(data.sequence[fw] or {}) do
        table.insert(out, data.rows[fw][k])
    end
    return out
end

-- Every framework the surface table names, in the table's order.
function surface_frameworks(corpus)
    local known = surface(corpus).order
    return table.move(known, 1, #known, 1, {})
end

-- Every row of the surface table, a row the table names twice included: {rows = fw -> the framework's rows in the table's order, order =
-- the frameworks in the order the table first names them}. The scope counts each row, so it cannot use the map of surface_rows, which
-- keeps one row per key. Read a line at a time, and the empty lines skipped, as csv.DictReader skips them.
function all_rows(corpus)
    local rows, order = {}, {}
    local header = nil
    for line in io.lines(path.join(corpus, "sdk-26.2-surface.tsv")) do
        local cells = tsv.fields(line)
        if header == nil then
            header = cells
        elseif line ~= "" then
            local row = {}
            for column, name in ipairs(header) do
                row[name] = cells[column]
            end
            if rows[row.framework] == nil then
                rows[row.framework] = {}
                table.insert(order, row.framework)
            end
            table.insert(rows[row.framework], row)
        end
    end
    return {rows = rows, order = order}
end

-- class -> the list of {item, value_kind, value, build} from the host oracle capture, for one framework.
function oracle_defaults(corpus, fw)
    local out = {}
    local text = files.read_text(path.join(corpus, "cache-26.2", "oracle-defaults.tsv"))
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

-- The registry rows of a framework, whatever their status: canonical key -> {registry = path, entry = row}, the first row of a
-- key winning over the files sorted by name.
function registry_entries(tree, fw)
    local found = {}
    local single = path.join(tree, layout.constants().REGISTRY, fw .. ".json")
    local candidates = files.glob(path.join(tree, layout.registry_dir(fw), "*.json"))
    if os.isfile(single) then
        table.insert(candidates, single)
    end
    table.sort(candidates)
    for _, filepath in ipairs(candidates) do
        local data = json.decode(files.read_text(filepath))
        local entries = data.entries or data
        local relative = path.join(layout.registry_dir(fw), path.filename(filepath))
        if filepath == single then
            relative = path.join(layout.constants().REGISTRY, fw .. ".json")
        end
        for _, entry in ipairs(entries) do
            local canonical = canonical_member(entry.api, entry.kind or "method")
            if found[canonical] == nil then
                found[canonical] = {registry = relative, entry = entry}
            end
        end
    end
    return found
end
