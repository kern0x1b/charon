-- The generator of apple-backports, in Lua: `xmake l tools/gen.lua <command> --tree T [options]`.
-- Commands ported so far: gen, check, pin. The rest of the commands are still in tools/gen.py (the oracle) until ported; the
-- driver refuses them by name rather than falling back to Python. See coordination/wave-2026-10-03/design-spec-driven.md.


local BOOLEAN_OPTIONS = {all = true, record = true, members = true, catalyst = true}
local VALUE_OPTIONS = {tree = true, framework = true, ledger = true, sdk = true, owned = true, measured = true,
                       ["ios-constants"] = true, repin = true, class = true, out = true, limit = true, selector = true,
                       ["catalyst-sdk"] = true}
local COMMANDS = {gen = "gen", check = "check", pin = "pin"}
local PORTED_LATER = {"input", "diff", "sources", "classify", "doc", "scope", "protocols", "functions", "objc", "swift", "behaviour",
                      "trace"}

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

function main(command, ...)
    local argv = {...}
    if command == nil or COMMANDS[command] == nil then
        for _, name in ipairs(PORTED_LATER) do
            if name == command then
                print("gen: " .. command .. " is not ported to Lua yet (still in tools/gen.py)")
                os.exit(2)
            end
        end
        print("usage: xmake l tools/gen.lua {gen|check|pin} --tree T [--framework F | --all] [--record] [--repin KEY]")
        os.exit(2)
    end
    local args = parse(argv)
    assert(args.tree, "--tree is required")
    assert(args.framework or (args.all and command ~= "pin"), "--framework is required (gen and check accept --all)")
    local status = import("gen.cmd_" .. command, {rootdir = os.scriptdir(), anonymous = true}).run(args)
    if status ~= 0 then
        os.exit(status)
    end
end
