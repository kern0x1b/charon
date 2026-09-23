-- xmake l tools/release-split.lua OBJECTSDIR [OUTPUT] [SDKDIR]
--
-- SDKDIR is the iPhoneOS SDK whose .tbd files say which library each symbol belongs to (the newest
-- one in the shared xmake store when not given). A symbol counts as exported only by that library
-- or one it re-exports, where a client binds it, not by a same-named symbol elsewhere in the cache.
--
-- What a run measures is kept in $CHARON_HOME/cache (dyld.sdk_owners, dyld.first_releases), keyed
-- by the SDK's .tbd files, the rungs' files and the code that reads them, so a second run over
-- symbols already measured loads no cache and reads no .tbd.
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
--
-- BLIND SPOT, confirmed not theoretical: an Objective-C category's method
-- implementations (e.g. a class extension like NSValue+SceneKit.m) compile
-- to no nm-visible exported symbol at all -- nm -gU on such a file returns
-- nothing, so this script silently checks zero symbols for it and can never
-- flag a category method that spans releases. Measured while carrying
-- SceneKit's NSValue(SceneKitAdditions) category: this script reported
-- "clean" while including that file, having checked none of its six methods.
-- Checking a category's own introduced version needs a different measurement
-- (a literal selector-string search across the cache ladder -- strings -a
-- CACHE | grep -xF SELECTOR, with a nonsense-selector negative control --
-- worked where it was tried; modules/apple/objc.lua's inventory() did not,
-- because it does not merge a category compiled into one image onto a class
-- defined in another). This script does not attempt that measurement; do not
-- read a clean run as covering any category file.
--
-- FIXED, was a false-positive source: ARC's compiler-generated block copy/destroy helpers
-- (___copy_helper_block_*, ___destroy_helper_block_*) get external linkage so identical helpers
-- merge across translation units, which makes them nm -gU-visible even though they are not part
-- of any release's real export surface -- they never appear in any dyld cache, so every one of
-- them classified as "none" and, sharing a file with a single genuine API symbol, made that file
-- read as spanning two releases when it does not. Measured on 10 of 14 files a first run of this
-- script flagged MIXED-RELEASES (UISearchController.o, UIViewPropertyAnimator.o and others): each
-- carried exactly one real symbol plus these helpers, none of which any release will ever export.

import("apple.dyld", {rootdir = path.join(os.scriptdir(), "..", "modules")})

local EXCLUDED = {
    "^_OBJC_IVAR_%$_",
    "^__OBJC_PROTOCOL_%$_",
    "^__OBJC_LABEL_PROTOCOL_%$_",
    "^__OBJC_PROTOCOL_REFERENCE_%$_",
    "^___block_descriptor",
    "^___block_literal_",
    "^___copy_helper_block_",
    "^___destroy_helper_block_",
    "^___NSArray%d+__$",
    "^___NSDictionary%d+__$",
    "^___kCFBooleanTrue$",
    "^___kCFBooleanFalse$",
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
    return dyld.held_ladder({"armv7", "armv7s"})
end

local function newest_sdk()
    local found = os.dirs(path.join(os.getenv("HOME"), ".xmake", "packages", "i", "iphoneos-sdk", "*", "*", "Developer.app",
                                    "Contents", "Developer", "Platforms", "iPhoneOS.platform", "Developer", "SDKs", "iPhoneOS*.sdk"))
    table.sort(found, function (a, b) return os.mtime(a) > os.mtime(b) end)
    return found[1]
end

function main(objectsdir, output, sdkdir)
    assert(objectsdir, "usage: xmake l tools/release-split.lua OBJECTSDIR [OUTPUT] [SDKDIR]")
    sdkdir = sdkdir or newest_sdk()
    assert(sdkdir and os.isdir(sdkdir), "release-split: no iPhoneOS SDK found; pass SDKDIR")
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

    local first = dyld.first_releases(ladder(), sdkdir, table.orderkeys(all_symbols))

    -- A class and its metaclass are one API, and it arrives with the class: a release can export the
    -- class alone (NaturalLanguage of 12.0 exports _OBJC_CLASS_$_NLTokenizer, its metaclass only from
    -- 16.0), which would otherwise read as one object spanning two releases.
    for symbol in pairs(all_symbols) do
        local class = symbol:match("^_OBJC_METACLASS_%$_(.+)$")
        local arrived = class and first["_OBJC_CLASS_$_" .. class]
        if arrived and (not first[symbol] or dyld.compare_versions(arrived, first[symbol]) < 0) then
            first[symbol] = arrived
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

    -- A release named here is the first held rung that exports the symbol, so it bounds the arrival
    -- from above; where the ladder skips whole major releases (nothing is held between 12.0 and
    -- 16.0), a symbol of 13.0, 14.0 or 15.0 reads as 16.0. Say so, from the rungs actually held.
    local rungs = ladder()
    for index = 2, #rungs do
        local previous, current = rungs[index - 1].release, rungs[index].release
        if tonumber(current:match("^%d+")) - tonumber(previous:match("^%d+")) > 1 then
            cprint("${color.warning}note:${clear} no release is held between %s and %s, so %s here means after %s and by %s, not a measured first release",
                   previous, current, current, previous, current)
        end
    end

    if #mixed > 0 then
        raise("release-split: %d file(s) mix more than one release's symbols: %s", #mixed, table.concat(mixed, ", "))
    end
    cprint("release-split: clean, every object file's symbols first-appear in one release (%d files, %d symbols, %d releases checked)",
           #files, table.orderkeys(all_symbols) and #table.orderkeys(all_symbols) or 0, #ladder())
end
