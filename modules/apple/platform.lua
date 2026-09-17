import("macho")
import("compat")
import("dyld")
import("firmware")
import("objc")
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

function report_selectors(source, binaries, architecture, folder)
    for binary, missing in pairs(objc.absent_selectors(source, binaries, architecture)) do
        local named = folder and path.relative(binary, folder) or binary
        local shown = table.concat(table.slice(missing, 1, math.min(12, #missing)), " ") .. (#missing > 12 and string.format(" and %d more", #missing - 12) or "")
        wprint("%s sends %d selector%s no class of the %s release it is checked against implements, which must run only behind respondsToSelector: or a version check: %s",
               named, #missing, #missing == 1 and "" or "s", architecture, shown)
    end
end

function verify(target, binary, opt)
    opt = opt or {}
    verify_minimum(target, binary)
    macho.verify(binary, {waived = waivers(target), arrived = compat.arrived("iOS"), stripped = opt.stripped})
    if opt.imports ~= false then
        local source = imports_source(target)
        dyld.check(source, {binary})
        report_selectors(source, {binary}, target:arch())
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
        local source = imports_source(target)
        dyld.check(source, binaries, folder)
        report_selectors(source, binaries, target:arch(), folder)
    end
    return folder
end
