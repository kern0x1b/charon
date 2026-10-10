-- The targets of the SDK entries that have no declaration shard of their own, read as data from the extractor's configuration
-- (tools/found/config, the foundation's classification): no-own.tsv names, for an umbrella framework, the nested frameworks whose
-- shards hold its declarations (Accelerate: Accelerate/vImage and Accelerate/vecLib), and products.tsv names, for a product folder
-- that is not an SDK framework, the SDK frameworks whose shards declare its identifiers (Graphics). Nothing here is written.

local files = import("files", {anonymous = true})

-- The rows of a configuration file: tab-separated, one per line, without the comment lines (those starting with #).
local function rows_of(filepath)
    local out = {}
    local text = files.read_text(filepath)
    if text == nil then
        return out
    end
    for line in string.gmatch(text, "[^\n]+") do
        if string.sub(line, 1, 1) ~= "#" then
            local cells = {}
            for cell in (line .. "\t"):gmatch("([^\t]*)\t") do
                table.insert(cells, cell)
            end
            table.insert(out, cells)
        end
    end
    return out
end

-- The frameworks of the configuration folder's list named by a comma list (a "-" is none).
local function list_of(text)
    local out = {}
    if text == nil or text == "-" then
        return out
    end
    for item in string.gmatch(text, "[^,]+") do
        table.insert(out, item)
    end
    return out
end

-- The umbrella frameworks of no-own.tsv: name -> {class = ..., targets = {the nested frameworks}}.
function umbrellas(tree)
    local out = {}
    for _, cells in ipairs(rows_of(path.join(tree, "tools", "found", "config", "no-own.tsv"))) do
        out[cells[1]] = {class = cells[2], targets = list_of(cells[3])}
    end
    return out
end

-- The product folders of products.tsv: name -> the SDK frameworks whose shards declare its identifiers.
function products(tree)
    local out = {}
    for _, cells in ipairs(rows_of(path.join(tree, "tools", "found", "config", "products.tsv"))) do
        out[cells[1]] = list_of(cells[2])
    end
    return out
end
