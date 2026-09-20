ARRIVED = {
    __bswapdi2 = {iOS = "3.0"},
    __bswapsi2 = {iOS = "3.0"},
    __floatundidf = {iOS = "3.0"},
    __floatundisf = {iOS = "3.0"},
    __floatunsidf = {iOS = "3.0"},
    __floatunsisf = {iOS = "3.0"},
    aligned_alloc = {iOS = "13.0", Macos = "10.15", tvOS = "13.0", watchOS = "6.0"},
    arc4random_buf = {iOS = "4.3", Macos = "10.7"},
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
    __ulock_wake = {iOS = "10.0", Macos = "10.12", tvOS = "10.0", watchOS = "3.0"},
    clock_getres = {iOS = "10.0", Macos = "10.12", tvOS = "10.0", watchOS = "3.0"},
    os_unfair_lock_lock = {iOS = "10.0", Macos = "10.12", tvOS = "10.0", watchOS = "3.0"},
    os_unfair_lock_trylock = {iOS = "10.0", Macos = "10.12", tvOS = "10.0", watchOS = "3.0"},
    os_unfair_lock_unlock = {iOS = "10.0", Macos = "10.12", tvOS = "10.0", watchOS = "3.0"},
    os_unfair_recursive_lock_lock_with_options = {iOS = "12.0", Macos = "10.14", tvOS = "12.0", watchOS = "5.0"},
    os_unfair_recursive_lock_unlock = {iOS = "12.0", Macos = "10.14", tvOS = "12.0", watchOS = "5.0"},
    memset_s = {iOS = "7.0", Macos = "10.9"},
    objc_allocWithZone = {iOS = "7.0", Macos = "10.9"},
    objc_opt_self = {iOS = "11.0", Macos = "10.13", tvOS = "11.0", watchOS = "4.0"},
    voucher_adopt = {iOS = "8.0", Macos = "10.10", tvOS = "9.0", watchOS = "2.0"},
    voucher_copy = {iOS = "8.0", Macos = "10.10", tvOS = "9.0", watchOS = "2.0"},
    qos_class_self = {iOS = "8.0", Macos = "10.10", tvOS = "9.0", watchOS = "2.0"},
    dispatch_block_create = {iOS = "8.0", Macos = "10.10", tvOS = "9.0", watchOS = "2.0"},
    dispatch_block_create_with_qos_class = {iOS = "8.0", Macos = "10.10", tvOS = "9.0", watchOS = "2.0"},
    dispatch_block_perform = {iOS = "8.0", Macos = "10.10", tvOS = "9.0", watchOS = "2.0"},
    dispatch_block_wait = {iOS = "8.0", Macos = "10.10", tvOS = "9.0", watchOS = "2.0"},
    dispatch_block_notify = {iOS = "8.0", Macos = "10.10", tvOS = "9.0", watchOS = "2.0"},
    dispatch_block_cancel = {iOS = "8.0", Macos = "10.10", tvOS = "9.0", watchOS = "2.0"},
    dispatch_block_testcancel = {iOS = "8.0", Macos = "10.10", tvOS = "9.0", watchOS = "2.0"},
    os_unfair_lock_assert_owner = {iOS = "10.0", Macos = "10.12", tvOS = "10.0", watchOS = "3.0"},
    os_unfair_lock_assert_not_owner = {iOS = "10.0", Macos = "10.12", tvOS = "10.0", watchOS = "3.0"},
    dispatch_activate = {iOS = "10.0", Macos = "10.12", tvOS = "10.0", watchOS = "3.0"},
    ["dispatch_assert_queue$V2"] = {iOS = "10.0", Macos = "10.12", tvOS = "10.0", watchOS = "3.0"}
}

-- Calls whose state every image in a process shares: a lock one image takes and another releases waits and wakes through one
-- table. apple-compat does not link these into each image; libc++abi of charon@libcxx exports them once for the process.
PROCESS_WIDE = {
    os_unfair_lock_lock = true,
    os_unfair_lock_trylock = true,
    os_unfair_lock_unlock = true,
    os_unfair_recursive_lock_lock_with_options = true,
    os_unfair_recursive_lock_unlock = true
}

-- Calls every release exports whose meaning grew later: an older release has the symbol, so an import of it is no finding,
-- but a caller that relies on what the call learned needs the shim, reached by name through its header.
CHANGED = {
    dispatch_get_global_queue = {iOS = "8.0", Macos = "10.10", tvOS = "9.0", watchOS = "2.0"}
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

function process_wide()
    return table.copy(PROCESS_WIDE)
end

function provided(system)
    local found = arrived(system)
    for symbol, releases in pairs(CHANGED) do
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
        if PROCESS_WIDE[symbol] then
            raise("%s is exported once for the process by the libc++abi of charon@libcxx, so no image renames it", symbol)
        end
        if not ARRIVED[symbol] and not CHANGED[symbol] then
            raise("apple-compat provides nothing named %s; it knows %s", symbol, table.concat(table.orderkeys(table.join(ARRIVED, CHANGED)), ", "))
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
