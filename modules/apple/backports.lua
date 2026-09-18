import("macho")
import("dyld")
import("firmware")
import("signing")
import("objc")
import("core.base.json")

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

-- A backport holds more than the API it carries: Charon's own helpers, the
-- classes it invents for itself and the ivars of the classes it implements.
-- None of that is API - a release that already has a class exports its own
-- ivars, not these - so it is neither weighed against a release nor exported.
local function internal_symbol(name)
    if name:startswith("_OBJC_IVAR_$_") or name:find("$shim", 1, true) then
        return true
    end
    local bare = name:match("^_OBJC_%u*CLASS_%$_(.+)$") or name:match("^_(.+)$") or name
    return bare:startswith("charon_") or bare:startswith("Charon")
end

local function defined_symbols(file)
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

local function exported_symbols(file)
    local found = {}
    for _, symbol in ipairs(defined_symbols(file)) do
        if not internal_symbol(symbol) then
            table.insert(found, symbol)
        end
    end
    return found
end

local function clang(opt, arguments, objective_c)
    local given = {"-target", opt.triple, "-isysroot", opt.sdkdir}
    if objective_c then
        table.insert(given, "-fobjc-arc")
        if dyld.compare_versions(opt.deployment, "5.0") < 0 then
            table.join2(given, {"-Xclang", "-fobjc-runtime-has-weak"})
        end
    end
    table.join2(given, arguments)
    if opt.cc then
        return opt.cc, given
    end
    return "xcrun", table.join({"clang"}, given)
end

-- Only C is compiled hidden. The classes of a backport are the API it carries,
-- and the headers of the release declare a Foundation class without the
-- visibility UIKit gives its own, so -fvisibility=hidden makes clang hide every
-- Foundation class it implements: the library exports nothing, a port links its
-- classes as the weak imports that are NULL on the release, and the device says
-- only that the program failed. What the library must not export it hides at
-- the link, where a hidden symbol can still be named.
function compile(opt, source, object)
    local objective_c = not source:endswith(".c")
    local arguments = {"-Os", "-g0", "-Wall", "-Wno-unguarded-availability-new", "-Wno-unguarded-availability"}
    if not objective_c then
        table.insert(arguments, "-fvisibility=hidden")
    end
    os.vrunv(clang(opt, table.join(arguments, {"-c", source, "-o", object}), objective_c))
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

