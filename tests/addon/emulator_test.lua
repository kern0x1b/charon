import("core.base.json")
import("async.runjobs")
import("fixtures")

local CONTROL = "Package: org.example.placed\nName: Placed\nArchitecture: iphoneos-arm\nDescription: files placed through the guest's links\n"

local LOGS = {
    springboard = {
        "[control] ready; use help for commands",
        "[display] frame=1 visible-pixels=11404",
        "[process] spawn-setexec pid=11 parent=1 suspended=0 /usr/libexec/charon-runner argv=\"/usr/libexec/charon-runner\",\"30\",\"/usr/libexec/tool\"",
        "[process] spawn-setexec pid=63 parent=1 suspended=0 /System/Library/CoreServices/SpringBoard.app/SpringBoard argv=\"/System/Library/CoreServices/SpringBoard.app/SpringBoard\"",
        "[process] spawn parent=11 child=68 suspended=0 /usr/libexec/tool argv=\"/usr/libexec/tool\"",
        "[cpu] fatal pid=68 cpu=0 pc=0x2f10 lr=0x2f01 fault=0x0 access=0x1 size=0x4 sp=0x2fffef00 cpsr=0x30",
        "[process] exit pid=68 status=0 signal=11"
    },
    looping = {
        "[control] ready; use help for commands",
        "[process] spawn-setexec pid=23 parent=1 suspended=0 /usr/libexec/backboardd argv=\"/usr/libexec/backboardd\"",
        "[process] exit pid=23 status=0 signal=11",
        "[process] spawn-setexec pid=74 parent=1 suspended=0 /usr/libexec/backboardd argv=\"/usr/libexec/backboardd\"",
        "[process] exit pid=74 status=0 signal=11",
        "[process] spawn-setexec pid=77 parent=1 suspended=0 /usr/libexec/backboardd argv=\"/usr/libexec/backboardd\"",
        "[process] exit pid=77 status=0 signal=11",
        "[process] spawn-setexec pid=64 parent=1 suspended=0 /System/Library/CoreServices/SpringBoard.app/SpringBoard argv=\"/System/Library/CoreServices/SpringBoard.app/SpringBoard\""
    },
    migrating = {
        "[control] ready; use help for commands",
        "[process] spawn-setexec pid=63 parent=1 suspended=0 /System/Library/CoreServices/SpringBoard.app/SpringBoard argv=\"\"",
        "[process] spawn-setexec pid=75 parent=1 suspended=0 /System/Library/PrivateFrameworks/DataMigration.framework/Support/DataMigrator argv=\"\""
    }
}

local function recorded(folder, name, lines, verdict)
    local run = path.join(folder, name)
    os.mkdir(path.join(run, "results"))
    io.writefile(path.join(run, "emulator.log"), table.concat(lines or {}, "\n") .. "\n")
    if verdict then
        json.savefile(path.join(run, "results", "verdict.json"), verdict)
    end
    return run
end

local function verdicts(emulator, folder, found)
    local function judged(name, lines, verdict)
        local run = recorded(folder, name, lines, verdict)
        local state = emulator.scan_file(path.join(run, "emulator.log"), {})
        return emulator.describe(emulator.verdict(state, path.join(run, "results"), {frame = path.join(run, "frame.png")}))
    end
    local test = {path = "/usr/libexec/tool", spawned = 1, spawn_error = 0, timed_out = 0, seconds = 1.5}
    local cases = {
        {"pass", LOGS.springboard, {test = table.join(test, {exit = 0})}, "pass"},
        {"fail", LOGS.springboard, {test = table.join(test, {exit = 3})}, "fail(exit 3)"},
        {"timeout", LOGS.springboard, {test = table.join(test, {timed_out = 1})}, "timeout"},
        {"crash", LOGS.springboard, {test = table.join(test, {signal = 11})}, "crash(signal 11, pc 0x2f10, last frame "},
        {"unspawned", LOGS.springboard, {test = table.join(test, {spawned = 0, spawn_error = 2})}, "fail(spawn error 2)"},
        {"looping", LOGS.looping, nil, "boot-blocked(backboardd)"},
        {"migrating", LOGS.migrating, nil, "boot-blocked(DataMigrator)"},
        {"silent", {}, nil, "boot-blocked(emulator)"}
    }
    for _, case in ipairs(cases) do
        local described = judged(case[1], case[2], case[3])
        if not described:startswith(case[4]) then
            table.insert(found, string.format("a %s run is %s..., the verdict says %s", case[1], case[4], described))
        end
    end
    local state = emulator.scan_file(path.join(recorded(folder, "migrated", table.join(LOGS.migrating, {"[process] exit pid=75 status=0"})), "emulator.log"), {})
    if not state.migrated or not state.springboard then
        table.insert(found, "DataMigrator exiting cleanly after SpringBoard started is the golden image's milestone")
    end
