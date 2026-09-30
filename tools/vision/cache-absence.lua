-- xmake l tools/vision/cache-absence.lua <cache file>
--
-- Does a release's armv7 shared cache hold a Vision image, and does it export a name of Vision?
--
-- This is the one measurement every Vision registry row cites. Vision.framework arrived in iOS 11.0 and the
-- releases this package carries have none of it, so the honest end for a Vision row is `absent` with THIS as
-- the reason: the cache is read, not assumed, and two controls say the probe finds what is there - NSObject
-- and PassKit, the same two HealthKit used, because a probe that finds nothing everywhere proves nothing.
-- A name no cache exports reports as absent rather than as a count of zero.

function main(cachefile)
    assert(cachefile, "usage: cache-absence.lua <cache file>")
    local modules = os.getenv("CHARON_ROOT") .. "/modules"
    local dyld = import("apple.dyld", {rootdir = modules, anonymous = true})
    local objc = import("apple.objc", {rootdir = modules, anonymous = true})

    -- Not asserted: assert() swallows its own message in this build, which is why the earlier run said
    -- only "assertion failed!" and not which of the two calls below was the one that failed.
    local opened, err = dyld.open_cache(cachefile)
    if not opened then
        print("NO CACHE  " .. tostring(cachefile) .. "  " .. tostring(err))
        return
    end
    local cache = opened
    local inventory = objc.inventory(cache)
    local total, vision, nsobject, passkit = 0, 0, 0, 0
    for _, name in pairs(inventory.classnames or {}) do
        total = total + 1
        if name == "Vision" then vision = vision + 1
        elseif name == "NSObject" then nsobject = nsobject + 1
        elseif name == "PassKit" then passkit = passkit + 1 end
    end
    local here = cachefile
    print("%-52s strings %6d   Vision %d   NSObject %d   PassKit %d",
          string.match(here, "([^/]+)/dyld_shared_cache_armv7$") or here, total, vision, nsobject, passkit)
end
