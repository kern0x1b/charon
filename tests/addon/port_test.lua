import("fixtures")

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

-- The version an addon is installed under is what xmake keeps it by, so it names this copy of the working tree: a run
-- against changed files must not be answered with the addon a previous run installed.

local function repository(folder)
    local root = path.absolute(path.join(os.scriptdir(), "..", ".."))
    local copy = path.join(folder, "charon")
    os.mkdir(copy)
    local listed = os.iorunv("git", {"-C", root, "ls-files", "-c", "-o", "--exclude-standard"})
    for _, file in ipairs(listed:split("\n", {plain = true})) do
        file = file:trim()
        if file ~= "" and os.isfile(path.join(root, file)) then
            os.mkdir(path.directory(path.join(copy, file)))
            os.cp(path.join(root, file), path.join(copy, file))
        end
    end
    for _, argv in ipairs({{"init", "-q", "-b", "main"}, {"add", "-A"},
                           {"-c", "user.name=charon", "-c", "user.email=charon@example.com", "commit", "-q", "-m", "the working tree"}}) do
        os.vrunv("git", table.join({"-C", copy}, argv))
    end
    local head = os.iorunv("git", {"-C", copy, "rev-parse", "HEAD"}):trim()
    local version = "v0.0.0-" .. head:sub(1, 12)
    os.vrunv("git", {"-C", copy, "tag", version})

    -- The recipe of the addon is read from this directory, while the addon itself is cloned from its history, so naming
    -- the copy and its one version here needs no commit of its own.
    local recipe = path.join(copy, "addons", "c", "charon", "xmake.lua")
    local text = io.readfile(recipe):gsub('add_urls%("[^"]*"%)', 'add_urls("' .. path.join(copy, ".git") .. '")', 1)
    io.writefile(recipe, text .. string.format('    add_versions("%s", "%s")\n', version, head))
    return copy, version
end

local function port(folder, version, name, source, requires, packages)
    local at = path.join(folder, name)
    os.mkdir(at)
    io.writefile(path.join(at, "main.c"), source)
    io.writefile(path.join(at, "control"), CONTROL)
    io.writefile(path.join(at, "xmake.lua"), string.format(PROJECT, folder .. "/charon", version, requires or "", packages or ""))
    return at
end

local function built(at)
    os.vrunv("xmake", {"f", "-p", "iphoneos", "-a", "armv7", "-y"}, {curdir = at})
    os.vrunv("xmake", {"build", "-y"}, {curdir = at})
end

function failures(opt)
    local found = {}
    local folder = fixtures.scratch()
    local copy, version = repository(folder)

    -- A port that asks for nothing an old release lacks is built, placed and checked, and its binary is there.
    local plain = port(folder, version, "plain", MAIN)
    local refused = fixtures.refusal(function () built(plain) end)
    if refused then
        table.insert(found, "a daemon port that calls nothing an old release lacks must build: " .. refused)
    elseif #os.files(path.join(plain, "build", "**", "probe")) == 0 then
        table.insert(found, "the daemon rule built no binary for the port")
    end

    -- The checks after the link answer with the library that carries the call, and the answer differs: a symbol one image
    -- may carry comes from apple-compat, and one the whole process shares comes from the C++ runtime that exports it once.
    for _, case in ipairs({{"later", LATER, "apple%-compat::dispatch_activate"},
                           {"locked", LOCKED, "charon@libcxx"}}) do
        local told = fixtures.refusal(function () built(port(folder, version, case[1], case[2])) end)
        if not told then
            table.insert(found, string.format("a port calling %s must be refused at %s", case[1], "iOS 6.0"))
        elseif not told:find(case[3]) then
            table.insert(found, string.format("the refusal of the %s port must name %s: %s", case[1], case[3], told))
        end
    end
    os.tryrm(folder)
    return found
end
