SYSTEM_STUB = [[--- !tapi-tbd
tbd-version: 4
targets: [ armv7-ios, arm64-ios ]
install-name: '/usr/lib/libSystem.B.dylib'
exports:
  - targets: [ armv7-ios, arm64-ios ]
    symbols: [ %s ]
...
]]

function system_stub(symbols, installed)
    local text = SYSTEM_STUB:format(symbols or "dyld_stub_binder")
    if installed then
        text = text:gsub("/usr/lib/libSystem.B.dylib", installed)
    end
    return text
end

function run(folder, program, argv)
    return os.iorunv(program, argv, {curdir = folder})
end

function link(folder, ld64, output, triple, source, extra)
    local linker = triple:startswith("armv7") and ld64 or "ld"
    run(folder, "xcrun", table.join({"clang", "-target", triple, "-Wno-incompatible-sysroot", "-fuse-ld=" .. linker,
                                     "-nostdlib", "-L.", "-lSystem"}, extra or {}, {"-o", output, source}))
    return path.join(folder, output)
end

function section_offset(folder, binary, segment, section)
    local listing = run(folder, "xcrun", {"otool", "-l", binary})
    for block in (listing .. "Section"):gmatch("(.-)Section") do
        if block:match("sectname%s+" .. section:gsub("_", "%%_") .. "%s") and block:match("segname%s+" .. segment:gsub("_", "%%_") .. "%s") then
            return tonumber(block:match("offset%s+(%d+)"))
        end
    end
    raise("%s has no %s,%s", binary, segment, section)
end

function slot(file, position)
    return string.unpack("<I4", io.readfile(file, {encoding = "binary"}), position + 1)
end

function edited(source, destination, position, value)
    local data = io.readfile(source, {encoding = "binary"})
    io.writefile(destination, data:sub(1, position) .. string.pack("<I4", value) .. data:sub(position + 5), {encoding = "binary"})
    return destination
end

function scratch()
    local folder = os.tmpfile() .. ".dir"
    os.mkdir(folder)
    return folder
end

function refusal(action)
    local errors
    try {
        action,
        catch {
            function (raised)
                errors = tostring(raised)
            end
        }
    }
    return errors
end
