-- `swift`: writes spec/swift/bucket.tsv, one row per Swift bucket row (see swift.lua), through emit. --coordination is the corpus folder.

local swift = import("swift", {anonymous = true})
local emit = import("emit", {anonymous = true})

-- Returns the exit status.
function run(args)
    assert(args.coordination, "--coordination (the corpus folder) is required")
    local rows, matched, frameworks = swift.bucket(args.tree, args.coordination)
    emit.file(swift.bucket_path(args.tree), swift.bucket_text(rows))
    print(string.format("swift: %d bucket rows, %d matched by the table (%d frameworks)", #rows, matched, frameworks))
    return 0
end
