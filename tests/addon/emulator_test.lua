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
    local refused = fixtures.refusal(function ()
        io.writefile(path.join(folder, "not.deb"), "plain text")
        emulator.install_deb(path.join(folder, "not.deb"), rootfs)
    end)
    if not refused or not refused:find("not a Debian package", 1, true) then
        table.insert(found, "a file that is no ar archive must be refused: " .. tostring(refused))
    end
end

local function runner_job(emulator, folder, found)
    local job = path.join(folder, "job.plist")
    io.writefile(job, emulator.runner_job({"/usr/libexec/tool", "a&b", "<x>"}, 45))
    if not try {function () os.vrunv("plutil", {"-lint", job}) return true end} then
        table.insert(found, "the runner's LaunchDaemon job is a well-formed property list")
        return
    end
    local listed = os.iorunv("plutil", {"-convert", "json", "-o", "-", job})
    if not listed:find('"a&b"', 1, true) or not listed:find('"<x>"', 1, true) or not listed:find('"45"', 1, true) then
        table.insert(found, "the runner job passes the deadline and every argument verbatim: " .. listed)
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
        table.insert(found, "a device iLEmu has no profile for must be refused, not replaced by another: " .. tostring(refused))
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
    local unanswered = table.join(LOGS.looping, {"[iokit] unhandled pid=23 id=118 remote-object=139776",
                                                "[iokit] unhandled pid=23 id=118 remote-object=139776",
                                                "[iokit] unhandled pid=23 id=404 remote-object=139776"})
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
    if not blocked.gap or blocked.gap.request ~= 118 or blocked.gap.count ~= 2 or
       blocked.gap.process ~= "backboardd" or not described:find("IOKit request 118", 1, true) then
        table.insert(found, "a blocked boot names the request the emulator left unanswered, said " .. described)
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
    choice(emulator, found)
    concurrency(folder, opt.modules, found)
    os.tryrm(folder)
    return found
end
