import("macho")
import("dyld")
import("firmware")
import("signing")

LIBRARIES = {
    {name = "FoundationBackports", folder = "Foundation", frameworks = {"Foundation", "CoreFoundation"}},
    {name = "UIKitBackports", folder = "UIKit", frameworks = {"UIKit", "Foundation", "CoreGraphics", "QuartzCore"}, libraries = {"FoundationBackports"}},
    {name = "CoreLocationBackports", folder = "CoreLocation", frameworks = {"CoreLocation", "Foundation"}, libraries = {"FoundationBackports"}}
}

PACKAGE = "org.charon.apple-backports"
INSTALL_FOLDER = "/usr/lib/charon/" .. PACKAGE
COMPATIBLE = {armv7 = {"armv7", "armv7s"}, armv7s = {"armv7s"}, arm64 = {"arm64"}}

function libraries()
    return LIBRARIES
end

function package_name()
    return PACKAGE
end

function compatible(architecture)
    return COMPATIBLE[architecture] or {architecture}
end

function held_cache(architecture, release)
    for _, candidate in ipairs(compatible(architecture)) do
        local held = dyld.held_source(path.join(dyld.root(), release), candidate)
        if held then
            return held
        end
    end
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

local function compiled(opt)
    local attach = path.join(opt.builddir, "objects", "attach.o")
    os.mkdir(path.directory(attach))
    compile(opt, path.join(opt.root, "attach.c"), attach)
    local objects, origins = {}, {}
    for _, library in ipairs(LIBRARIES) do
        objects[library.name] = {}
        for _, source in ipairs(sources(opt.root, library)) do
            local object = path.join(opt.builddir, "objects", library.folder, path.basename(source) .. ".o")
            os.mkdir(path.directory(object))
            compile(opt, source, object)
            table.insert(objects[library.name], object)
            origins[object] = source
        end
    end
    return attach, objects, origins
end

local function exported_through(release, install, seen)
    local found = release.libraries[install]
    if not found or seen[install] then
        return {}
    end
    seen[install] = true
    local names = table.keys(found.exports)
    for _, other in ipairs(found.reexports or {}) do
        table.join2(names, exported_through(release, other, seen))
    end
    return names
end

local function provides(release, install, symbol, seen)
    local found = release.libraries[install]
    if not found or seen[install] then
        return false
    end
    seen[install] = true
    if found.exports[symbol] then
        return true
    end
    for _, other in ipairs(found.reexports or {}) do
        if provides(release, other, symbol, seen) then
            return true
        end
    end
    return false
end

function stubs(architecture, library, reexported, releases, folder)
    local preferred = {}
    for index, framework in ipairs(library.frameworks) do
        preferred[framework] = index
    end
    local chosen = {}
    for _, symbol in ipairs(reexported) do
        local candidates = {}
        for install in pairs(releases[1].libraries) do
            local everywhere = true
            for _, release in ipairs(releases) do
                everywhere = everywhere and provides(release, install, symbol, {})
            end
            if everywhere then
                table.insert(candidates, install)
            end
        end
        if #candidates == 0 then
            raise("no library exports %s in every release a band of %s is checked against", symbol, library.name)
        end
        table.sort(candidates, function (a, b)
            local left, right = preferred[path.basename(a)] or math.huge, preferred[path.basename(b)] or math.huge
            if left ~= right then
                return left < right
            end
            return a < b
        end)
        chosen[candidates[1]] = chosen[candidates[1]] or {}
        table.insert(chosen[candidates[1]], symbol)
    end
    local files = {}
    for _, install in ipairs(table.orderkeys(chosen)) do
        local symbols, classes = {}, {}
        for _, symbol in ipairs(exported_through(releases[1], install, {})) do
            local class = symbol:match("^_OBJC_CLASS_%$_(.+)$")
            if class then
                table.insert(classes, class)
            elseif not symbol:startswith("_OBJC_METACLASS_$_") then
                table.insert(symbols, symbol)
            end
        end
        table.sort(symbols)
        table.sort(classes)
        local target = architecture .. "-ios"
        local file = path.join(folder, path.basename(install) .. ".tbd")
        io.writefile(file, table.concat({"--- !tapi-tbd", "tbd-version: 4", "targets: [ " .. target .. " ]", "install-name: '" .. install .. "'", "exports:",
                                         "  - targets: [ " .. target .. " ]", "    symbols: [ " .. table.concat(symbols, ", ") .. " ]",
                                         "    objc-classes: [ " .. table.concat(classes, ", ") .. " ]", "..."}, "\n") .. "\n")
        table.insert(files, file)
    end
    return files
end