end

local function home_step(emulator, folder, found)
    local rootfs = path.join(folder, "home-rootfs")
    os.mkdir(path.join(rootfs, "private", "var", "mobile"))
    os.mkdir(path.join(rootfs, "private", "var", "root", "Library", "Lockdown"))
    os.ln("private/var", path.join(rootfs, "var"))
    local ark = path.join(rootfs, "private", "var", "root", "Library", "Lockdown", "data_ark.plist")
    os.vrunv("plutil", {"-create", "binary1", ark})
    emulator.home(rootfs)
    local state = try {function () return os.iorunv("plutil", {"-extract", "com\\.apple\\.purplebuddy-SetupState", "raw", ark}):trim() end}
    if state ~= "DONE" then
        table.insert(found, "iOS 6.1 reads the setup state from lockdownd, expected DONE, read " .. tostring(state))
    end
    local plist = path.join(rootfs, "private", "var", "mobile", "Library", "Preferences", "com.apple.purplebuddy.plist")
    if not os.isfile(plist) then
        table.insert(found, "the home step writes com.apple.purplebuddy.plist under /private/var/mobile")
        return
    end
    for key, wanted in pairs({SetupDone = "true", SetupFinishedAllSteps = "true", SetupVersion = "2", AssistantPresented = "true"}) do
        local value = try {function () return os.iorunv("plutil", {"-extract", key, "raw", plist}):trim() end}
        if value ~= wanted then
            table.insert(found, string.format("the home step sets %s to %s, read %s", key, wanted, tostring(value)))
        end
    end
    local owner = try {function () return os.iorunv("xattr", {"-p", "hfsfuse.record.owner_id", plist}):trim() end}
    if owner ~= "501" then
        table.insert(found, "the purplebuddy preferences belong to mobile (501), read " .. tostring(owner))
    end
end

