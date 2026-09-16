ARRIVED = {
    aligned_alloc = {iOS = "13.0", Macos = "10.15", tvOS = "13.0", watchOS = "6.0"},
    clock_gettime = {iOS = "10.0", Macos = "10.12", tvOS = "10.0", watchOS = "3.0"},
    fdopendir = {iOS = "8.0", Macos = "10.10", tvOS = "9.0", watchOS = "2.0"},
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
