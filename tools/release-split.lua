-- xmake l tools/release-split.lua OBJECTSDIR [OUTPUT]
--
-- MANDATORY: a band runs this after its own build() and before handing off a
-- patch (or running write_deb()'s full band rebuild). It needs OBJECTSDIR's
-- *.o already compiled, so it cannot be the gate's first step, and it does
-- not replace band() -- see the divergence note below -- so it does not
-- replace write_deb() either. It is the fast, mandatory check in between.
--
-- For every *.o in OBJECTSDIR, lists the symbols it defines (nm -gU, with
-- ivars, $shim and Charon-/charon-prefixed internal symbols and ObjC protocol
-- metadata excluded -- the same exclusions modules/apple/backports.lua's own
-- internal_symbol()/exported_symbols() apply) and, for each symbol, walks
-- every release under dyld.root() oldest to newest to find the first one
-- that exports it. Groups by file and flags every file whose symbols first
-- appear in more than one release -- the same condition band() in
-- modules/apple/backports.lua refuses at link time with "an object carries
-- API that arrived in one release, so split it".
--
-- Run this before a band build, not instead of one: it is stricter than
-- band() itself, not a duplicate of it. band() only tests a file's symbols
-- against the one release each existing band boundary happens to check
-- against; band_ranges() rounds a registry's declared "introduced" version
-- up to the nearest of those boundaries. Two symbols declared for the same
-- rounded-up version can share an object file, pass band() clean, and still
-- be wrong by a full release apart underneath. Measured case: SCNLightTypeIES
-- (introduced) and SCNLightTypeProbe were both declared "10.0" and built into
-- SCNLightConstants10.m; the port's own gate (check_releases and band())
-- accepted the file and linked SceneKitBackports without complaint. Only this
-- script, walking the real release cache ladder symbol by symbol, showed
-- SCNLightTypeProbe already exporting at 9.0 -- one release early, and wrong
-- in the registry even though the build was green. If this script prints
-- nothing under "release-split:", a following band build can still fail on
-- something outside this check (an internal symbol that band()/write_deb()
-- treats differently from build(), or a release_exports mismatch this
-- script's cache reading does not model) -- it narrows the search, it does
-- not replace the gate.

import("apple.dyld", {rootdir = path.join(os.scriptdir(), "..", "modules")})

local EXCLUDED = {
    "^_OBJC_IVAR_%$_",
    "^__OBJC_PROTOCOL_%$_",
    "^__OBJC_LABEL_PROTOCOL_%$_",
    "^___block_descriptor",
}

local function internal(name)
    if name:find("$shim", 1, true) then
        return true
    end
    for _, pattern in ipairs(EXCLUDED) do
        if name:match(pattern) then
            return true
        end
    end
    local bare = name:match("^_OBJC_%u*CLASS_%$_(.+)$") or name:match("^_(.+)$") or name
    return bare:startswith("charon_") or bare:startswith("Charon")
end

local function symbols_of(object)
    local out = os.iorunv("nm", {"-gU", object})
    local found = {}
    for line in out:gmatch("[^\n]+") do
        local name = line:match("%S+$")
        if name and not internal(name) then
            table.insert(found, name)
        end
    end
    return found
end

local function ladder()
    local releases = {}
    for _, folder in ipairs(os.dirs(path.join(dyld.root(), "*"))) do
        local release = path.filename(folder)
        if release:match("^%d+[%.%d]*$") then
            local cache = dyld.held_source(folder, "armv7") or dyld.held_source(folder, "armv7s")
            if cache and os.isfile(cache) then
                table.insert(releases, {release = release, cache = cache})
            end
        end
    end
    table.sort(releases, function (a, b) return dyld.compare_versions(a.release, b.release) < 0 end)
    return releases
end

function main(objectsdir, output)
    assert(objectsdir, "usage: xmake l tools/release-split.lua OBJECTSDIR [OUTPUT]")
    local files = os.files(path.join(objectsdir, "*.o"))
    assert(#files > 0, objectsdir .. " holds no *.o")
    table.sort(files)

    local by_file, all_symbols = {}, {}
    for _, file in ipairs(files) do
        local name = path.filename(file)
        by_file[name] = symbols_of(file)
        for _, symbol in ipairs(by_file[name]) do
            all_symbols[symbol] = true
        end
    end

    local first = {}
    for _, entry in ipairs(ladder()) do
        local release = dyld.load(entry.cache)
        for symbol in pairs(all_symbols) do
            if not first[symbol] and release.exports[symbol] then
                first[symbol] = entry.release
            end
        end
    end

    local lines, mixed = {}, {}
    for _, file in ipairs(files) do
        local name = path.filename(file)
        local seen = {}
        for _, symbol in ipairs(by_file[name]) do
            local release = first[symbol] or "none"
            table.insert(lines, name .. "\t" .. symbol .. "\t" .. release)
            seen[release] = true
        end
        local distinct = table.orderkeys(seen)
        if #distinct > 1 then
            table.insert(lines, name .. "\tMIXED-RELEASES\t" .. table.concat(distinct, ","))
            table.insert(mixed, name)
        end
    end

    local text = table.concat(lines, "\n") .. "\n"
    if output then
        io.writefile(output, text)
    else
        print(text)
    end

    if #mixed > 0 then
        raise("release-split: %d file(s) mix more than one release's symbols: %s", #mixed, table.concat(mixed, ", "))
    end
    cprint("release-split: clean, every object file's symbols first-appear in one release (%d files, %d symbols, %d releases checked)",
           #files, table.orderkeys(all_symbols) and #table.orderkeys(all_symbols) or 0, #ladder())
end