local function deb_step(emulator, debian, folder, found)
    local tree = path.join(folder, "deb-tree")
    os.mkdir(path.join(tree, "var", "mobile", "Library"))
    io.writefile(path.join(tree, "var", "mobile", "Library", "note.txt"), "through /var")
    os.mkdir(path.join(tree, "User"))
    io.writefile(path.join(tree, "User", "profile.txt"), "through an absolute link")
    os.mkdir(path.join(tree, "usr", "libexec"))
    io.writefile(path.join(tree, "usr", "libexec", "tool"), "#!/bin/sh\n")
    os.runv("chmod", {"755", path.join(tree, "usr", "libexec", "tool")})
    os.ln("tool", path.join(tree, "usr", "libexec", "alias"))
    local control = path.join(folder, "control")
    io.writefile(control, CONTROL)
    local deb = debian.write({control = control, version = "1.0", root = tree, outputdir = path.join(folder, "debs")})

    local rootfs = path.join(folder, "deb-rootfs")
    os.mkdir(path.join(rootfs, "private", "var", "mobile"))
    os.ln("private/var", path.join(rootfs, "var"))
    os.ln("/private/var/mobile", path.join(rootfs, "User"))
    emulator.install_deb(deb, rootfs)
    local through = path.join(rootfs, "private", "var", "mobile", "Library", "note.txt")
    if not os.isfile(through) or io.readfile(through) ~= "through /var" then
        table.insert(found, "a member under ./var lands in /private/var of the image, through its link")
    end
    local absolute = path.join(rootfs, "private", "var", "mobile", "profile.txt")
    if not os.isfile(absolute) then
        table.insert(found, "a member under an absolute link of the image (/User -> /private/var/mobile) lands inside the image")
    end
    if not os.isexec(path.join(rootfs, "usr", "libexec", "tool")) then
        table.insert(found, "an executable member keeps its mode")
    end
    local alias = path.join(rootfs, "usr", "libexec", "alias")
    if not os.islink(alias) or os.readlink(alias) ~= "tool" then
        table.insert(found, "a symbolic link member stays a link")
    end
    if os.isfile("/private/var/mobile/profile.txt") then
        table.insert(found, "installing a package wrote to the host's /private/var/mobile")
    end

    -- A package whose libraries depend on the release, like the backports, does
    -- its work in the maintainer script dpkg runs with DPKG_ROOT; the image is
    -- that root.
    local scripted = path.join(folder, "scripted")
    os.mkdir(path.join(scripted, "usr", "lib"))
    io.writefile(path.join(scripted, "usr", "lib", "carried.txt"), "carried")
    local scripts = path.join(folder, "scripts")
    os.mkdir(scripts)
    io.writefile(path.join(scripts, "postinst"),
                 '#!/bin/sh\nset -e\n[ "$1" = configure ] || exit 3\n' ..
                 'echo "root ${DPKG_ROOT}" > "${DPKG_ROOT}/usr/lib/configured.txt"\n')
    local script_deb = debian.write({control = control, version = "1.0", root = scripted,
                                     scripts = scripts,
                                     outputdir = path.join(folder, "scripted-debs")})
    emulator.install_deb(script_deb, rootfs)
    local configured = path.join(rootfs, "usr", "lib", "configured.txt")
    if not os.isfile(configured) or not io.readfile(configured):find(rootfs, 1, true) then
        table.insert(found, "the package's postinst runs against the image as its DPKG_ROOT")
    end

    local failing_scripts = path.join(folder, "failing-scripts")
    os.mkdir(failing_scripts)
    io.writefile(path.join(failing_scripts, "postinst"),
                 '#!/bin/sh\necho "no libraries for this release" >&2\nexit 1\n')
    local failing_deb = debian.write({control = control, version = "1.0", root = scripted,
                                      scripts = failing_scripts,
                                      outputdir = path.join(folder, "failing-debs")})
    local script_refusal = fixtures.refusal(function ()
        emulator.install_deb(failing_deb, rootfs)
    end)
    if not script_refusal or not script_refusal:find("no libraries for this release", 1, true) then
        table.insert(found, "a postinst that refuses the image stops the install and says why, said " ..
                            tostring(script_refusal))
    end
    local refused = fixtures.refusal(function ()
        io.writefile(path.join(folder, "not.deb"), "plain text")
        emulator.install_deb(path.join(folder, "not.deb"), rootfs)
    end)
    if not refused or not refused:find("not a Debian package", 1, true) then
        table.insert(found, "a file that is no ar archive must be refused: " .. tostring(refused))
    end
end

