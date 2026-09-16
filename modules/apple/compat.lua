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
