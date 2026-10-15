-- `swiftshard`: writes spec/<F>/swift.tsv, the Swift declaration shard of each Swift module of the SDK (swift_shard.lua). --sdk is the SDK,
-- --coordination the corpus folder (coordination/heavy.sh sits beside it); --framework runs one module (a measurement). One line per module.

local swift_shard = import("swift_shard", {anonymous = true})

-- Returns the exit status.
function run(args)
    assert(args.sdk, "--sdk (the SDK folder) is required")
    assert(args.coordination, "--coordination (the corpus folder) is required")
    local heavy, names, triple = swift_shard.plan(args.coordination, args.sdk, args.framework)
    local written, missing = 0, 0
    for _, name in ipairs(names) do
        local rows, reason = swift_shard.write_shard(args.tree, heavy, args.sdk, triple, name)
        if rows then
            written = written + 1
            print(string.format("swiftshard: %s %d rows", name, rows))
        else
            missing = missing + 1
            print(string.format("swiftshard: %s no shard: %s", name, reason))
        end
    end
    print(string.format("swiftshard: %d shards, %d modules without one", written, missing))
    return 0
end
