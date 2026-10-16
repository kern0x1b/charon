-- `ledger`: the 6.1.3 ledger's cache pass over the whole model. For every framework of the model it reads the declarations the model gives
-- that framework (surface_model.declarations, claimed by the owner rule) and checks each checkable one against the release's own dyld
-- shared cache (ledger.lua): a framework none of whose own declarations is in the cache is absent from the release, with that reason. Writes
-- framework-verdicts-<release>.tsv into --out and prints the counts and the absent list. --sdk gives the SDK whose shards are read, --release
-- the cache's release (6.1.3 by default), --tree the repository (the readers run from it). Returns the exit status: 0 when the file is written.

local emit = import("emit", {anonymous = true})
local surface_model = import("surface_model", {anonymous = true})
local sdk_info = import("sdk", {anonymous = true})
local ledger = import("ledger", {anonymous = true})

-- Returns the exit status: 0 when the verdicts are written.
function run(args)
    assert(args.out, "ledger needs --out: the folder framework-verdicts-<release>.tsv is written to")
    assert(args.sdk, "ledger needs --sdk: the iPhoneOS SDK whose declaration shards the model is read from")
    local release = args.release or "6.1.3"
    local sdk_release = sdk_info.discover(args.sdk).version
    local decls = surface_model.declarations(args.tree, sdk_release)
    local facts, cache, objc_text, export_text = ledger.read_release(args.tree, release)
    if args.dump then
        emit.file(path.join(args.dump, "objc-inventory-" .. release .. ".tsv"), objc_text)
        emit.file(path.join(args.dump, "exports-" .. release .. ".tsv"), export_text)
    end
    print(string.format("ledger: %s cache %s: %d classes, %d protocols, %d exported symbols", release, cache,
                        #table.keys(facts.classes), #table.keys(facts.protocols), #table.keys(facts.exports)))
    -- the symbols each framework's 26.2 .tbd exports, read once per framework; a unit the SDK has no framework for exports none
    local tbd = import("tbd", {anonymous = true})
    local exports_memo = {}
    local function exported(unit)
        if exports_memo[unit] == nil then
            exports_memo[unit] = tbd.has_framework(args.sdk, unit) and tbd.exports(args.sdk, unit) or {}
        end
        return exports_memo[unit]
    end
    local verdicts = ledger.verdicts(decls, facts, exported)
    local names = table.keys(verdicts)
    table.sort(names)
    local lines = {"framework\tverdict\tcheckable\tpresent\treason"}
    local counts, absent = {}, {}
    for _, fw in ipairs(names) do
        local v = verdicts[fw]
        counts[v.verdict] = (counts[v.verdict] or 0) + 1
        if v.verdict == "absent" then
            table.insert(absent, fw)
        end
        table.insert(lines, table.concat({fw, v.verdict, v.checkable, v.present, v.reason}, "\t"))
    end
    emit.file(path.join(args.out, "framework-verdicts-" .. release .. ".tsv"), table.concat(lines, "\n") .. "\n")
    print(string.format("ledger: %d frameworks: present %d, absent %d, undecided %d", #names, counts.present or 0, counts.absent or 0,
                        counts.undecided or 0))
    print("ledger: absent at " .. release .. ": " .. table.concat(absent, ", "))
    return 0
end