local function link(opt, library, attach, objects, releases, outputdir)
    local kept, reexported = band(releases[1].exports, objects)
    local output = path.join(outputdir, "lib" .. library.name .. ".dylib")
    os.mkdir(outputdir)
    local arguments = {"clang", "-target", opt.triple, "-isysroot", opt.sdkdir, "-fuse-ld=" .. opt.ld, "-fobjc-arc", "-dynamiclib",
                       "-install_name", path.join(INSTALL_FOLDER, path.filename(output)),
                       "-Wl,-rename_section,__DATA,__objc_catlist,__DATA,__charon_catlist", "-o", output, attach}
    table.join2(arguments, kept)
    if #reexported > 0 then
        local folder = path.join(opt.builddir, "stubs", path.filename(outputdir), library.name)
        os.tryrm(folder)
        os.mkdir(folder)
        table.join2(arguments, stubs(opt.architecture, library, reexported, releases, folder))
    end
    for _, other in ipairs(library.libraries or {}) do
        table.join2(arguments, {"-L" .. outputdir, "-l" .. other})
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

local function loaded(cache, architecture)
    local release = dyld.load(cache)
    if not table.contains(compatible(architecture), release.architecture) then
        raise("%s holds %s libraries, which an %s build does not run on", cache, release.architecture, architecture)
    end
    return release
end

function build(opt)
    local release = loaded(opt.cache, opt.architecture)
    opt = table.join(opt, {triple = opt.architecture .. "-apple-ios" .. opt.deployment})
    local attach, objects = compiled(opt)
    local built = {}
    for _, library in ipairs(LIBRARIES) do
        if not opt.libraries or table.contains(opt.libraries, library.name) then
            table.insert(built, link(opt, library, attach, objects[library.name], {release}, opt.outputdir))
        end
    end
    dyld.check(opt.cache, built)
    return built
end

function introduced_version(dump, name)
    local found, current
    for line in dump:gmatch("[^\n]+") do
        local dumping = line:match("^Dumping (.-):$")
        if dumping then
            current = dumping
        elseif current == name then
            local version = line:match("^[|`]%-AvailabilityAttr.- ios (%d+[%.%d]*) ")
            if version and (not found or dyld.compare_versions(version, found) < 0) then
                found = version
            end
        end
    end
    return found
end

local function introduced(opt, source, object)
    local names = {}
    for _, symbol in ipairs(exported_symbols(object)) do
        names[symbol:match("^_OBJC_CLASS_%$_(.+)$") or symbol:match("^_OBJC_METACLASS_%$_(.+)$") or symbol:sub(2)] = true
    end
    local releases = {}
    for _, name in ipairs(table.orderkeys(names)) do
        local dump = os.iorunv("xcrun", {"clang", "-target", opt.triple, "-isysroot", opt.sdkdir, "-fobjc-arc", "-fsyntax-only", "-w",
                                         "-Xclang", "-ast-dump", "-Xclang", "-ast-dump-filter", "-Xclang", name, source})
        local version = introduced_version(dump, name)
        if not version then
            raise("the SDK declares %s, which %s defines, without an iOS release it arrived in, so no band can hold it", name, path.filename(source))
        end
        releases[version] = releases[version] or {}
        table.insert(releases[version], name)
    end
    local found = table.orderkeys(releases)
    if #found > 1 then
        local described = {}
        for _, version in ipairs(found) do
            table.insert(described, string.format("%s from iOS %s", table.concat(releases[version], " "), version))
        end
        raise("%s defines %s; an object carries API that arrived in one release, so split it", path.filename(source), table.concat(described, " and "))
    end
    return found[1]
end

function band_ranges(points, listed)
    local ranges = {}
    for index, point in ipairs(points) do
        local following = points[index + 1]
        local first, last
        for _, version in ipairs(listed) do
            if dyld.compare_versions(version, point) >= 0 and (not following or dyld.compare_versions(version, following) < 0) then
                first = first or version
                last = version
            end
        end
        if not first and index == 1 then
            raise("no firmware in the catalog runs iOS %s or later%s, so its API has no band", point, following and (" and before " .. following) or "")
        end
        if first then
            table.insert(ranges, {point = point, first = first, last = last})
        end
    end
    return ranges
end

local function release_cache(opt, architectures, release)
    local held = held_cache(opt.architecture, release)
    if held then
        return held
    end
    local cache, found = firmware.ensure(architectures[release], release, {tool = opt.tool})
    if found ~= release then
        raise("the band of iOS %s is checked against that release, and the %s firmware nearest to it is %s", release, architectures[release], tostring(found))
    end
    return cache
end

