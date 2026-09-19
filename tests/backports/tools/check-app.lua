function main(release, band, ...)
    local binaries = {...}
    assert(release and band and #binaries > 0, "usage: xmake l check-app.lua <release> <band folder> <binary>...")
    local dyld = import("apple.dyld", {rootdir = path.join(os.getenv("CHARON_ROOT"), "modules"), anonymous = true})
    local cache = path.join(os.getenv("HOME"), ".charon", "dyld", release, "dyld_shared_cache_armv7")
    local provided = {}
    for _, library in ipairs(os.files(path.join(band, "*.dylib"))) do
        table.insert(provided, library)
    end
    local checked = table.join(binaries, provided)
    local missing = dyld.missing_imports(cache, checked)
    local exported = {}
    for _, library in ipairs(provided) do
        for symbol in os.iorunv("xcrun", {"nm", "-gU", library}):gmatch("[^\n]+ [TDSsdt] (_[^%s]+)") do
            exported[symbol] = true
        end
    end
    local linkage, absent = {}, {}
    for _, entry in ipairs(missing) do
        local line = string.format("%s  %s", path.filename(entry[1]), entry[2]:gsub("%s*%(.*$", ""))
        if exported[entry[2]:match("^(%S+)")] then
            table.insert(linkage, line)
        else
            table.insert(absent, line)
        end
    end
    print("%d binaries checked against the shared cache of iOS %s and the libraries in %s", #binaries, release, band)
    print("")
    print("carried by the backports, and unresolved only because the stock library is bound first (%d):", #linkage)
    for _, line in ipairs(linkage) do
        print("  " .. line)
    end
    print("")
    print("not carried by the backports and not in the release (%d):", #absent)
    for _, line in ipairs(absent) do
        print("  " .. line)
    end
end
