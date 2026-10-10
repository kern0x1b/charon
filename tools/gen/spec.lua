-- The snapshot of a framework as the generator reads it: the spec table, the hand-written overrides (registry rows the generator
-- skips), the pins that name the declaration each override was written against, and the records `check` compares with.

local layout = import("layout", {anonymous = true})
local tsv = import("tsv", {anonymous = true})
local files = import("files", {anonymous = true})
local decl = import("decl", {anonymous = true})
local order = import("order", {anonymous = true})
local json = import("core.base.json")

-- The spec rows of a framework, in the snapshot's order.
function load(tree, fw)
    local text = files.read_text(layout.spec_path(tree, fw))
    assert(text, "no spec snapshot for " .. fw)
    return tsv.records(text)
end

-- Every spec row under its own api and, for a property, under the dotted name the registry uses (Class.name). The first row
-- of a key wins, as the oracle's setdefault does.
function index(rows)
    local found = {}
    local function add(key, row)
        if found[key] == nil then
            found[key] = row
        end
    end
    for _, r in ipairs(rows) do
        add(r.api, r)
        if r.kind == "property" then
            local name = decl.member_name(r.api)
            add(r.cls .. "." .. name, r)
        end
    end
    return found
end

local OVERRIDE_KINDS = {method = true, property = true, class = true}

-- The hand-written registry rows of a framework that are implemented: api -> {registry = path, entry = row}, with the first row
-- of an api winning, and order = the apis in the order they were found (files sorted by name, rows in file order).
function overrides(tree, fw)
    local found, order = {}, {}
    for _, filepath in ipairs(files.glob(path.join(tree, layout.registry_dir(fw), "*.json"))) do
        local data = json.decode(files.read_text(filepath))
        local entries = data.entries or data
        for _, entry in ipairs(entries) do
            local owner = entry.owner or ""
            if entry.status == "implemented" and OVERRIDE_KINDS[entry.kind] and string.sub(owner, 1, 10) ~= "generator:" then
                if found[entry.api] == nil then
                    found[entry.api] = {registry = path.join(layout.registry_dir(fw), path.filename(filepath)), entry = entry}
                    table.insert(order, entry.api)
                end
            end
        end
    end
    return found, order
end

-- The pins of a framework, in the sidecar's order; none when no sidecar is committed.
function pins(tree, fw)
    local text = files.read_text(layout.pins_path(tree, fw))
    if not text then
        return {}
    end
    return tsv.records(text)
end

-- The pins as the sidecar holds them, sorted by key.
function pins_text(list)
    local sorted = table.move(list, 1, #list, 1, {})
    table.sort(sorted, function(a, b) return order.less(a.key, b.key) end)
    local rows = {}
    for _, p in ipairs(sorted) do
        table.insert(rows, {p.api, p.key, p.pinned, p["pinned-by"], p.registry})
    end
    return tsv.table_text(layout.constants().PIN_COLUMNS, rows)
end

-- The members record: api -> the declaration hash recorded for it, or nil when no record is committed.
function members(tree, fw)
    local text = files.read_text(layout.members_path(tree, fw))
    if not text then
        return nil
    end
    local out = {}
    local all = tsv.lines(text)
    for i = 2, #all do
        if all[i] ~= "" then
            local cells = tsv.fields(all[i])
            out[cells[1]] = cells[2]
        end
    end
    return out
end

-- The manifest: file -> sha256 of the text the generator emits, as the snapshot records it, or nil when none is committed.
function manifest(tree, fw)
    local text = files.read_text(layout.manifest_path(tree, fw))
    if not text then
        return nil
    end
    local out = {}
    local all = tsv.lines(text)
    for i = 2, #all do
        if all[i] ~= "" then
            local cells = tsv.fields(all[i])
            out[cells[1]] = cells[2]
        end
    end
    return out
end