local function runner_job(emulator, folder, found)
    local task = emulator.runner_task({"/usr/libexec/tool", "a&b", "<x>", "two words", "'q\"x"}, 45)
    if task ~= "45\0/usr/libexec/tool\0a&b\0<x>\0two words\0'q\"x\0" then
        table.insert(found, "the runner's job holds the deadline and every argument verbatim, each ended by a NUL")
    end
    local launch = emulator.runner_launch()
    if launch ~= "bsexec .. /usr/libexec/charon-runner --job /private/var/charon/job\n" then
        table.insert(found, "launchd.conf starts the runner on its job file, in words launchctl splits on whitespace: " .. launch)
    end
    local job = path.join(folder, "job.plist")
    io.writefile(job, emulator.runner_job())
    if not try {function () os.vrunv("plutil", {"-lint", job}) return true end} then
        table.insert(found, "the runner's LaunchDaemon job is a well-formed property list")
        return
    end
    local listed = os.iorunv("plutil", {"-convert", "json", "-o", "-", job})
    if not listed:find('"--job"', 1, true) or not listed:find("private\\/var\\/charon\\/job", 1, true) then
        table.insert(found, "the runner's plist starts it on its job file: " .. listed)
    end
    for _, case in ipairs({{release = "6.1.3", conf = true}, {release = "3.0", conf = true}, {release = "7.1.2", conf = false}}) do
        local rootfs = path.join(folder, "rootfs-" .. case.release)
        local guest = path.join(folder, "guest")
        os.mkdir(path.join(guest, "usr", "libexec"))
        io.writefile(path.join(guest, "usr", "libexec", "charon-runner"), "")
        os.mkdir(path.join(rootfs, "private", "etc"))
        os.mkdir(path.join(rootfs, "System", "Library", "LaunchDaemons"))
        io.writefile(path.join(rootfs, "private", "etc", "launchd.conf"), "setenv TZ UTC")
        emulator.install_runner(rootfs, guest, {"/bin/true"}, 30, case.release)
        emulator.install_runner(rootfs, guest, {"/bin/true"}, 30, case.release)
        local conf = io.readfile(path.join(rootfs, "private", "etc", "launchd.conf"))
        local plist = os.isfile(path.join(rootfs, "System", "Library", "LaunchDaemons", "org.charon.emulator.runner.plist"))
        local expected = case.conf and "setenv TZ UTC\n" .. emulator.runner_launch() or "setenv TZ UTC"
        if conf ~= expected or plist == case.conf then
            table.insert(found, "iOS " .. case.release .. " starts the runner from " .. (case.conf and "launchd.conf, once, keeping what it held" or "its plist") .. ": " .. conf)
        end
    end
end

local function choice(emulator, found)
    local devices = {
        {identifier = "iPhone1,1", platform = "s5l8900x", firmwares = {{version = "3.1.3", build = "7E18"}}},
        {identifier = "iPhone2,1", platform = "s5l8920x", firmwares = {{version = "6.1.6", build = "10B500"}, {version = "5.0", build = "9A334"}}},
        {identifier = "iPhone3,1", platform = "s5l8930x", firmwares = {{version = "6.0", build = "10A403"}, {version = "7.1.2", build = "11D257"}}},
        {identifier = "iPad3,1", platform = "s5l8945x", firmwares = {{version = "6.0", build = "10A403"}}}
    }
    local emulated = {"iPhone1,1", "iPhone2,1", "iPhone3,1"}
    local chosen = emulator.choose(devices, emulated, {architecture = "armv7", release = "6.0"})
    if chosen.identifier ~= "iPhone2,1" or chosen.version ~= "6.1.6" then
        table.insert(found, string.format("armv7 6.0 goes to the first emulated armv7 device with a release not older, iPhone2,1 6.1.6, got %s %s", chosen.identifier, chosen.version))
    end
    chosen = emulator.choose(devices, emulated, {device = "iphone3,1", architecture = "armv7", release = "6.0"})
    if chosen.identifier ~= "iPhone3,1" or chosen.build ~= "10A403" then
        table.insert(found, "a named device takes its earliest release not older than the wanted one")
    end
    local refused = fixtures.refusal(function () emulator.choose(devices, emulated, {device = "iPad3,1", architecture = "armv7", release = "6.0"}) end)
    if not refused or not refused:find("no profile for iPad3,1", 1, true) then
        table.insert(found, "a device Shade has no profile for must be refused, not replaced by another: " .. tostring(refused))
    end
    refused = fixtures.refusal(function () emulator.choose(devices, emulated, {architecture = "armv7", release = "8.0"}) end)
    if not refused or not refused:find("release 8.0 or later", 1, true) then
        table.insert(found, "a release no emulated device runs must be refused: " .. tostring(refused))
    end
end

local function script(folder, name, body, modules)
    local file = path.join(folder, name .. ".lua")
    io.writefile(file, "function main(root, extra)\n    local emulator = import(\"emulator\", {rootdir = \"" .. path.translate(modules) .. "\", anonymous = true})\n" .. body .. "\nend\n")
    return file
end