-- dyld learned to re-export a symbol of another library in iOS 4.2, and ld64
-- refuses -reexported_symbols_list for anything older ("targeted OS version
-- does not support -reexported_symbols_list"). A band for such a release still
-- drops what the release carries - that is the point of the band - it just
-- promises nothing in its place, and the port binds the release's own symbol,
-- which is there. libcxx does the same where it cannot re-export libcxxabi.
function reexports(deployment)
    return dyld.compare_versions(deployment, "4.2") >= 0
end

local function link(opt, library, attach, objects, releases, outputdir)
    local kept, reexported = band(releases[1].exports, objects)
    if not reexports(opt.deployment) then
        reexported = {}
    end
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
    local internal = {}
    for _, object in ipairs(kept) do
        for _, symbol in ipairs(defined_symbols(object)) do
            if internal_symbol(symbol) then
                table.insert(internal, symbol)
            end
        end
    end
    if #internal > 0 then
        local list = path.join(opt.builddir, library.name .. ".internal")
        io.writefile(list, table.concat(table.unique(internal), "\n") .. "\n")
        table.insert(arguments, "-Wl,-unexported_symbols_list," .. list)
    end
    os.vrunv("xcrun", arguments)
    if sections_of(output)["__DATA,__objc_catlist"] then
        raise("%s kept __objc_catlist: the linker did not rename it, so the runtime would attach every backported method over the system's own", output)
    end
    local held = {}
    for _, symbol in ipairs(defined_symbols(output)) do
        held[symbol] = true
    end
    local missing = {}
    for _, object in ipairs(kept) do
        for _, symbol in ipairs(exported_symbols(object)) do
            if not held[symbol] then
                table.insert(missing, symbol)
            end
        end
    end
    if #missing > 0 then
        table.sort(missing)
        raise("%s holds %d API it does not export, and a port that links against it takes the weak import of the release instead, which is NULL there: %s",
              output, #missing, table.concat(table.slice(missing, 1, math.min(8, #missing)), " ") .. (#missing > 8 and (" and %d more"):format(#missing - 8) or ""))
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

function surface(binaries, architecture)
    local found = {classes = {}, members = {}, symbols = {}}
    for _, binary in ipairs(binaries) do
        local ours = {}
        for _, symbol in ipairs(exported_symbols(binary)) do
            local class = symbol:match("^_OBJC_CLASS_%$_(.+)$")
            if class then
                ours[class] = true
                found.classes[class] = true
            elseif not symbol:startswith("_OBJC_METACLASS_$_") and not symbol:startswith("_OBJC_IVAR_$_") then
                found.symbols[symbol:sub(2)] = true
            end
        end
        local inventory = objc.binary_inventory(binary, architecture)
        for name, class in pairs(inventory and inventory.classes or {}) do
            if class.image and not name:startswith("Charon") then
                found.classes[name] = true
            end
            if not class.image and not ours[name] then
                for kind, sign in pairs({instance = "-", class = "+"}) do
                    for selector in pairs(class[kind]) do
                        local plain = selector:sub(2)
                        if not plain:startswith("charon_") and not plain:startswith(".cxx_") then
                            found.members[string.format("%s[%s %s]", sign, name, plain)] = true
                        end
                    end
                end
            end
        end
    end
    return found
end

local STATUSES = {implemented = true, inert = true, absent = true, ignored = true}

function registry(root)
    local listed, told, incomplete = {}, {}, {}
    local files = table.join(os.files(path.join(root, "registry", "*.json")), os.files(path.join(root, "registry", "*", "*.json")))
    table.sort(files)
    for _, file in ipairs(files) do
        local named = path.join(path.filename(path.directory(file)), path.filename(file))
        local held = json.decode(io.readfile(file))
        for _, entry in ipairs(held.entries or held) do
            if told[entry.api] then
                table.insert(incomplete, entry.api .. " is named by both " .. told[entry.api] .. " and " .. named)
            end
            told[entry.api] = named
            listed[entry.api] = entry
            if not STATUSES[entry.status] then
                table.insert(incomplete, entry.api .. " says " .. tostring(entry.status) .. ", which is not one of the four answers")
            elseif entry.status ~= "implemented" then
                if not entry.effect then
                    table.insert(incomplete, entry.api .. " is " .. entry.status .. " without an effect")
                elseif entry.status ~= "ignored" and not entry.reason then
                    table.insert(incomplete, entry.api .. " is " .. entry.status .. " without a reason")
                elseif entry.status == "ignored" and not entry.facts then
                    table.insert(incomplete, entry.api .. " is ignored without a file of facts")
                end
            end
        end
    end
    return listed, incomplete
end

local function spellings(api)
    local plain = api:gsub("%(%)$", "")
    local found = {[plain] = true}
    local class, member = plain:match("^([%u][%w_]*)%.(.+)$")
    if class then
        found[string.format("-[%s %s]", class, member)] = true
        found[string.format("+[%s %s]", class, member)] = true
    end
    local sign, owner, selector = plain:match("^([-+])%[([%w_]+) (.+)%]$")
    if sign then
        found[owner .. "." .. selector] = true
    end
    return found
end

local ORDER = {ignored = 1, absent = 2, inert = 3}

function advice(root, used)
    local listed = registry(root)
    local found = {}
    for api, entry in pairs(listed) do
        if ORDER[entry.status] then
            for spelling in pairs(spellings(api)) do
                local selector = spelling:match("^[-+]%[[%w_]+ (.+)%]$")
                if used[spelling] or (selector and used[selector]) then
                    found[api] = entry
                end
            end
        end
    end
    local named = table.orderkeys(found)
    table.sort(named, function (a, b)
        if ORDER[found[a].status] ~= ORDER[found[b].status] then
            return ORDER[found[a].status] < ORDER[found[b].status]
        end
        return a < b
    end)
    local advised = {}
    for _, api in ipairs(named) do
        table.insert(advised, {api = api, status = found[api].status, effect = found[api].effect, introduced = found[api].introduced})
    end
    return advised
end

function check_registry(root, found, complete, deployment, exports)
    local listed, incomplete = registry(root)
    local unlisted, undocumented = {}, {}
    local function known(name)
        for spelling in pairs(spellings(name)) do
            if listed[spelling] then
                return true
            end
        end
        return false
    end
    for _, carried in ipairs({found.classes, found.members, found.symbols}) do
        for name in pairs(carried) do
            if not known(name) then
                table.insert(unlisted, name)
            end
        end
    end
    local unbuilt = {}
    if complete ~= false then
        for name, entry in pairs(listed) do
            local built = false
            for spelling in pairs(spellings(name)) do
                built = built or found.classes[spelling] or found.members[spelling] or found.symbols[spelling] or false
            end
            local owner = name:match("^[-+]%[([%w_]+) ") or name:match("^([%u][%w_]*)%.")
            built = built or (owner and found.classes[owner]) or false
            local carried = deployment and entry.introduced and dyld.compare_versions(entry.introduced, deployment) <= 0
            carried = carried or (exports and exports["_" .. name:gsub("%(%)$", "")]) or false
            if entry.status == "implemented" and not built and not carried then
                table.insert(unbuilt, name)
            elseif entry.status == "implemented" and not entry.facts then
                table.insert(undocumented, name)
            end
        end
    end
    table.sort(unlisted)
    table.sort(unbuilt)
    if #unlisted > 0 or #unbuilt > 0 or #incomplete > 0 then
        local lines = {"the registry does not describe what the backports carry:"}
        for _, described in ipairs(incomplete) do
            table.insert(lines, "  " .. described)
        end
        if #unlisted > 0 then
            table.insert(lines, "  built, but no entry in registry/: " .. table.concat(unlisted, " "))
        end
        if #unbuilt > 0 then
            table.insert(lines, "  listed as implemented, but nothing of that name is built: " .. table.concat(unbuilt, " "))
        end
        raise(table.concat(lines, "\n"))
    end
    return #undocumented
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
    if #built == #LIBRARIES then
        local undocumented = check_registry(opt.root, surface(built, opt.architecture), opt.registry, opt.deployment, release.exports)
        if undocumented > 0 then
            cprint("${color.warning}note:${clear} %d of the registry's entries name no file of facts yet", undocumented)
        end
    end
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

function availability_names(symbols)
    local names = {}
    for _, symbol in ipairs(symbols) do
        names[symbol:match("^_OBJC_CLASS_%$_(.+)$") or symbol:match("^_OBJC_METACLASS_%$_(.+)$")
              or symbol:match("^_OBJC_IVAR_%$_(.-)%.") or symbol:sub(2)] = true
    end
    return names
end

local LISTED = {}

local function listed(root)
    LISTED[root] = LISTED[root] or registry(root)
    return LISTED[root]
end

local function introduced(opt, source, object)
    local names = availability_names(exported_symbols(object))
    local releases = {}
    for _, name in ipairs(table.orderkeys(names)) do
        local dump = os.iorunv(clang(opt, {"-fsyntax-only", "-w", "-Xclang", "-ast-dump", "-Xclang", "-ast-dump-filter", "-Xclang", name, source}, true))
        local version = introduced_version(dump, name)
        if not version then
            -- API that is Foundation's own and in no header of the SDK, which a
            -- backport still carries under Apple's name because an archive holds
            -- it: the registry is what says when it arrived.
            local entry = listed(opt.root)[name]
            version = entry and entry.status == "implemented" and entry.introduced or nil
        end
        if not version then
            raise("neither the SDK nor the registry says which iOS release %s arrived in, and %s defines it, so no band can hold it", name, path.filename(source))
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

local function staged_libraries(opt)
    local staged = {}
    for _, library in ipairs(LIBRARIES) do
        if not opt.libraries or table.contains(opt.libraries, library.name) then
            table.insert(staged, library)
        end
    end
    return staged
end

function stage_bands(opt)
    opt = table.join(opt, {triple = opt.architecture .. "-apple-ios" .. opt.deployment})
    local attach, objects, origins = compiled(opt)
    local points = {[opt.deployment] = true}
    for _, library in ipairs(staged_libraries(opt)) do
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
            for _, library in ipairs(staged_libraries(opt)) do
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
        for _, library in ipairs(staged_libraries(opt)) do
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
