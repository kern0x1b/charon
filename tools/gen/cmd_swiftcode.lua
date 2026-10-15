-- `swiftcode`: writes each Swift module's compilable skeleton (swift_render.lua) from the full model (swift_model.lua) under --out,
-- one .swift per module. A build product, never committed. --sdk is the SDK, --out the folder, --framework runs one module (a
-- measurement). The digester runs through heavy.sh; --coordination names the corpus folder heavy.sh sits beside (default: the
-- workspace's).

local swift_model = import("swift_model", {anonymous = true})
local swift_render = import("swift_render", {anonymous = true})

-- The path of coordination/heavy.sh: beside --coordination when it is given, else the workspace's coordination folder.
local function heavy_path(args)
    if args.coordination then
        return path.join(args.coordination, "heavy.sh")
    end
    return path.join(os.getenv("HOME"), "Git", "projects", "ios", "coordination", "heavy.sh")
end

-- Renders one module's model into out_dir/<name>.swift. Returns the number of rows rendered, or nil and the reason it has none.
local function write_swift(heavy, sdk, triple, out_dir, name)
    local rows, reason = swift_model.model(heavy, sdk, triple, name)
    if rows == nil then
        return nil, reason
    end
    local filepath = path.join(out_dir, name .. ".swift")
    local emit = import("emit", {anonymous = true})
    emit.file(filepath, swift_render.render(rows, name))
    return #rows
end

-- Returns the exit status.
function run(args)
    assert(args.sdk, "--sdk (the SDK folder) is required")
    assert(args.out, "--out (the folder to write the code into) is required")
    local heavy = heavy_path(args)
    assert(os.isfile(heavy), "no heavy.sh: " .. heavy)
    local names = args.framework and {args.framework} or swift_model.modules(args.sdk)
    local triple = swift_model.triple_of(args.sdk)
    os.mkdir(args.out)
    local started = os.mclock()
    local written, missing, total = 0, 0, 0
    for _, name in ipairs(names) do
        local rows, reason = write_swift(heavy, args.sdk, triple, args.out, name)
        if rows then
            written = written + 1
            total = total + rows
            print(string.format("swiftcode: %s %d declarations", name, rows))
        else
            missing = missing + 1
            print(string.format("swiftcode: %s no code: %s", name, reason))
        end
    end
    local seconds = (os.mclock() - started) / 1000
    print(string.format("swiftcode: %d modules, %d declarations, %d modules without code, %.1fs", written, total, missing, seconds))
    return 0
end
