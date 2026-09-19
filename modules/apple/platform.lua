import("core.base.option")
import("core.project.project")
import("macho")
import("compat")
import("dyld")
import("firmware")
import("objc")
import("signing")
import("bundle")
import("backports")

function waivers(target)
    local waived = {}
    for _, name in ipairs(macho.WAIVABLE) do
        waived[name] = target:values("charon.waive." .. name)
    end
    return waived
end

function deployment(target)
    local found = target:toolchain("apple-ios")
    found:load()
    return found:config("deployment")
end

-- xmake hands a target the packages it adds under the name a require carries,
-- which is its alias, or its own name when it has none: a require named after
-- the repository it comes from reaches no target without one. A target that
-- adds a package and never receives it links against the frameworks of the
-- release alone, and the program it builds fails on the device saying nothing.
function verify_packages(target)
    local _, extra = project.requires_str()
    for _, required in ipairs(table.wrap(target:get("packages"))) do
        local wanted = required:split("%s+")[1]
        local at = wanted:lastof("@", true)
        local name = wanted:sub(at and at + 1 or 1)
        local declared = (extra or {})[required] or {}
        if not target:pkg(name) and project.required_package(required) and not declared.optional then
            raise("target(%s) adds package %s, and nothing of it reached the target%s", target:name(), required,
                  at and string.format("; a require named after its repository reaches one only under an alias: add_requires(\"%s\", {alias = \"%s\"})", wanted, name)
                     or ", so this configuration holds no install of it")
        end
    end
end