local function spawned(files, arguments)
    runjobs("emulator-concurrency", function (index)
        local log = files[index] .. "." .. index .. ".log"
        os.execv(os.programfile(), table.join({"l", files[index]}, arguments[index]), {stdout = log, stderr = log, try = true})
    end, {total = #files, comax = #files})
end

local function load_step(emulator, found)
    for _, case in ipairs({{20.0, 12, true}, {3.0, 12, false}, {12.0, 12, false}, {nil, 12, false}, {5.0, nil, false}}) do
        if emulator.crowded(case[1], case[2]) ~= case[3] then
            table.insert(found, string.format("a load of %s on %s cores is %scrowded",
                                              tostring(case[1]), tostring(case[2]), case[3] and "" or "not "))
        end
    end
    local load = emulator.machine_load()
    if load ~= nil and (type(load) ~= "number" or load < 0) then
        table.insert(found, "the machine's load reads as a number or as nothing, read " .. tostring(load))
    end
    -- A build the queue already started carries its slot, and a build inside it
    -- must not wait for a second one.
    local marker = emulator.build_slot_name()
    if emulator.holds_build_slot({}) or not emulator.holds_build_slot({[marker] = "2"}) or
       emulator.holds_build_slot({[marker] = ""}) then
        table.insert(found, "a build carries its slot to the builds it starts, and only then")
    end
    if emulator.build_capacity() < 2 then
        table.insert(found, "a machine runs at least two builds at once, said " .. tostring(emulator.build_capacity()))
    end
    -- A slot is a share of the machine: what runs in it is told how much of it
    -- to take, and only when it is an xmake that would otherwise take all of it.
    if emulator.build_jobs(12, 3) ~= 4 or emulator.build_jobs(2, 3) ~= 1 or emulator.build_jobs(12, 0) ~= 12 then
        table.insert(found, string.format("three slots on twelve cores are four jobs each, said %d, %d and %d",
                                          emulator.build_jobs(12, 3), emulator.build_jobs(2, 3), emulator.build_jobs(12, 0)))
    end
    for _, case in ipairs({{{"xmake", {}}, "-j 4"},
                           {{"xmake", {"test", "suite/default"}}, "test suite/default -j 4"},
                           {{"xmake", {"build", "--", "-v"}}, "build -j 4 -- -v"},
                           {{"xmake", {"run", "port"}}, "run port"},
                           {{"xmake", {"f", "-y"}}, "f -y"},
                           {{"xmake", {"build", "-j8"}}, "build -j8"},
                           {{"/bin/sh", {"-c", "xmake"}}, "-c xmake"}}) do
        local given = table.concat(emulator.queued_arguments(case[1][1], case[1][2], 4), " ")
        if given ~= case[2] then
            table.insert(found, string.format("%s %s runs in a slot as %s, not %s", case[1][1], table.concat(case[1][2], " "), case[2], given))
        end
    end
    -- Patience of zero is how a test takes a slot without waiting for a quiet
    -- machine; it must still hand out the slot.
    local slot = emulator.acquire({folder = path.join(os.tmpdir(), "charon-slot-test-" .. os.getpid()), count = 1, patience = 0})
    if not slot then
        table.insert(found, "a run with no patience still takes a slot")
    else
        emulator.release(slot)
    end
end

local function concurrency(folder, modules, found)
    local root = path.join(folder, "emulator-root")
    local firmware = path.join(folder, "firmware-rootfs")
    os.mkdir(path.join(firmware, "System", "Library", "CoreServices"))
    io.writefile(path.join(firmware, "System", "Library", "CoreServices", "SystemVersion.plist"), "firmware")
    os.mkdir(path.join(firmware, "private", "var", "mobile"))
    local golden = script(folder, "golden", [[
    local rootfs = emulator.golden({root = root, identifier = "iPhone3,1", build = "10A403", ilemu_hash = "fixture", deadline = 30,
                                    firmware = extra, boot = function (opt)
        io.writefile(path.join(root, "boot-" .. os.getpid()), "booted")
        os.sleep(3000)
        return {reason = "reached", seconds = 3, state = {}, log = "none"}
    end})
    io.writefile(path.join(root, "result-" .. os.getpid()), rootfs)]], modules)
    os.mkdir(root)
    spawned({golden, golden}, {{root, firmware}, {root, firmware}})
    local boots = os.files(path.join(root, "boot-*"))
    local results = os.files(path.join(root, "result-*"))
    if #boots ~= 1 then
        table.insert(found, string.format("two processes preparing one golden image boot it once, booted %d times", #boots))
    end
    if #results ~= 2 then
        table.insert(found, "both processes preparing one golden image get it")
    else
        local first, second = io.readfile(results[1]), io.readfile(results[2])
        if first ~= second or not os.isfile(path.join(first, "System", "Library", "CoreServices", "SystemVersion.plist")) then
            table.insert(found, "both processes get the same complete golden image, got " .. first .. " and " .. second)
        end
    end
    if #os.dirs(path.join(root, "golden.noindex", "*.partial-*")) > 0 then
        table.insert(found, "a finished golden image leaves no partial folder behind")
    end

    local slots = path.join(folder, "slots")
    local holders = path.join(folder, "holders")
    os.mkdir(path.join(holders, "active"))
    local slot = script(folder, "slot", [[
    local taken = emulator.acquire({folder = root, count = 2})
    local marker = path.join(extra, "active", tostring(os.getpid()))
    io.writefile(marker, tostring(taken.index))
    io.writefile(path.join(extra, os.getpid() .. ".peak"), tostring(#os.files(path.join(extra, "active", "*"))))
    os.sleep(1500)
    os.rm(marker)
    emulator.release(taken)]], modules)
    spawned({slot, slot, slot, slot, slot}, {{slots, holders}, {slots, holders}, {slots, holders}, {slots, holders}, {slots, holders}})
    local peaks = os.files(path.join(holders, "*.peak"))
    if #peaks ~= 5 then
        table.insert(found, string.format("five processes waiting for two slots all get one, %d did", #peaks))
    end
    for _, peak in ipairs(peaks) do
        local holding = tonumber(io.readfile(peak))
        if holding > 2 then
            table.insert(found, string.format("two slots were held by %d processes at once", holding))
        end
    end
end

local function timing_and_reports(emulator, folder, found)
    local run = recorded(folder, "timed", LOGS.springboard,
                         {test = {path = "/usr/libexec/tool", spawned = 1, spawn_error = 0, timed_out = 0,
                                  seconds = 1.5, exit = 0}})
    local result = emulator.verdict(emulator.scan_file(path.join(run, "emulator.log"), {}),
                                    path.join(run, "results"), {scale = 10, host_seconds = 18.25})
    if result.guest_seconds ~= 1.5 or result.host_seconds ~= 18.25 or result.scale ~= 10 then
        table.insert(found, string.format("a verdict carries both clocks and the scale, read %s guest, %s host, scale %s",
                                          tostring(result.guest_seconds), tostring(result.host_seconds), tostring(result.scale)))
    end

    local rootfs = path.join(folder, "report-rootfs")
    local reports = path.join(rootfs, "private", "var", "logs", "CrashReporter")
    os.mkdir(reports)
    os.ln("private/var", path.join(rootfs, "var"))
    local description = table.concat({"Incident Identifier: 0", "Hardware Model:      iPhone4,1",
                                      "Exception Code:      0xbe18d1ee",
                                      "Reason:              mediaserverd: RPCTimeout message received to terminate [0] with reason 'InitializeSystemSoundPorts'"}, "\n")
    local report = path.join(reports, "SpringBoard-2026-09-17-131741.plist")
    io.writefile(report, "")
    os.vrunv("plutil", {"-create", "binary1", report})
    os.vrunv("plutil", {"-replace", "description", "-string", description, report})
    local collected = emulator.reports(rootfs)
    if #collected ~= 1 or collected[1].process ~= "SpringBoard" or
       not (collected[1].reason or ""):startswith("mediaserverd: RPCTimeout") then
        table.insert(found, "the guest's own report names the process and the reason it died")
        return
    end
    local unanswered = table.join(LOGS.looping, {
        "[mach] stalled pid=23 thread=1 request=118 reply-port=73216 object=477440 receive-owner=23 guest-seconds=45",
        "[mach] stalled pid=23 thread=4 request=404 reply-port=73217 object=477441 receive-owner=23 guest-seconds=12"})
    local blocked = emulator.verdict(emulator.scan_file(path.join(recorded(folder, "blocked", unanswered), "emulator.log"), {}),
                                     path.join(folder, "blocked", "results"), {reports = collected})
    local described = emulator.describe(blocked)
    if not described:find("mediaserverd: RPCTimeout", 1, true) then
        table.insert(found, "a blocked boot names the guest's own reason, said " .. described)
    end
    for _, case in ipairs({{"strict", 10, true}, {"strict", 1, false}, {"scaled", 10, false}, {nil, 10, false}}) do
        local refused = emulator.timing_refusal(case[1], case[2]) ~= nil
        if refused ~= case[3] then
            table.insert(found, string.format("a %s port at scale %d is %srefused",
                                              tostring(case[1]), case[2], case[3] and "" or "not "))
        end
    end
    -- A request the emulator never answers is a hole in the HLE, and a blocked
    -- boot says so instead of reading as a slow guest.
    if not blocked.gap or blocked.gap.request ~= 118 or blocked.gap.seconds ~= 45 or
       blocked.gap.process ~= "backboardd" or not described:find("reply to request 118", 1, true) then
        table.insert(found, "a blocked boot names the reply the guest waited for, said " .. described)
    end
end

-- The queue's plugin runs in xmake's sandbox, where a call the sandbox does not
-- hold is a crash on the way in and no command runs at all. Nothing catches
-- that but running it, so the test installs the repository as an addon in a
-- store of its own, with a Charon home of its own for the slots, and asks the
-- queue for a command that succeeds and one that fails.
local function queue_step(emulator, folder, opt, found)
    local work = path.join(folder, "queue")
    local envs = {XMAKE_GLOBALDIR = path.join(work, "store"), CHARON_HOME = path.join(work, "home")}
    os.mkdir(work)
    os.iorunv("xmake", {"addon", "--install", "-y", path.absolute(path.join(opt.modules, ".."))}, {curdir = work, envs = envs})
    -- A queue that already holds a slot passes it down and runs the command
    -- itself, and both ways have to answer with the status of what they ran.
    for _, held in ipairs({"", "1"}) do
        for _, case in ipairs({{"/usr/bin/true", 0}, {"/usr/bin/false", 1}}) do
            local code = os.execv("xmake", {"queue", "--", case[1]},
                                  {curdir = work, try = true,
                                   envs = table.join(envs, {[emulator.build_slot_name()] = held}),
                                   stdout = path.join(work, "queue.log"), stderr = path.join(work, "queue.log")})
            if code ~= case[2] then
                table.insert(found, string.format("the queue ends with the status of what it ran%s: %s answered %s, not %d, and said %s",
                                                  held == "" and "" or ", slot held", case[1], tostring(code), case[2],
                                                  (io.readfile(path.join(work, "queue.log")) or ""):trim()))
            end
        end
    end
end

-- An address in a backtrace is named by the image the guest says it loaded and
-- by the nearest symbol of the images the rootfs holds as files; what only the
-- shared cache holds is named by image and offset, and what no image covers
-- stays the number it is.
local function naming_step(emulator, found)
    local images = {{address = 0x4000, install = "/usr/libexec/port"}, {address = 0x33141000, install = "/usr/lib/libobjc.A.dylib"}}
    local symbols = {["/usr/libexec/port"] = {{address = 0x0, name = "_start"}, {address = 0x120, name = "_main"}}}
    for _, case in ipairs({{0x4124, "port`_main + 0x4"}, {0x4000, "port`_start + 0x0"},
                           {0x3314dfe8, "libobjc.A.dylib + 0xcfe8"}, {0x100, "0x00000100"}}) do
        local named = emulator.named_address(case[1], images, symbols)
        if named ~= case[2] then
            table.insert(found, string.format("0x%x is %s, not %s", case[1], case[2], named))
        end
    end
end

function failures(opt)
    local emulator = import("emulator", {rootdir = opt.modules, anonymous = true})
    local debian = import("debian", {rootdir = opt.modules, anonymous = true})
    local found = {}
    local folder = fixtures.scratch()
    verdicts(emulator, folder, found)
    home_step(emulator, folder, found)
    deb_step(emulator, debian, folder, found)
    runner_job(emulator, folder, found)
    timing_and_reports(emulator, folder, found)
    load_step(emulator, found)
    choice(emulator, found)
    concurrency(folder, opt.modules, found)
    queue_step(emulator, folder, opt, found)
    naming_step(emulator, found)
    os.tryrm(folder)
    return found
end
