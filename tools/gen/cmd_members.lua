-- `members`: re-reads the member rows of a framework's snapshot from its declaration shard (headers.shard_facts), keeping the
-- constant rows as they are (the constant layer is not re-derived here). The record of members (members.tsv) is not written:
-- `gen --record` writes it after the change is reviewed. Prints the same summary the oracle's cmd_members prints.

local layout = import("layout", {anonymous = true})
local snapshot = import("spec", {anonymous = true})
local emit = import("emit", {anonymous = true})
local digest = import("digest", {anonymous = true})
local tsv = import("tsv", {anonymous = true})
local headers = import("headers", {anonymous = true})
local tbd = import("tbd", {anonymous = true})
local members = import("members", {anonymous = true})

-- Returns the exit status.
function run(args)
    local fw = args.framework
    local before = {}
    local kept = {}
    local types = headers.constant_types(args.tree, fw)
    for _, r in ipairs(snapshot.load(args.tree, fw)) do
        if r.kind == "method" or r.kind == "property" then
            before[r.api] = r
        else
            if r.kind == "constant" then
                -- the constant's type comes from the shard's variable of the same name, in place of the declaration text
                r.type = types[r.api] or "-"
            end
            table.insert(kept, r)
        end
    end
    local _, classes = tbd.exports(args.sdk, fw)
    local fresh = members.rows(headers.shard_facts(args.tree, fw).members, classes, fw)
    local rows = table.move(kept, 1, #kept, 1, {})
    for _, r in ipairs(fresh) do
        table.insert(rows, r)
    end
    -- two members can mangle to one identifier: both then carry a digest of their full name, so no member is dropped
    local count = {}
    for _, r in ipairs(rows) do
        count[r.key] = (count[r.key] or 0) + 1
    end
    for _, r in ipairs(rows) do
        if count[r.key] > 1 then
            r.key = r.key .. "_" .. string.sub(digest.digest("key", r.api), 1, 8)
        end
    end
    local columns = layout.constants().SPEC_COLUMNS
    local lines = {}
    for _, r in ipairs(rows) do
        local cells = {}
        for _, name in ipairs(columns) do
            table.insert(cells, r[name] or "-")
        end
        table.insert(lines, cells)
    end
    emit.file(layout.spec_path(args.tree, fw), tsv.table_text(columns, lines))
    local after, added, changed = {}, 0, {}
    for _, r in ipairs(fresh) do
        after[r.api] = r
    end
    for api, r in pairs(after) do
        if before[api] == nil then
            added = added + 1
        elseif before[api].hash ~= r.hash then
            table.insert(changed, api)
        end
    end
    local removed = 0
    for api in pairs(before) do
        if after[api] == nil then
            removed = removed + 1
        end
    end
    table.sort(changed)
    local afterCount, beforeCount = 0, 0
    for _ in pairs(after) do afterCount = afterCount + 1 end
    for _ in pairs(before) do beforeCount = beforeCount + 1 end
    print(string.format("members %s: %d member rows (was %d): %d added, %d removed, %d with a changed declaration",
        fw, afterCount, beforeCount, added, removed, #changed))
    for i = 1, math.min(#changed, 20) do
        print("  changed: " .. changed[i])
    end
    return 0
end
