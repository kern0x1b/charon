import("macho")
import("compat")
import("dyld")
import("signing")

function waivers(target)
    local waived = {}
    for _, name in ipairs(macho.WAIVABLE) do
        waived[name] = target:values("charon.waive." .. name)
    end
    return waived
end

function verify(target, binary)
    macho.verify(binary, {waived = waivers(target), arrived = compat.arrived("iOS")})
    dyld.check(dyld.held_cache(target:arch()), {binary})
end

function finish(target, binary)
    os.vrunv("xcrun", {"strip", "-x", binary})
    local entitlements = target:values("charon.entitlements")
    signing.sign(path.join(target:pkg("ldid"):installdir(), "bin", "ldid"), binary, {
        entitlements = entitlements and path.join(target:scriptdir(), entitlements),
        waived = waivers(target)
    })
end