function stage_bands(opt)
    opt = table.join(opt, {triple = opt.architecture .. "-apple-ios" .. opt.deployment})
    local attach, objects, origins = compiled(opt)
    local points = {[opt.deployment] = true}
    for _, library in ipairs(LIBRARIES) do
        for _, object in ipairs(objects[library.name]) do
            if #exported_symbols(object) > 0 then
                local version = introduced(opt, origins[object], object)
                if dyld.compare_versions(version, opt.deployment) > 0 then
                    points[version] = true
                end
            end
        end
    end
    points = table.orderkeys(points)
    table.sort(points, function (a, b) return dyld.compare_versions(a, b) < 0 end)
    local architectures = {}
    for _, architecture in ipairs(compatible(opt.architecture)) do
        for _, version in ipairs(firmware.versions(architecture)) do
            architectures[version] = architectures[version] or architecture
        end
    end
    local listed = table.orderkeys(architectures)
    table.sort(listed, function (a, b) return dyld.compare_versions(a, b) < 0 end)
    local ranges = band_ranges(points, listed)
    local home = path.join(opt.stage, INSTALL_FOLDER)
    local lines = {}
    for _, range in ipairs(ranges) do
        local releases, signatures = {}, {}
        for _, release in ipairs(table.unique({range.first, range.last})) do
            local found = loaded(release_cache(opt, architectures, release), opt.architecture)
            table.insert(releases, found)
            local reexported = {}
            for _, library in ipairs(LIBRARIES) do
                local _, symbols = band(found.exports, objects[library.name])
                table.join2(reexported, symbols)
            end
            signatures[release] = table.concat(reexported, " ")
        end
        if signatures[range.first] ~= signatures[range.last] then
            raise("iOS %s and %s export different backported symbols (%s, and %s), although the SDK says nothing the backports define arrived between them",
                  range.first, range.last, signatures[range.first], signatures[range.last])
        end
        local built = {}
        for _, library in ipairs(LIBRARIES) do
            table.insert(built, link(opt, library, attach, objects[library.name], releases, path.join(home, "bands", range.first)))
        end
        for _, release in ipairs(table.unique({range.first, range.last})) do
            dyld.check(release_cache(opt, architectures, release), built)
        end
        for index = #built, 1, -1 do
            os.vrunv("xcrun", {"strip", "-x", built[index]})
            signing.sign(opt.ldid, built[index])
        end
        table.insert(lines, range.first .. " " .. range.last)
    end
    io.writefile(path.join(home, "bands", "ranges"), table.concat(lines, "\n") .. "\n")
    return ranges
end

POSTINST = [[
#!/bin/sh
set -e
root="${DPKG_ROOT:-}"
home="$root@HOME@"
version=$(sed -n '/<key>ProductVersion<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$root/System/Library/CoreServices/SystemVersion.plist" 2>/dev/null || true)
if [ -z "$version" ]; then
    echo "@PACKAGE@ cannot read ProductVersion from $root/System/Library/CoreServices/SystemVersion.plist, so it cannot pick the libraries for this iOS" >&2
    exit 1
fi
older() {
    left=$1 right=$2
    while [ -n "$left$right" ]; do
        a=${left%%.*} b=${right%%.*}
        if [ "$left" = "$a" ]; then left=; else left=${left#*.}; fi
        if [ "$right" = "$b" ]; then right=; else right=${right#*.}; fi
        if [ "${a:-0}" -lt "${b:-0}" ]; then return 0; fi
        if [ "${a:-0}" -gt "${b:-0}" ]; then return 1; fi
    done
    return 1
}
band=
while read -r first last; do
    if ! older "$version" "$first" && ! older "$last" "$version"; then
        band=$first
    fi
done < "$home/bands/ranges"
if [ -z "$band" ]; then
    echo "@PACKAGE@ holds no libraries built and checked for iOS $version; it holds them for iOS $(sed 's/ / to /' "$home/bands/ranges" | tr '\n' ',' | sed 's/,$//;s/,/, /g')" >&2
    exit 1
fi
for library in "$home/bands/$band"/*.dylib; do
    ln -sf "bands/$band/${library##*/}" "$home/${library##*/}"
done
]]

PRERM = [[
#!/bin/sh
set -e
if [ "$1" = remove ]; then
    for library in "${DPKG_ROOT:-}@HOME@"/*.dylib; do
        if [ -L "$library" ]; then
            rm -f "$library"
        fi
    done
fi
]]

function write_scripts(folder)
    os.tryrm(folder)
    os.mkdir(folder)
    for name, text in pairs({postinst = POSTINST, prerm = PRERM}) do
        io.writefile(path.join(folder, name), (text:gsub("@HOME@", INSTALL_FOLDER):gsub("@PACKAGE@", PACKAGE)))
    end
end

function write_deb(opt)
    local debian = import("debian", {rootdir = path.join(os.scriptdir(), ".."), anonymous = true})
    local stage = path.join(opt.builddir, "stage")
    os.tryrm(stage)
    local ranges = stage_bands(table.join(opt, {stage = stage}))
    local covered = {}
    for _, range in ipairs(ranges) do
        table.insert(covered, range.first == range.last and range.first or (range.first .. " to " .. range.last))
    end
    local control = path.join(opt.builddir, "control")
    io.writefile(control, table.concat({
        "Package: " .. PACKAGE,
        "Name: Apple API backports",
        "Architecture: iphoneos-arm",
        "Section: System",
        "Description: Objective-C classes and methods of later iOS releases for the releases that lack them, as the libraries ports built with Charon load from " .. INSTALL_FOLDER .. "; libraries built and checked for iOS " .. table.concat(covered, ", ")
    }, "\n") .. "\n")
    local scripts = path.join(opt.builddir, "scripts")
    write_scripts(scripts)
    return debian.write({control = control, version = opt.version, root = stage, scripts = scripts, outputdir = opt.outputdir}), ranges
end
