-- `surface`: the surface of the SDK computed from the model (surface_model.lua): every row of every framework's declaration and Swift
-- shards that arrived after iOS 6.1, with the columns of the surface table. Writes sdk-surface-model.tsv into --out and prints the row
-- count per framework and kind. Nothing else is read and nothing is written into the tree: the readers switch to these rows, and this
-- command is how the rows are measured against the corpus table (the framework, kind and api keys of both). --sdk gives the release.

local emit = import("emit", {anonymous = true})
local surface_model = import("surface_model", {anonymous = true})
local sdk_info = import("sdk", {anonymous = true})

-- Returns the exit status: 0 when the rows are written.
function run(args)
    assert(args.out, "surface needs --out: the folder sdk-surface-model.tsv is written to")
    assert(args.sdk, "surface needs --sdk: the iPhoneOS SDK whose release the shards are checked against")
    local list = surface_model.rows(args.tree, args.coordination, sdk_info.discover(args.sdk).version)
    local counts, names = {}, {}
    for _, record in ipairs(list) do
        local key = record.framework .. "\t" .. record.kind
        if counts[key] == nil then
            counts[key] = 0
            table.insert(names, key)
        end
        counts[key] = counts[key] + 1
    end
    for _, key in ipairs(names) do
        print(string.format("surface: %s %d", string.gsub(key, "\t", " "), counts[key]))
    end
    emit.file(path.join(args.out, "sdk-surface-model.tsv"), surface_model.table_text(list))
    print(string.format("surface: %d rows -> sdk-surface-model.tsv", #list))
    return 0
end
