import("macho")
import("dyld")

LIBRARIES = {
    {name = "FoundationBackports", folder = "Foundation", frameworks = {"Foundation", "CoreFoundation"}},
    {name = "UIKitBackports", folder = "UIKit", frameworks = {"UIKit", "Foundation", "CoreGraphics", "QuartzCore"}, libraries = {"FoundationBackports"}}
}

INSTALL_FOLDER = "/usr/lib/charon/org.charon.apple-backports"

function libraries()
    return LIBRARIES
end

local function exported_symbols(file)
    local data = macho.read(file)
    local found = {}
    for _, image in ipairs(macho.images(data)) do
        if image.symtab then
            local symoff, nsyms, stroff = image.symtab[1], image.symtab[2], image.symtab[3]
            local entry = image.wide and 16 or 12
            for index = 0, nsyms - 1 do
                local strx, kind = string.unpack("<I4B", data, image.base + symoff + index * entry + 1)
                if kind & 0xE0 == 0 and kind & 0x10 == 0 and kind & 0x0E == 0x0E and kind & 0x01 ~= 0 then
                    local finish = data:find("\0", image.base + stroff + strx + 1, true)
                    found[data:sub(image.base + stroff + strx + 1, finish - 1)] = true
                end
            end
        end
    end
    return table.orderkeys(found)
end

local function compile(opt, source, object)
    local language = source:endswith(".c") and {} or {"-fobjc-arc"}
    os.vrunv("xcrun", table.join({"clang", "-target", opt.triple, "-isysroot", opt.sdkdir, "-Os", "-g0", "-fvisibility=hidden",
                                  "-Wall", "-Wno-unguarded-availability-new", "-Wno-unguarded-availability", "-c", source, "-o", object}, language))
end

local function sections_of(file)
    local names = {}
    for _, image in ipairs(macho.images(macho.read(file))) do
        for _, section in ipairs(image.sections) do
            names[section.segment .. "," .. section.name] = true
        end
    end
    return names
end

function sources(root, library)
    local found = table.join(os.files(path.join(root, library.folder, "*.m")), os.files(path.join(root, library.folder, "*.c")))
    table.sort(found)
    return found
end

function band(release_exports, objects)
    local kept, reexported = {}, {}
    for _, object in ipairs(objects) do
        local symbols = exported_symbols(object)
        local present = {}
        for _, symbol in ipairs(symbols) do
            if release_exports[symbol] then
                table.insert(present, symbol)
            end
        end
        if #present == 0 then
            table.insert(kept, object)
        elseif #present == #symbols then
            table.join2(reexported, symbols)
        else
            local absent = {}
            for _, symbol in ipairs(symbols) do
                if not release_exports[symbol] then
                    table.insert(absent, symbol)
                end
            end
            raise("%s defines %s, which the release already exports, together with %s, which it does not; an object carries API that arrived in one release, so split it",
                  path.filename(object), table.concat(present, " "), table.concat(absent, " "))
        end
    end
    return kept, reexported
end

local function link(opt, library, attach, release_exports)
    local objects = {}
    for _, source in ipairs(sources(opt.root, library)) do
        local object = path.join(opt.builddir, "objects", library.folder, path.basename(source) .. ".o")
        os.mkdir(path.directory(object))
        compile(opt, source, object)
        table.insert(objects, object)
    end
    local kept, reexported = band(release_exports, objects)
    local output = path.join(opt.outputdir, "lib" .. library.name .. ".dylib")
    os.mkdir(opt.outputdir)
    local arguments = {"clang", "-target", opt.triple, "-isysroot", opt.sdkdir, "-fuse-ld=" .. opt.ld, "-fobjc-arc", "-dynamiclib",
                       "-install_name", path.join(INSTALL_FOLDER, path.filename(output)),
                       "-Wl,-rename_section,__DATA,__objc_catlist,__DATA,__charon_catlist", "-o", output, attach}
    table.join2(arguments, kept)
    for _, other in ipairs(library.libraries or {}) do
        table.join2(arguments, {"-L" .. opt.outputdir, "-l" .. other})
    end
    for _, framework in ipairs(library.frameworks) do
        table.join2(arguments, {"-framework", framework})
    end
    if #reexported > 0 then
        local list = path.join(opt.builddir, library.name .. ".reexported")
        io.writefile(list, table.concat(reexported, "\n") .. "\n")
        table.insert(arguments, "-Wl,-reexported_symbols_list," .. list)
    end
    os.vrunv("xcrun", arguments)
    if sections_of(output)["__DATA,__objc_catlist"] then
        raise("%s kept __objc_catlist: the linker did not rename it, so the runtime would attach every backported method over the system's own", output)
    end
    return output
end

function build(opt)
    local release = dyld.load(opt.cache)
    if release.architecture ~= opt.architecture then
        raise("%s holds %s libraries, and the backports are built for %s", opt.cache, release.architecture, opt.architecture)
    end
    opt = table.join(opt, {triple = opt.architecture .. "-apple-ios" .. opt.deployment})
    local attach = path.join(opt.builddir, "objects", "attach.o")
    os.mkdir(path.directory(attach))
    compile(opt, path.join(opt.root, "attach.c"), attach)
    local built = {}
    for _, library in ipairs(LIBRARIES) do
        if not opt.libraries or table.contains(opt.libraries, library.name) then
            table.insert(built, link(opt, library, attach, release.exports))
        end
    end
    dyld.check(opt.cache, built)
    return built
end
