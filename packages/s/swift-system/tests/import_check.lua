-- Checks the armv7 libswiftSystem.dylib against the iOS 6.1.3 shared cache with modules/apple/dyld.lua's own check, the function
-- the 6.1.3 gate calls: every non-weak import must resolve against the cache's exports, and the weak ones are reported.
-- The Swift runtime's libraries the dylib links are given as the program's providers (checked, reported, not refused), the
-- way the gate gives another package's images. dyld.check prints the verdict line itself, like the gate's.
--
-- Usage: xmake l packages/s/swift-system/tests/import_check.lua <checkout> <cachefile> <libswiftSystem.dylib> <runtime lib/swift/iphoneos>
-- The cache is passed by path and read only by dyld.check; this test does not open it.
function main(checkout, cachefile, dylib, runtime)
    assert(checkout and cachefile and dylib and runtime, "usage: import_check.lua <checkout> <cachefile> <dylib> <runtime lib/swift/iphoneos>")
    local dyld = import("apple.dyld", {rootdir = path.join(checkout, "modules"), anonymous = true})
    local providers = {}
    for _, name in ipairs({"libswiftCore.dylib", "libswiftDarwin.dylib", "libswiftObjectiveC.dylib", "libswiftDispatch.dylib",
                           "libswift_Concurrency.dylib"}) do
        table.insert(providers, path.join(runtime, name))
    end
    -- The dylib is the image under test; the runtime's libraries are its providers, as the gate passes them.
    local binaries = table.join({dylib}, providers)
    dyld.check(cachefile, binaries, nil, {exempt = providers})
    return true
end
