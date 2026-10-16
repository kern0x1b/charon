-- The generator of apple-backports, in Lua: `xmake l tools/gen.lua <command> --tree T [options]`.
-- A command is tools/gen/cmd_<command>.lua: it has run(args) and returns the exit status. Every command in COMMANDS has its module; the
-- driver names a command that has none. The design is in coordination/wave-2026-10-03/design-spec-driven.md.

local BOOLEAN_OPTIONS = {all = true, record = true, members = true, catalyst = true, doc = true}
local VALUE_OPTIONS = {tree = true, framework = true, ledger = true, sdk = true, owned = true, measured = true,
                       ["ios-constants"] = true, repin = true, class = true, out = true, limit = true, selector = true,
                       ["catalyst-sdk"] = true, coordination = true, ["ipsw-cache"] = true, sdk16 = true,
                       ir = true, compare = true, dump = true, release = true}
local COMMANDS = {"input", "pin", "gen", "check", "trace", "diff", "sources", "doc", "scope", "protocols",
                  "functions", "objc", "swift", "swiftshard", "swiftmodel", "swiftcode", "roundtrip", "behaviour", "members",
                  "headers", "sdk", "surface", "swiftiface", "ledger"}

-- The options after the command: --name value, or a flag. Returns a table keyed by the option's name with dashes as underscores.
local function parse(argv)
    local args = {}
    local i = 1
    while i <= #argv do
        local name = string.match(argv[i], "^%-%-(.+)$")
        assert(name, "expected an option, got " .. argv[i])
        local key = string.gsub(name, "%-", "_")
        if BOOLEAN_OPTIONS[name] then
            args[key] = true
            i = i + 1
        elseif VALUE_OPTIONS[name] then
            args[key] = argv[i + 1]
            assert(args[key], "option " .. argv[i] .. " needs a value")
            i = i + 2
        else
            error("unknown option " .. argv[i])
        end
    end
    return args
end

-- Which commands take one framework, and which of those also take every framework with --all (the oracle's rule).
local FRAMEWORK = {input = true, pin = true, gen = true, check = true, trace = true, diff = true, doc = true, protocols = true,
                   functions = true, behaviour = true}
local EVERY_FRAMEWORK = {input = true, gen = true, check = true, trace = true, doc = true, protocols = true, functions = true}

local function known(command)
    for _, name in ipairs(COMMANDS) do
        if name == command then
            return true
        end
    end
    return false
end

function main(command, ...)
    if not known(command) then
        print("usage: xmake l tools/gen.lua <command> --tree T [options]; commands: " .. table.concat(COMMANDS, ", "))
        os.exit(2)
    end
    local module = path.join(os.scriptdir(), "gen", "cmd_" .. command .. ".lua")
    if not os.isfile(module) then
        print("gen: " .. command .. " has no module (tools/gen/cmd_" .. command .. ".lua)")
        os.exit(2)
    end
    local args = parse({...})
    assert(args.tree, "--tree is required")
    assert(not FRAMEWORK[command] or args.framework or (args.all and EVERY_FRAMEWORK[command]),
           command .. " needs --framework" .. (EVERY_FRAMEWORK[command] and " (or --all)" or ""))
    local status = import("gen.cmd_" .. command, {rootdir = os.scriptdir(), anonymous = true}).run(args)
    if status ~= 0 then
        os.exit(status)
    end
end
