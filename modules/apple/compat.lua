ARRIVED = {
    __bswapdi2 = {iOS = "3.0"},
    __bswapsi2 = {iOS = "3.0"},
    __floatundidf = {iOS = "3.0"},
    __floatundisf = {iOS = "3.0"},
    __floatunsidf = {iOS = "3.0"},
    __floatunsisf = {iOS = "3.0"},
    aligned_alloc = {iOS = "13.0", Macos = "10.15", tvOS = "13.0", watchOS = "6.0"},
    clock_gettime = {iOS = "10.0", Macos = "10.12", tvOS = "10.0", watchOS = "3.0"},
    fdopendir = {iOS = "8.0", Macos = "10.10", tvOS = "9.0", watchOS = "2.0"},
    posix_memalign = {iOS = "3.0", Macos = "10.6"},
    openat = {iOS = "8.0", Macos = "10.10", tvOS = "9.0", watchOS = "2.0"},
    fchmodat = {iOS = "8.0", Macos = "10.10", tvOS = "9.0", watchOS = "2.0"},
    unlinkat = {iOS = "8.0", Macos = "10.10", tvOS = "9.0", watchOS = "2.0"},
    __sincos_stret = {iOS = "7.0", Macos = "10.9"},
    __sincosf_stret = {iOS = "7.0", Macos = "10.9"},
    __strlcpy_chk = {iOS = "7.0", Macos = "10.9"},
    __strlcat_chk = {iOS = "7.0", Macos = "10.9"},
    __ulock_wait = {iOS = "10.0", Macos = "10.12", tvOS = "10.0", watchOS = "3.0"},
    __ulock_wake = {iOS = "10.0", Macos = "10.12", tvOS = "10.0", watchOS = "3.0"}
}

EMITTED = {
    {by = "arclite, which clang force-loads when -fobjc-arc is on the link and not only on the compile",
     symbols = {"objc_retain", "objc_release", "objc_autorelease", "objc_retainAutorelease", "objc_retainAutoreleasedReturnValue",
                "objc_autoreleaseReturnValue", "objc_retainAutoreleaseReturnValue", "objc_retainBlock", "objc_storeStrong",
                "objc_storeWeak", "objc_loadWeak", "objc_loadWeakRetained", "objc_initWeak", "objc_destroyWeak",
                "objc_copyWeak", "objc_moveWeak", "objc_autoreleasePoolPush", "objc_autoreleasePoolPop"}},
    {by = "libBlocksRuntime, which the toolchain links below 3.2",
     symbols = {"_Block_copy", "_Block_release", "_Block_object_assign", "_Block_object_dispose",
                "_NSConcreteStackBlock", "_NSConcreteGlobalBlock", "_NSConcreteMallocBlock"}},
    {by = "the libc++abi of charon@libcxx, which an image that uses them links",
     symbols = {"__emutls_get_address", "__cxa_thread_atexit", "__atomic_load", "__atomic_store", "__atomic_exchange",
                "__atomic_compare_exchange", "__atomic_is_lock_free"}},
    {by = "dyld from 9.0 on, and below it by the -femulated-tls the toolchain compiles with",
     symbols = {"_tlv_atexit", "_tlv_bootstrap"}}
}

function emitted()
    local found = {}
    for _, group in ipairs(EMITTED) do
        for _, symbol in ipairs(group.symbols) do
            found[symbol] = group.by
        end
    end
    return found
end

function arrived(system)
    local found = {}
    for symbol, releases in pairs(ARRIVED) do
        found[symbol] = releases[system]
    end
    return found
end

function force_includes(package, symbols)
    local folders = {}
    if package.fetch then
        table.insert(folders, path.join(package:installdir(), "include"))
    else
        table.join2(folders, table.wrap(package:get("sysincludedirs")), table.wrap(package:get("includedirs")))
    end
    local flags = {}
    for _, symbol in ipairs(table.wrap(symbols)) do
        if not ARRIVED[symbol] then
            raise("apple-compat provides nothing named %s; it knows %s", symbol, table.concat(table.orderkeys(ARRIVED), ", "))
        end
        for _, folder in ipairs(folders) do
            local header = path.join(folder, "charon", symbol .. ".h")
            if os.isfile(header) then
                table.insert(flags, "-include" .. header)
                break
            end
        end
    end
    return flags
end
