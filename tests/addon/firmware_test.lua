import("fixtures")

-- A system image as harvest sees it once mounted: one armv7 shared cache holding the given bytes.
local function image(folder, name, bytes)
    local mount = path.join(folder, name)
    io.writefile(path.join(mount, "System", "Library", "Caches", "com.apple.dyld", "dyld_shared_cache_armv7"), bytes)
    return mount
end

function failures(opt)
    local found = {}
    local folder = fixtures.scratch()
    local home = os.getenv("CHARON_HOME")
    os.setenv("CHARON_HOME", path.join(folder, "home"))
    local firmware = import("apple.firmware", {rootdir = opt.modules, anonymous = true})
    local dyld = import("apple.dyld", {rootdir = opt.modules, anonymous = true})
    local held = path.join(dyld.root(), "9.9", "dyld_shared_cache_armv7")
    local outside = dyld.outside_source(path.directory(held), "armv7")
    local first, other = {identifier = "iPad2,4", build = "99A1"}, {identifier = "iPhone4,1", build = "99A1"}

    local taken = firmware.harvest(image(folder, "first", "the cache of one firmware"), "9.9", first)
    if table.concat(taken, " ") ~= "armv7" or io.readfile(held) ~= "the cache of one firmware" then
        table.insert(found, "a release with no cache takes the image's")
    end
    if not os.isdir(outside) then
        table.insert(found, "taking a cache takes the libraries beside it, even when there are none")
    end

    -- The same cache from another firmware is the same release: kept, and its libraries taken.
    os.tryrm(outside)
    local errors = fixtures.refusal(function () firmware.harvest(image(folder, "same", "the cache of one firmware"), "9.9", other) end)
    if errors or not os.isdir(outside) then
        table.insert(found, "an image carrying the held cache is accepted: " .. tostring(errors))
    end

    -- Another cache is another firmware's: the held one is the ladder every gate reads.
    os.tryrm(outside)
    errors = fixtures.refusal(function () firmware.harvest(image(folder, "another", "the cache of another firmware"), "9.9", other) end)
    if not errors or not errors:find("iPhone4,1 99A1", 1, true) then
        table.insert(found, "an image carrying another cache than the held one is refused by the firmware's name: " .. tostring(errors))
    end
    if io.readfile(held) ~= "the cache of one firmware" then
        table.insert(found, "a held cache is never written over")
    end
    if os.isdir(outside) then
        table.insert(found, "the libraries of a refused image are not taken")
    end

    os.setenv("CHARON_HOME", home or nil)
    os.tryrm(folder)
    return found
end
