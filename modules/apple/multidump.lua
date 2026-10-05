-- The clang plugin that answers every -ast-dump-filter query of a list from one parse
-- (multidump/multidump.cpp), built for the clang the lift runs, or nil where it cannot be had.
--
-- Why: a lift asks clang for the declarations of a name thousands of times, and each query was two
-- whole parses of every framework's headers - one for the JSON dump, one for the text one - at
-- 2-5 s each. ccache holds none of them: it refuses every compile with -ivfsoverlay unless told
-- not to hash the overlay (measured: "Result: unsupported_compiler_option"). The plugin walks the
-- AST once, the way clang's own ASTPrinter walks it for one filter, and writes what clang would
-- have printed for each filter, byte for byte (measured on six filters from one umbrella of 81
-- frameworks: every JSON and text dump identical once the per-run node addresses are masked,
-- 2.5 s for the six against 13 s for their twelve parses).
--
-- A plugin is compiled against the headers of the clang that loads it. The lift's clang is built
-- by this repository's llvm recipe, which installs no headers, so an llvm-config of the same
-- major.minor release is looked for (CHARON_LLVM_CONFIG, the path, Homebrew's llvm), and the
-- plugin is compiled with its clang++ and without RTTI, which is how the lift's clang is built. It
-- is kept by the digest of what went into it. Whether it answers as clang does is not assumed:
-- lift.lua compares its first answer with clang's own and stops using it on any difference.
-- CHARON_LIFT_MULTIDUMP=0 turns it off.

local PLUGIN

local function home()
    return os.getenv("CHARON_HOME") or path.join(os.getenv("HOME"), ".charon")
end

local function release(text)
    return text and text:match("(%d+%.%d+)%.%d+")
end

local function configs()
    local found = {}
    local given = os.getenv("CHARON_LLVM_CONFIG")
    if given and given ~= "" then
        table.insert(found, given)
    end
    for _, folder in ipairs((os.getenv("PATH") or ""):split(path.envsep())) do
        table.insert(found, path.join(folder, "llvm-config"))
    end
    table.join2(found, {"/opt/homebrew/opt/llvm/bin/llvm-config", "/usr/local/opt/llvm/bin/llvm-config"})
    return found
end

-- The plugin for clang, built if it is not kept yet; nil when there is none to be had.
function plugin(clang)
    if PLUGIN ~= nil then
        return PLUGIN or nil
    end
    PLUGIN = false
    if os.getenv("CHARON_LIFT_MULTIDUMP") == "0" then
        return nil
    end
    local wanted = release(try { function () return os.iorunv(clang, {"--version"}) end })
    if not wanted then
        return nil
    end
    local config, version
    for _, candidate in ipairs(configs()) do
        if os.isexec(candidate) then
            local answer = try { function () return os.iorunv(candidate, {"--version"}) end }
            if release(answer) == wanted then
                config, version = candidate, answer:trim()
                break
            end
        end
    end
    if not config then
        return nil
    end
    local source = path.join(os.scriptdir(), "multidump", "multidump.cpp")
    local flags = os.iorunv(config, {"--cxxflags"}):trim():split("%s+")
    local compiler = path.join(os.iorunv(config, {"--bindir"}):trim(), "clang++")
    local key = hash.strhash128(table.concat({io.readfile(source), version, table.concat(flags, " "), clang,
                                              tostring(os.filesize(clang)), tostring(os.mtime(clang))}, "\n"))
    local dylib = path.join(home(), "cache", "multidump", key .. ".dylib")
    if not os.isfile(dylib) then
        try { function () os.mkdir(path.directory(dylib)) end }
        local temporary = dylib .. "." .. hash.strhash32(dylib .. os.mclock()) .. ".tmp"
        local built = try { function ()
            os.vrunv(compiler, table.join(flags, {"-fno-rtti", "-fPIC", "-shared", "-undefined", "dynamic_lookup", "-O2",
                                                  source, "-o", temporary}))
            return true
        end }
        if not built or not os.isfile(temporary) then
            os.tryrm(temporary)
            return nil
        end
        os.mv(temporary, dylib)
    end
    PLUGIN = dylib
    return dylib
end

-- Stops the plugin being used for the rest of this process.

-- The arguments that make a clang run with base (the parse, as a query would run it) answer every
-- filter of list into folder: <folder>/<n>.json and <folder>/<n>.txt for the n-th line of list.
function arguments(dylib, base, list, folder)
    return table.join(base, {"-Xclang", "-load", "-Xclang", dylib, "-Xclang", "-plugin", "-Xclang", "charon-multidump",
                             "-Xclang", "-plugin-arg-charon-multidump", "-Xclang", list,
                             "-Xclang", "-plugin-arg-charon-multidump", "-Xclang", folder})
end
