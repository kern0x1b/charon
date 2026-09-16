import("macho")
import("compat")
import("dyld")
import("signing")
import("bundle")

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

function verify(target, binary, opt)
    opt = opt or {}
    macho.verify(binary, {waived = waivers(target), arrived = compat.arrived("iOS"), stripped = opt.stripped})
    if opt.imports ~= false then
        dyld.check(dyld.held_cache(target:arch()), {binary})
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
    bundle.retarget(binaries, identities)
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
        dyld.check(dyld.held_cache(target:arch()), binaries, folder)
    end
    return folder
end