function verify_inputs(target)
    local wanted = macho.encoded_version(deployment(target))
    local problems, objects, members = {}, 0, 0
    local function inspect(file, owner)
        for _, recorded in ipairs(macho.recorded_minimums(file, target:arch())) do
            if recorded.member then
                members = members + 1
            else
                objects = objects + 1
            end
            if recorded.minimum ~= wanted then
                local label = (owner and (owner .. "/") or "") .. path.filename(file) .. (recorded.member and ("(" .. recorded.member .. ")") or "")
                if not recorded.minimum then
                    table.insert(problems, string.format("%s records no minimum release, so nothing says it was built for %s", label, deployment(target)))
                elseif recorded.minimum > wanted then
                    table.insert(problems, string.format("%s was built for iOS %s, newer than the %s this links for", label, macho.version_text(recorded.minimum), deployment(target)))
                else
                    table.insert(problems, string.format("%s was built for iOS %s instead of %s, which means it was compiled without the target's flags", label, macho.version_text(recorded.minimum), deployment(target)))
                end
            end
        end
    end
    for _, file in ipairs(target:objectfiles()) do
        if os.isfile(file) then
            inspect(file)
        end
    end
    for _, package in ipairs(target:orderpkgs()) do
        local reason = target:values("charon.waive.input-minimum." .. package:name())
        if reason then
            wprint("%s: input-minimum not checked for %s: %s", target:name(), package:name(), reason)
        else
            for _, file in ipairs(table.wrap(package:get("libfiles"))) do
                if file:endswith(".a") and os.isfile(file) then
                    inspect(file, package:name())
                end
            end
        end
    end
    if #problems > 0 then
        local shown = table.concat(table.slice(problems, 1, 5), "; ") .. (#problems > 5 and string.format("; and %d more", #problems - 5) or "")
        raise("a link input of %s was not built for this target: %s", target:name(), shown)
    end
    vprint("%s: %d objects and %d archive members record iOS %s", target:name(), objects, members, deployment(target))
end

-- A package checks what it installs: every image is for the architecture and the release it was built for. The sources of
-- a package are one directory for every architecture, so a build tree, or an object, that another configuration left
-- behind would otherwise reach a port as a library it cannot use. Nothing downstream would say so either: a port's link
-- checks its own objects and the static archives of its packages, not the libraries a package installs.
function verify_installed(package)
    local chosen = assert(package:toolchains(), package:name() .. " is built for apple-ios without the apple-ios toolchain")[1]
    chosen:load()
    local wanted = macho.encoded_version(chosen:config("deployment"))
    local problems, checked = {}, 0
    for _, file in ipairs(os.files(path.join(package:installdir(), "**"))) do
        if macho.is_macho(file) or file:endswith(".a") then
            local recorded = macho.recorded_minimums(file, package:arch())
            if #recorded == 0 then
                table.insert(problems, string.format("%s holds nothing for %s", path.filename(file), package:arch()))
            end
            for _, entry in ipairs(recorded) do
                checked = checked + 1
                if entry.minimum ~= wanted then
                    table.insert(problems, string.format("%s%s records iOS %s, not the %s this package is built for",
                                 path.filename(file), entry.member and ("(" .. entry.member .. ")") or "",
                                 entry.minimum and macho.version_text(entry.minimum) or "nothing", chosen:config("deployment")))
                end
            end
        end
    end
    if #problems > 0 then
        local shown = table.concat(table.slice(problems, 1, 5), "; ") .. (#problems > 5 and string.format("; and %d more", #problems - 5) or "")
        raise("%s installed what it did not build for %s iOS %s: %s", package:name(), package:arch(), chosen:config("deployment"), shown)
    end
    vprint("%s: %d images record %s iOS %s", package:name(), checked, package:arch(), chosen:config("deployment"))
end

function verify_minimum(target, binary)
    local wanted = macho.encoded_version(deployment(target))
    for _, image in ipairs(macho.images(macho.read(binary))) do
        if image.architecture == target:arch() and image.minimum ~= wanted then
            raise("%s records iOS %s, and this target builds for %s; the linker raised it, which it does when a startup object such as crt1.3.1.o is missing", binary, macho.version_text(image.minimum), deployment(target))
        end
    end
end

function imports_source(target, architecture)
    local tool = path.join(target:pkg("firmware-tools"):installdir(), "bin", "charon-firmware")
    return (firmware.ensure(architecture or target:arch(), deployment(target), {tool = tool}))
end

function backport_libraries(target)
    local package = target:pkg("apple-backports")
    local libraries = {}
    for _, folder in ipairs(package and table.wrap(package:get("linkdirs")) or {}) do
        for _, library in ipairs(backports.libraries()) do
            local file = path.join(folder, "lib" .. library.name .. ".dylib")
            if os.isfile(file) then
                table.insert(libraries, file)
            end
        end
    end
    if package and #libraries == 0 then
        raise("target(%s) uses apple-backports, and its link folders %s hold none of its libraries", target:name(), table.concat(table.wrap(package:get("linkdirs")), " "))
    end
    return libraries
end

-- The packages of the runtime a program shares rather than carries: the ones charon@swift-runtime and charon@libcxx wrote
-- for their builds, and the libraries in them under the names the program will find them by.
local SHARED = {"swift-runtime", "libcxx"}

function shared_runtime(target)
    local found = {packages = {}, identities = {}, libraries = {}}
    for _, alias in ipairs(SHARED) do
        local package = target:pkg(alias)
        local name = package and table.wrap((package:envs() or {}).CHARON_SHARED_PACKAGE)[1]
        if name then
            local folder = "/usr/lib/charon/" .. name
            local debs = os.files(path.join(package:installdir(), "share", name .. "_*.deb"))
            if #debs ~= 1 then
                raise("target(%s) shares %s, whose install holds %d packages of that name instead of one", target:name(), name, #debs)
            end
            for _, file in ipairs(os.files(path.join(package:installdir(), "share", "root", folder, "*.dylib"))) do
                found.identities[path.filename(file)] = folder .. "/" .. path.filename(file)
                table.insert(found.libraries, file)
            end
            table.insert(found.packages, {deb = debs[1], name = name, relation = "=", version = path.filename(debs[1]):match("^[^_]+_([^_]+)_"),
                                          needs = table.wrap((package:envs() or {}).CHARON_SHARED_NEEDS)[1]})
        end
    end
    if #found.packages == 0 then
        return nil
    end
    -- One copy of libc++abi to a process: the runtime and the program name the same build of it.
    local names = {}
    for _, shared in ipairs(found.packages) do
        names[shared.name] = true
    end
    for _, shared in ipairs(found.packages) do
        if shared.needs and not names[shared.needs] then
            raise("target(%s) shares %s, which is linked against %s, and the target itself takes the C++ runtime from a different build; require charon@libcxx with the same configs as the runtime does (packaged)", target:name(), shared.name, shared.needs)
        end
    end
    return found
end

-- What the release's own libraries do not hold and the program finds installed by a package it depends on.
function provided_libraries(target)
    local shared = shared_runtime(target)
    return table.join(backport_libraries(target), shared and shared.libraries or {})
end

function backport_package(target)
    local libraries = backport_libraries(target)
    if #libraries == 0 then
        return nil
    end
    local debs = os.files(path.join(path.directory(path.directory(libraries[1])), "share", backports.package_name() .. "_*.deb"))
    if #debs ~= 1 then
        raise("target(%s) uses apple-backports, whose install holds %d %s packages instead of one", target:name(), #debs, backports.package_name())
    end
    return {deb = debs[1], name = backports.package_name(), relation = ">=", version = path.filename(debs[1]):match("^[^_]+_([^_]+)_")}
end

function report_selectors(source, binaries, architecture, folder, provided)
    local found = objc.absent_selectors(source, table.join(binaries, provided or {}), architecture)
    for _, binary in ipairs(binaries) do
        local missing = found[binary]
        if missing then
            local named = folder and path.relative(binary, folder) or binary
            local limit = option.get("verbose") and #missing or 12
            local shown = table.concat(table.slice(missing, 1, math.min(limit, #missing)), " ") .. (#missing > limit and string.format(" and %d more, all of them under xmake -v", #missing - limit) or "")
            wprint("%s sends %d selector%s no class of the %s release it is checked against implements, which must run only behind respondsToSelector: or a version check: %s",
                   named, #missing, #missing == 1 and "" or "s", architecture, shown)
        end
    end
end

function report_registry(target, binary)
    local libraries = backport_libraries(target)
    if #libraries == 0 then
        return
    end
    local root = path.join(path.directory(path.directory(libraries[1])), "share")
    if not os.isdir(path.join(root, "registry")) then
        return
    end
    local used = macho.imported_symbols(binary, target:arch())
    for selector in pairs((objc.binary_selectors(binary, target:arch()) or {used = {}}).used) do
        used[selector:sub(2)] = true
    end
    local advised = backports.advice(root, used)
    if #advised == 0 then
        return
    end
    local told = {}
    for _, entry in ipairs(advised) do
        table.insert(told, string.format("  %s (iOS %s) is %s: %s", entry.api, entry.introduced or "?", entry.status, entry.effect or "?"))
    end
    wprint("%s calls %d API the backports do not carry as the release that added them does:\n%s",
           path.filename(binary), #advised, table.concat(told, "\n"))
end

function verify(target, binary, opt)
    opt = opt or {}
    verify_minimum(target, binary)
    macho.verify(binary, {waived = waivers(target), arrived = compat.arrived("iOS"), process_wide = compat.process_wide(),
                          stripped = opt.stripped})
    if opt.imports ~= false then
        local source = imports_source(target)
        local provided = provided_libraries(target)
        dyld.check(source, table.join({binary}, provided))
        report_selectors(source, {binary}, target:arch(), nil, provided)
        report_registry(target, binary)
    end
end

function carried_folder(target)
    local control = target:values("charon.control")
    if not control then
        raise("target(%s) carries %s, and a tweak or daemon keeps what it carries in /usr/lib/charon/<Package>; name the package with set_values(\"charon.control\", ...)", target:name(), table.concat(table.wrap(target:values("charon.libraries")), ", "))
    end
    local debian = import("debian", {rootdir = path.join(os.scriptdir(), ".."), anonymous = true})
    local package = debian.control_fields(path.absolute(control, target:scriptdir())).Package
    if not package or package == "" then
        raise("%s has no Package field to name the folder target(%s) carries its libraries in", control, target:name())
    end
    return "/usr/lib/charon/" .. package
end

function place_carried(target, root, binary)
    local offered = {}
    for _, library in ipairs(bundle.carried_libraries(target, "charon.libraries")) do
        offered[library.name] = library
    end
    local libraries, pending = {}, {binary}
    while #pending > 0 do
        for _, reference in ipairs(macho.images(macho.read(table.remove(pending)))[1].libraries) do
            local library = offered[path.filename(reference)]
            if library and not library.taken then
                library.taken = true
                table.insert(libraries, library)
                table.insert(pending, library.source)
            end
        end
    end
    local shared = shared_runtime(target)
    if #libraries == 0 then
        if shared then
            bundle.retarget({binary}, {}, {provided = shared.identities})
        end
        return {binary}
    end
    local folder = carried_folder(target)
    local identities, binaries = {}, {binary}
    for _, library in ipairs(libraries) do
        local destination = path.join(root, folder, library.name)
        os.mkdir(path.directory(destination))
        os.vcp(library.source, destination)
        identities[destination] = folder .. "/" .. library.name
        table.insert(binaries, destination)
    end
    bundle.retarget(binaries, identities, {home = folder .. "/", provided = shared and shared.identities})
    return binaries
end

function verify_placed(target, installed)
    if #table.wrap(target:values("charon.libraries")) == 0 and not shared_runtime(target) then
        return verify(target, target:targetfile())
    end
    local root = path.join(target:targetdir(), ".charon", "placed", target:name())
    os.tryrm(root)
    local binary = path.join(root, installed)
    os.mkdir(path.directory(binary))
    os.vcp(target:targetfile(), binary)
    local binaries = place_carried(target, root, binary)
    for _, placed in ipairs(binaries) do
        verify(target, placed, {imports = false})
    end
    local source = imports_source(target)
    local provided = provided_libraries(target)
    dyld.check(source, table.join(binaries, provided), root)
    report_selectors(source, binaries, target:arch(), root, provided)
end

function install_placed(target, installed)
    local binary = path.join(target:installdir(), installed)
    os.mkdir(path.directory(binary))
    os.vcp(target:targetfile(), binary)
    local binaries = place_carried(target, target:installdir(), binary)
    for index = #binaries, 1, -1 do
        finish(target, binaries[index])
    end
end

function ldid(target)
    return path.join(target:pkg("ldid"):installdir(), "bin", "ldid")
end

function strip(target, binary)
    local arguments = (target:values("charon.strip") or "-x"):split("%s+")
    os.vrunv("xcrun", table.join({"strip"}, arguments, {binary}))
end

function sign(target, binary, entitlements)
    signing.sign(ldid(target), binary, {
        entitlements = entitlements and path.join(target:scriptdir(), entitlements),
        waived = waivers(target)
    })
end

function finish(target, binary)
    strip(target, binary)
    sign(target, binary, target:values("charon.entitlements"))
end

function install_files(target)
    local sources, destinations = target:installfiles(target:installdir())
    for index, source in ipairs(sources or {}) do
        os.mkdir(path.directory(destinations[index]))
        os.vcp(source, destinations[index])
    end
end

function application(target)
    local name = target:basename()
    local folder = path.join(target:targetdir(), name .. ".app")
    os.tryrm(folder)
    local frameworks = path.join(folder, "Frameworks")
    local executable = path.join(folder, name)
    os.mkdir(folder)
    os.vcp(target:targetfile(), executable)
    local identities = {}
    local binaries = {executable}
    for _, library in ipairs(bundle.carried_libraries(target)) do
        local destination = path.join(frameworks, library.name)
        os.mkdir(frameworks)
        os.vcp(library.source, destination)
        identities[destination] = "@executable_path/Frameworks/" .. library.name
        table.insert(binaries, destination)
    end
    local shared = shared_runtime(target)
    bundle.retarget(binaries, identities, {provided = shared and shared.identities})
    bundle.copy_resources(target, folder)
    bundle.write_plist(path.join(folder, "Info.plist"), bundle.info(target, deployment(target)))
    for _, binary in ipairs(binaries) do
        verify(target, binary, {imports = false})
        strip(target, binary)
    end
    for index = #binaries, 1, -1 do
        sign(target, binaries[index], binaries[index] == executable and target:values("charon.entitlements") or nil)
    end
    if not os.getenv("CHARON_SLICE") then
        local source = imports_source(target)
        local provided = provided_libraries(target)
        dyld.check(source, table.join(binaries, provided), folder)
        report_selectors(source, binaries, target:arch(), folder, provided)
    end
    return folder
end
