-- `classify`: the class of every cell where a constant record differs from its reference (decision 1 of round 14). It reads the records
-- under --tree (spec/<F>/constants.tsv), the reference records under --reference (--against oracle: the oracle's shards
-- <F>/spec.sdk-26.2-headers.tsv; --against committed: <F>/constants.tsv), the SDK's headers, the iOS 26.2 cache table under
-- --coordination, and each framework's held-caches and owned snapshots. Every differing cell gets one class from classify.lua, or
-- is unclassified. The ledger (counts per class per framework, not cells) goes to --out; the command returns 1 while any cell is
-- unclassified, and prints the first of them.

local classify = import("classify", {anonymous = true})
local files = import("files", {anonymous = true})
local emit = import("emit", {anonymous = true})
local layout = import("layout", {anonymous = true})

local SHOWN = 100000

function run(args)
    assert(args.tree, "classify needs --tree: the root whose spec records are checked")
    assert(args.reference, "classify needs --reference: the folder of the reference records (<F>/ holds the file of --against)")
    assert(args.sdk, "classify needs --sdk: the iPhoneOS SDK whose headers are the truth for the declarations")
    assert(args.coordination, "classify needs --coordination: the corpus folder (the iOS 26.2 cache table)")
    assert(args.out, "classify needs --out: the ledger file")
    local against = args.against or "oracle"
    assert(against == "oracle" or against == "committed", "classify --against is oracle or committed")
    local reference_file = against == "oracle" and "spec.sdk-26.2-headers.tsv" or "constants.tsv"
    local cache = classify.cache_values(path.join(args.coordination, "cache-26.2", "constants-26.2.tsv.gz"))
    local spec_root = layout.constants().SNAP_ROOT

    local totals, unclassified, cells_total, frameworks_differing = {}, {}, 0, 0
    local ledger = {"framework\tclass\tcells"}
    local per_framework = {}
    for _, record in ipairs(files.glob(path.join(args.tree, spec_root, "*", "constants.tsv"))) do
        local fw = path.filename(path.directory(record))
        local left = classify.rows_of(files.read_text(record) or "")
        local right = classify.rows_of(files.read_text(path.join(args.reference, fw, reference_file)) or "")
        local cells = classify.cells(fw, left, right, against)
        if #cells > 0 then
            frameworks_differing = frameworks_differing + 1
            local dir = layout.snap_dir(args.tree, fw)
            local ctx = classify.context({headers = {[fw] = classify.framework_headers(args.sdk, fw)}, cache = cache,
                                          held = classify.pairs_of(files.read_text(path.join(dir, "measured.held-caches.tsv")) or ""),
                                          owned = classify.pairs_of(files.read_text(path.join(dir, "owned.tsv")) or "")})
            local _, counts = classify.classify(cells, ctx, args.disabled)
            for _, c in ipairs(cells) do
                cells_total = cells_total + 1
                if c.cls == nil then
                    table.insert(unclassified, fw .. "\t" .. c.api .. "\t" .. c.column .. "\t" .. c.rval .. "\t" .. c.lval)
                end
            end
            for key, n in pairs(counts) do
                totals[key] = (totals[key] or 0) + n
                per_framework[fw .. "\t" .. key] = n
            end
        end
    end
    local keys = {}
    for key in pairs(per_framework) do
        table.insert(keys, key)
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        table.insert(ledger, key .. "\t" .. per_framework[key])
    end
    emit.file(args.out, table.concat(ledger, "\n") .. "\n")

    print("classify --against " .. against .. ": " .. cells_total .. " differing cells in " .. frameworks_differing .. " frameworks")
    local names = {}
    for name in pairs(totals) do
        if name ~= "UNCLASSIFIED" then
            table.insert(names, name)
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        print(string.format("  %-28s %6d", name, totals[name]))
    end
    print(string.format("  %-28s %6d", "UNCLASSIFIED", totals.UNCLASSIFIED or 0))
    if #unclassified > 0 then
        table.sort(unclassified)
        for i = 1, math.min(SHOWN, #unclassified) do
            print("  unclassified: " .. unclassified[i])
        end
        return 1
    end
    return 0
end
