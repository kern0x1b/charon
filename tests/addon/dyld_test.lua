import("core.base.json")
import("fixtures")

local function cache(file, architecture, exported, installed)
    installed = installed or "/usr/lib/libSystem.B.dylib"
    local strings = "\0" .. exported .. "\0"
    local image, header, segment = 0x100, 28, 56
    local symbols = image + header + segment + 24
    local symbol_table = symbols + 12
    local name = symbol_table + #strings
    local size = name + #installed + 1
    local data = {}
    local function put(at, bytes)
        table.insert(data, {at, bytes})
    end
    put(0, ("dyld_v1" .. string.rep(" ", 8 - #architecture) .. architecture .. "\0"))
    put(16, string.pack("<I4I4I4I4", 0x40, 1, 0x60, 1))
    put(0x40, string.pack("<I8I8I8I4I4", 0, size, 0, 5, 5))
    put(0x60, string.pack("<I8I8I8I4", image, 0, 0, name))
    put(image, string.pack("<I4i4i4I4I4I4I4", 0xFEEDFACE, 12, 9, 6, 2, segment + 24, 0))
    put(image + header, string.pack("<I4I4c16I4I4I4I4i4i4I4I4", 0x1, segment, "__LINKEDIT", 0, size, 0, size, 1, 1, 0, 0))
    put(image + header + segment, string.pack("<I4I4I4I4I4I4", 0x2, 24, symbols, 1, symbol_table, #strings))
    put(symbols, string.pack("<I4BBi2I4", 1, 0x0F, 1, 0, 0))
    put(symbol_table, strings)
    put(name, installed .. "\0")
    local bytes = string.rep("\0", size)
    for _, piece in ipairs(data) do
        bytes = bytes:sub(1, piece[1]) .. piece[2] .. bytes:sub(piece[1] + #piece[2] + 1)
    end
    io.writefile(file, bytes, {encoding = "binary"})
    return file
end

local function dylib(folder, ld64, name, triple, imported, extra)
    io.writefile(path.join(folder, name .. ".c"), string.format("extern int %s(void);\nint use(void) { return %s(); }\n", imported:sub(2), imported:sub(2)))
    return fixtures.link(folder, ld64, name .. ".dylib", triple, name .. ".c", table.join({"-dynamiclib"}, extra or {}))
end

function failures(opt)
    local dyld = import("apple.dyld", {rootdir = opt.modules, anonymous = true})
    local found = {}
    local folder = fixtures.scratch()
    local armv7 = cache(path.join(folder, "dyld_shared_cache_armv7"), "armv7", "_exported")
    io.writefile(path.join(folder, "libSystem.tbd"), fixtures.system_stub("dyld_stub_binder, _exported, _nested, ___divti3"))
    io.writefile(path.join(folder, "libother.tbd"), fixtures.system_stub("_elsewhere", "/usr/lib/libother.dylib"))
    io.writefile(path.join(folder, "libgone.tbd"), fixtures.system_stub("_gone", "/usr/lib/libgone.dylib"))
    local clean = dylib(folder, opt.ld64, "clean-armv7", "armv7-apple-ios6.0", "_exported")
    local late = dylib(folder, opt.ld64, "late-armv7", "armv7-apple-ios6.0", "___divti3")
    local wide = dylib(folder, opt.ld64, "wide-arm64", "arm64-apple-ios7.0", "___divti3")
    local loads = dylib(folder, opt.ld64, "loads-armv7", "armv7-apple-ios6.0", "_exported", {"-lgone"})
    local cases = {
        {"an armv7 slice importing only what the cache exports, beside an arm64 slice importing what it does not", {clean, wide}, nil},
        {"an armv7 slice importing what the cache does not export", {late, wide}, "___divti3"},
        {"a binary with no slice an armv7 device loads", {wide}, "no slice a armv7 device loads"},
        {"a binary loading a library neither the device nor the build provides", {loads}, "loads /usr/lib/libgone"}
    }
    for index, case in ipairs(cases) do
        local merged = path.join(folder, "merged" .. index .. ".dylib")
        fixtures.run(folder, "xcrun", table.join({"lipo", "-create"}, case[2], {"-output", merged}))
        local missing = dyld.missing_imports(armv7, {merged})
        local described = {}
        for _, entry in ipairs(missing) do
            table.insert(described, entry[2])
        end
        local text = table.concat(described, "; ")
        if not case[3] and #missing > 0 then
            table.insert(found, case[1] .. " must pass: " .. text)
        elseif case[3] and not text:find(case[3], 1, true) then
            table.insert(found, case[1] .. " must be refused naming " .. case[3] .. ": " .. text)
        end
    end
    local libraries = path.join(folder, "home", "dyld", "2.2.1", "libraries_armv7")
    local device = path.join(libraries, "usr", "lib")
    os.mkdir(path.join(device, "system"))
    io.writefile(path.join(folder, "nested.c"), "int nested(void) { return 0; }\n")
    fixtures.link(folder, opt.ld64, path.join(device, "system", "libnested.dylib"), "armv7-apple-ios6.0", "nested.c",
                  {"-dynamiclib", "-install_name", "/usr/lib/system/libnested.dylib"})
    io.writefile(path.join(folder, "other.c"), "int other(void) { return 0; }\n")
    fixtures.link(folder, opt.ld64, path.join(device, "libother.dylib"), "armv7-apple-ios6.0", "other.c",
                  {"-dynamiclib", "-install_name", "/usr/lib/libother.dylib"})
    io.writefile(path.join(folder, "system.c"), "int exported(void) { return 0; }\nint elsewhere(void) { return 0; }\n")
    fixtures.link(folder, opt.ld64, path.join(device, "libSystem.B.dylib"), "armv7-apple-ios6.0", "system.c",
                  {"-dynamiclib", "-install_name", "/usr/lib/libSystem.B.dylib", "-Wl,-reexport_library," .. path.join(device, "system", "libnested.dylib")})
    local nested = dylib(folder, opt.ld64, "nested-armv7", "armv7-apple-ios6.0", "_nested")
    local bound = dylib(folder, opt.ld64, "bound-armv7", "armv7-apple-ios6.0", "_elsewhere", {"-lother"})
    local firmware = import("apple.firmware", {rootdir = opt.modules, anonymous = true})
    local function release(version, build)
        return {version = version, build = build, url = "https://example.invalid/" .. build .. ".ipsw", size = 1}
    end
    json.savefile(path.join(folder, "home", "firmware", "catalog.json"), {sources = firmware.sources(), devices = {
        {identifier = "iPhone3,1", platform = "s5l8930x", firmwares = {release("2.2.1", "5H11"), release("4.3.5", "8L1"), release("4.1", "8B117")}},
        {identifier = "iPhone5,1", platform = "s5l8950x", firmwares = {release("6.0", "10A405")}}
    }})
    local home = os.getenv("CHARON_HOME")
    os.setenv("CHARON_HOME", path.join(folder, "home"))
    local held = firmware.source("armv7", "2.0")
    local absent, absent_release = firmware.source("armv7", "4.0")
    local later = firmware.release_for("armv7s", "5.0")
    os.setenv("CHARON_HOME", home or "")
    if held ~= libraries then
        table.insert(found, "a 2.0 port must be checked against the libraries of 2.2.1, the earliest release not older than it, not " .. tostring(held))
    end
    if absent_release ~= "4.1" or not absent:endswith(path.join("4.1", "dyld_shared_cache_armv7")) then
        table.insert(found, "a 4.0 port must be checked against 4.1, the earliest armv7 release not older than 4.0, and told where its cache goes, not " .. absent)
    end
    if later ~= "6.0" then
        table.insert(found, "an armv7s port for 5.0 must be checked against 6.0, the first release on armv7s, not " .. tostring(later))
    end
    if #dyld.missing_imports(libraries, {clean}) > 0 then
        table.insert(found, "an import a device library exports must pass against the libraries folder")
    end
    local text = ""
    for _, entry in ipairs(dyld.missing_imports(libraries, {late})) do
        text = text .. entry[2]
    end
    if not text:find("___divti3", 1, true) then
        table.insert(found, "an import no device library exports must be refused against the libraries folder: " .. text)
    end
    local reexported = dyld.missing_imports(libraries, {nested})
    if #reexported > 0 then
        table.insert(found, "an import a library re-exports from another must pass: " .. reexported[1][2])
    end
    text = ""
    for _, entry in ipairs(dyld.missing_imports(libraries, {bound})) do
        text = text .. entry[2]
    end
    if not text:find("_elsewhere (bound to /usr/lib/libother.dylib, which only another library exports", 1, true) then
        table.insert(found, "an import bound to a library that does not export it must be refused even when another library does: " .. text)
    end
    local errors = fixtures.refusal(function () dyld.check(path.join(folder, "absent"), {clean}) end)
    if not errors or not errors:find("no shared cache", 1, true) then
        table.insert(found, "a check with no cache to read must refuse rather than pass")
    end
    os.tryrm(folder)
    return found
end
