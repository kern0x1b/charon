import("fixtures")
import("core.package.addon")

-- What a port reaches through @addon/charon is the addon, not the files of this checkout, so the rules of a port - the
-- toolchain, the checks after the link, the placement - are exercised only where a port is really built. The suites
-- around this one build objects and binaries by hand and never take that road, which is how a call in the checks after
-- the link went missing without a single test turning red.
--
-- The addon is installed the way a port installs one, from a repository, and the repository here is a copy of this
-- working tree rather than its history: a test must check the files as they are now, not as they were committed.

local MAIN = "int main(void) { return 0; }\n"

-- A release older than the call it makes: the checks after the link read the imports of the binary and name what carries
-- each one. os_unfair_lock_lock is one of the symbols a whole process shares, so the remedy for it is the C++ runtime,
-- which exports it once; dispatch_activate is an ordinary one, and apple-compat carries it per image.
local LOCKED = "extern void os_unfair_lock_lock(void *lock);\nstatic long word;\nint main(void) { os_unfair_lock_lock(&word); return 0; }\n"
local LATER = "extern void dispatch_activate(void *object);\nint main(void) { dispatch_activate(0); return 0; }\n"

local CONTROL = "Package: org.charon.porttest\nName: Port test\nArchitecture: iphoneos-arm\nDescription: a port the tests build\n"

local PROJECT = [[
add_repositories("charon %s")
add_addons("charon %s")
set_config("apple_minimum", "6.0")
includes("@addon/charon/apple-ios")
set_allowedplats("iphoneos")
set_allowedarchs("iphoneos|armv7")
set_defaultplat("iphoneos")
set_defaultarchs("iphoneos|armv7")
%s
target("probe")
    add_rules("@addon/charon/daemon")
    add_files("main.c")
    set_values("charon.control", "control")
%s
]]

local function port(folder, version, name, source, requires, packages)
    local at = path.join(folder, name)
    os.mkdir(at)
    io.writefile(path.join(at, "main.c"), source)
    io.writefile(path.join(at, "control"), CONTROL)
    io.writefile(path.join(at, "xmake.lua"), string.format(PROJECT, folder .. "/charon", version, requires or "", packages or ""))
    return at
end

function failures(opt)
    local found = {}
    local folder = fixtures.scratch()
    local copy, version = fixtures.repository(folder)

    -- A port that asks for nothing an old release lacks is built, placed and checked, and its binary is there.
    local plain = port(folder, version, "plain", MAIN)
    local refused = fixtures.refusal(function () fixtures.build(plain) end)
    if refused then
        table.insert(found, "a daemon port that calls nothing an old release lacks must build: " .. refused)
    elseif #os.files(path.join(plain, "build", "**", "probe")) == 0 then
        table.insert(found, "the daemon rule built no binary for the port")
    end

    -- The checks after the link answer with the library that carries the call, and the answer differs: a symbol one image
    -- may carry comes from apple-compat, and one the whole process shares comes from the C++ runtime that exports it once.
    for _, case in ipairs({{"later", LATER, "apple%-compat::dispatch_activate"},
                           {"locked", LOCKED, "charon@libcxx"}}) do
        local told = fixtures.refusal(function () fixtures.build(port(folder, version, case[1], case[2])) end)
        if not told then
            table.insert(found, string.format("a port calling %s must be refused at %s", case[1], "iOS 6.0"))
        elseif not told:find(case[3]) then
            table.insert(found, string.format("the refusal of the %s port must name %s: %s", case[1], case[3], told))
        end
    end
    -- The addon this installed is named after the tree it copied, so it is this run's and no other's; a test that leaves
    -- one behind would leave one for every run it ever made. Both halves go: the files, and the registry entry that
    -- names them - an entry whose files are gone is worse than the files, because the next install reads it and stops.
    addon.unregister("charon", version)
    os.tryrm(path.join(addon.installdir(), addon.dirname("charon"), version))
    os.tryrm(folder)
    return found
end
