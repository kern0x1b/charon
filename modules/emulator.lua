import("core.base.json")
import("core.base.pipe")
import("core.base.process")
import("apple.dyld")
import("apple.firmware")

RESULTS = "private/var/charon"
REPORTS = "private/var/logs/CrashReporter"
RUNNER = "usr/libexec/charon-runner"
RUNNER_JOB = "System/Library/LaunchDaemons/org.charon.emulator.runner.plist"
MIGRATOR = "System/Library/PrivateFrameworks/DataMigration.framework/Support/DataMigrator"
SETUP_KEYS = {{"SetupDone", "-bool", "YES"}, {"SetupFinishedAllSteps", "-bool", "YES"}, {"SetupVersion", "-integer", "2"},
              {"AssistantPresented", "-bool", "YES"}}
CRASH_LOOP = 3
-- A guest second takes this many host seconds. The emulator is one to two
-- orders of magnitude slower than the device it emulates, so at 1 the guest's
-- own watchdogs and RPC deadlines expire before it finishes: iOS 6.1.3 loses
-- SpringBoard every 100 s to a mediaserverd RPC timeout and loses every app
-- backboardd's launch watchdog reaches. See README for the measurements.
TIME_SCALE = 10

function directory(folder)
    if not os.isdir(folder) then
        try {function () os.mkdir(folder) end}
    end
    if not os.isdir(folder) then
        raise("cannot create the folder %s", folder)
    end
    return folder
end

function remove(folder)
    if os.isdir(folder) or os.isfile(folder) or os.islink(folder) then
        os.execv("chmod", {"-R", "u+w", folder}, {try = true})
        os.tryrm(folder)
        if os.isdir(folder) then
            raise("cannot remove %s", folder)
        end
    end
end

function root()
    return path.join(path.directory(dyld.root()), "emulator")
end

function profiles(ilemu)
    local listed = {}
    for line in os.iorunv(ilemu, {"profile", "--list"}):gmatch("[^\n]+") do
        table.insert(listed, line:trim())
    end
    return listed
end

function kernels(ilemu)
    local known = {}
    for line in os.iorunv(ilemu, {"abi"}):gmatch("[^\n]+") do
        local name = line:match("^%s+(darwin%S+)$")
        if name then
            table.insert(known, name)
        end
    end
    return known
end

function kernel(ilemu, build)
    local output = try {function () return os.iorunv(ilemu, {"abi", "--ios-build", build}) end}
    return output and output:match("abi: (%S+)")
end

function choose(devices, emulated, opt)
    local known = {}
    for _, device in ipairs(devices) do
        known[device.identifier:lower()] = device
    end
    local candidates = {}
    if opt.device then
        local device = known[opt.device:lower()] or raise("the firmware catalog knows no device %s", opt.device)
        if not table.contains(emulated, device.identifier) then
            raise("iLEmu has no profile for %s; it emulates %s", device.identifier, table.concat(emulated, ", "))
        end
        candidates = {device}
    else
        for _, device in ipairs(devices) do
            if firmware.architecture(device.platform) == opt.architecture and table.contains(emulated, device.identifier) then
                table.insert(candidates, device)
            end
        end
    end
    for _, device in ipairs(candidates) do
        local chosen
        for _, candidate in ipairs(device.firmwares) do
            if dyld.compare_versions(candidate.version, opt.release) >= 0 and (not chosen or dyld.compare_versions(candidate.version, chosen.version) < 0) then
                chosen = candidate
            end
        end
        if chosen then
            return {identifier = device.identifier, version = chosen.version, build = chosen.build}
        end
    end
    if opt.device then
        raise("%s has no firmware of release %s or later in the catalog; pass -r with a release it runs", opt.device, opt.release)
    end
    raise("no device iLEmu emulates (%s) runs %s release %s or later; pass -d and -r", table.concat(emulated, ", "), opt.architecture, opt.release)
end

function guest_path(rootfs, relative, opt)
    opt = opt or {}
    local resolved = rootfs
    local pending = relative:split("/", {plain = true})
    local hops = 0
    local index = 1
    while index <= #pending do
        local part = pending[index]
        index = index + 1
        if part == ".." then
            if resolved ~= rootfs then
                resolved = path.directory(resolved)
            end
        elseif part ~= "" and part ~= "." then
            local candidate = path.join(resolved, part)
            if (index <= #pending or opt.follow) and os.islink(candidate) then
                hops = hops + 1
                if hops > 40 then
                    raise("%s loops through its symbolic links inside %s", relative, rootfs)
                end
                local link = os.readlink(candidate)
                local rest = table.slice(pending, index)
                pending = link:split("/", {plain = true})
                table.join2(pending, rest)
                index = 1
                if link:startswith("/") then
                    resolved = rootfs
                end
            else
                resolved = candidate
            end
        end
    end
    return resolved
end

function results(rootfs)
    return guest_path(rootfs, RESULTS)
end

function clone(source, destination)
    remove(destination)
    os.mkdir(path.directory(destination))
    os.vrunv("cp", {"-c", "-R", source, destination})
end

function home(rootfs)
    local preferences = guest_path(rootfs, "private/var/mobile/Library/Preferences")
    os.mkdir(preferences)
    for _, name in ipairs({"com.apple.purplebuddy", "com.apple.purplebuddy.notbackedup"}) do
        local file = path.join(preferences, name .. ".plist")
        if not os.isfile(file) then
            os.vrunv("plutil", {"-create", "binary1", file})
        end
        for _, key in ipairs(SETUP_KEYS) do
            os.vrunv("plutil", {"-replace", key[1], key[2], key[3], file})
        end
        os.vrunv("xattr", {"-w", "hfsfuse.record.owner_id", "501", file})
        os.vrunv("xattr", {"-w", "hfsfuse.record.group_id", "501", file})
    end
    -- iOS 6.1 asks lockdownd instead of the preferences above: SpringBoard
    -- reads com.apple.purplebuddy/SetupState, which Setup.app sets to DONE
    -- when it finishes. 6.0 reads the preferences, so both are written.
    local ark = guest_path(rootfs, "private/var/root/Library/Lockdown/data_ark.plist")
    if os.isfile(ark) then
        -- plutil reads a dot as a key-path separator, so the dots are escaped.
        os.vrunv("plutil", {"-replace", "com\\.apple\\.purplebuddy-SetupState", "-string", "DONE", ark})
        os.vrunv("xattr", {"-w", "hfsfuse.record.owner_id", "0", ark})
        os.vrunv("xattr", {"-w", "hfsfuse.record.group_id", "0", ark})
    end
end

-- The guest writes a report for every process it kills or that crashes, and
-- the report names the reason, which no emulator-side line can.
function reports(rootfs)
    local folder = guest_path(rootfs, REPORTS)
    local collected = {}
    for _, file in ipairs(os.files(path.join(folder, "*.plist"))) do
        local name = path.basename(file):match("^(.-)%-%d%d%d%d%-") or path.basename(file)
        local reason
        local printed = try {function () return os.iorunv("plutil", {"-extract", "description", "raw", "-o", "-", file}) end}
        for line in (printed or ""):gmatch("[^\n]+") do
            local named = line:match("^Reason:%s*(.+)$")
            if named then
                reason = named:trim()
                break
            end
        end
        table.insert(collected, {process = name, file = file, reason = reason})
    end
    table.sort(collected, function (left, right) return left.file < right.file end)
    return collected
end

local function ar_members(content, deb)
    if not content:startswith("!<arch>\n") then
        raise("%s is not a Debian package: it does not start with an ar header", deb)
    end
    local members, offset = {}, 8
    while offset + 60 <= #content do
        local header = content:sub(offset + 1, offset + 60)
        local name = header:sub(1, 16):trim():gsub("/$", "")
        local size = tonumber(header:sub(49, 58):trim())
        if not size then
            raise("%s has a damaged ar member header at byte %d", deb, offset)
        end
        members[name] = content:sub(offset + 61, offset + 60 + size)
        offset = offset + 60 + size + size % 2
    end
    return members
end

local function place(tree, rootfs)
    local entries = {}
    for _, entry in ipairs(os.filedirs(path.join(tree, "**"))) do
        table.insert(entries, path.relative(entry, tree))
    end
    table.sort(entries)
    for _, relative in ipairs(entries) do
        local source = path.join(tree, relative)
        local target = guest_path(rootfs, relative)
        if os.islink(source) then
            os.tryrm(target)
            os.mkdir(path.directory(target))
            os.ln(os.readlink(source), target)
        elseif os.isdir(source) then
            os.mkdir(guest_path(rootfs, relative, {follow = true}))
        else
            os.mkdir(path.directory(target))
            os.tryrm(target)
            os.vrunv("cp", {"-p", source, target})
        end
    end
end

function install_deb(deb, rootfs)
    local members = ar_members(io.readfile(deb, {encoding = "binary"}), deb)
    local data
    for name, content in pairs(members) do
        if name:startswith("data.tar") then
            data = {name = name, content = content}
        end
    end
    if not data then
        raise("%s has no data.tar member to install", deb)
    end
    local work = os.tmpfile() .. ".deb"
    os.mkdir(path.join(work, "tree"))
    local archive = path.join(work, data.name)
    io.writefile(archive, data.content, {encoding = "binary"})
    os.vrunv("tar", {"-xpf", archive, "-C", path.join(work, "tree")})
    place(path.join(work, "tree"), rootfs)
    remove(work)
end

local function escaped(text)
    return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function runner_job(argv, deadline)
    local arguments = {"<string>/" .. RUNNER .. "</string>", "<string>" .. tostring(deadline) .. "</string>"}
    for _, argument in ipairs(argv) do
        table.insert(arguments, "<string>" .. escaped(argument) .. "</string>")
    end
    return table.concat({
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
        '<plist version="1.0">',
        "<dict>",
        "<key>Label</key><string>org.charon.emulator.runner</string>",
        "<key>ProgramArguments</key><array>" .. table.concat(arguments) .. "</array>",
        "<key>RunAtLoad</key><true/>",
        "<key>LaunchOnlyOnce</key><true/>",
        "<key>StandardOutPath</key><string>/" .. RESULTS .. "/runner.stdout</string>",
        "<key>StandardErrorPath</key><string>/" .. RESULTS .. "/runner.stderr</string>",
        "</dict>",
        "</plist>",
        ""}, "\n")
end

function install_runner(rootfs, guest, argv, deadline)
    local runner = guest_path(rootfs, RUNNER)
    os.mkdir(path.directory(runner))
    os.vrunv("cp", {"-p", path.join(guest, RUNNER), runner})
    local job = guest_path(rootfs, RUNNER_JOB)
    io.writefile(job, runner_job(argv, deadline))
    local results = guest_path(rootfs, RESULTS)
    remove(results)
    os.mkdir(results)
    os.vrunv("chmod", {"0777", results})
end

function scan(state, line)
    state.lines = (state.lines or 0) + 1
    state.names = state.names or {}
    state.exits = state.exits or {}
    state.crashes = state.crashes or {}
    state.fatal = state.fatal or {}
    if line:startswith("[control] ready") then
        state.ready = true
    elseif line:startswith("[display] frame=") then
        state.frames = (state.frames or 0) + 1
    end
    local pid, program = line:match("^%[process%] spawn%-setexec pid=(%d+) parent=%d+ suspended=%d (%S+)")
    if not pid then
        pid, program = line:match("^%[process%] exec pid=(%d+) (/%S+)")
    end
    if not pid then
        pid, program = line:match("^%[process%] spawn parent=%d+ child=(%d+) suspended=%d (%S+)")
    end
    if pid then
        state.names[pid] = path.filename(program)
        if program:endswith("SpringBoard.app/SpringBoard") then
            state.springboard = true
        elseif program:endswith("/DataMigrator") then
            state.migrator = pid
        elseif program:endswith("/charon-runner") then
            state.runner = pid
        end
    end
    local exited, status = line:match("^%[process%] exit pid=(%d+) status=(%-?%d+)")
    if exited then
        local signal = tonumber(line:match(" signal=(%d+)")) or 0
        state.exits[exited] = {status = tonumber(status), signal = signal}
        if exited == state.migrator and signal == 0 then
            state.migrated = true
        end
        if signal ~= 0 then
            local name = state.names[exited] or exited
            state.crashes[name] = (state.crashes[name] or 0) + 1
        end
    end
    -- An IOKit request the emulator does not answer leaves the guest waiting
    -- for a reply that never comes, which is a hole in the HLE and not a slow
    -- guest; a blocked boot names the one it waited on most.
    local waiting, request = line:match("^%[iokit%] unhandled pid=(%d+) id=(%d+)")
    if waiting then
        state.unanswered = state.unanswered or {}
        local key = waiting .. " " .. request
        state.unanswered[key] = (state.unanswered[key] or 0) + 1
    end
    local faulted, pc = line:match("^%[cpu%] fatal pid=(%d+) cpu=%d+ pc=(0x%x+)")
    if faulted then
        state.fatal[faulted] = {pc = pc, line = line}
    end
    return state
end

function scan_file(file, state)
    state = state or {}
    if os.isfile(file) then
        for line in io.readfile(file, {encoding = "binary"}):gmatch("[^\n]+") do
            scan(state, line)
        end
    end
    return state
end

function crash_loop(state)
    local looping, most = nil, 0
    for name, count in pairs(state.crashes or {}) do
        if count >= CRASH_LOOP and count > most then
            looping, most = name, count
        end
    end
    return looping
end

function gap(state)
    local most, found = 0, nil
    for key, count in pairs(state.unanswered or {}) do
        if count > most then
            local pid, request = key:match("^(%d+) (%d+)$")
            most, found = count, {pid = pid, request = tonumber(request), count = count,
                                  process = (state.names or {})[pid] or pid}
        end
    end
    return found
end

function milestone(state)
    if not state.ready then
        return "emulator"
    end
    local looping = crash_loop(state)
    if looping then
        return looping
    end
    if not state.springboard then
        return "SpringBoard"
    end
    if state.migrator and not state.migrated then
        return "DataMigrator"
    end
    return "runner"
end

function verdict(state, results, opt)
    opt = opt or {}
    local file = path.join(results, "verdict.json")
    -- Guest seconds are the guest's own clock, which runs scale times slower
    -- than the host's; a test that measures time reads both and the scale.
    local timing = {scale = opt.scale or TIME_SCALE, host_seconds = opt.host_seconds, reports = opt.reports}
    if not os.isfile(file) then
        return table.join2({state = "boot-blocked", milestone = milestone(state), frame = opt.frame,
                            errors = opt.errors, gap = gap(state)}, timing)
    end
    local recorded = json.loadfile(file)
    local test = recorded.test or {}
    local result = table.join2({machine = recorded.machine, system = recorded.system,
                                guest_seconds = test.seconds, seconds = test.seconds,
                                stdout = path.join(results, "test.stdout"),
                                stderr = path.join(results, "test.stderr")}, timing)
    if test.spawned ~= 1 then
        result.state = "fail"
        result.spawn_error = test.spawn_error
    elseif test.timed_out == 1 then
        result.state = "timeout"
    elseif test.signal then
        result.state = "crash"
        result.signal = test.signal
        result.frame = opt.frame
        for pid, name in pairs(state.names or {}) do
            if state.fatal and state.fatal[pid] and path.filename(test.path or "") == name then
                result.pc = state.fatal[pid].pc
            end
        end
    elseif test.exit == 0 then
        result.state = "pass"
    else
        result.state = "fail"
        result.exit = test.exit
    end
    return result
end

function describe(result)
    local reported = ""
    for _, report in ipairs(result.reports or {}) do
        if report.reason then
            reported = string.format(", %s: %s", report.process, report.reason)
            break
        end
    end
    if result.state == "crash" then
        return string.format("crash(signal %d%s%s)", result.signal, result.pc and (", pc " .. result.pc) or "",
                             result.frame and (", last frame " .. result.frame) or "")
    elseif result.state == "fail" then
        return result.exit and string.format("fail(exit %d)", result.exit) or string.format("fail(spawn error %d)", result.spawn_error or 0)
    elseif result.state == "boot-blocked" then
        local waited = ""
        if result.gap then
            waited = string.format(", %s waited on IOKit request %d %d times the emulator did not answer",
                                   result.gap.process, result.gap.request, result.gap.count)
        end
        return string.format("boot-blocked(%s%s%s)", result.milestone, reported, waited)
    end
    return result.state
end

function boot(opt)
    local run = opt.run
    os.mkdir(run)
    local log = path.join(run, "emulator.log")
    local errors = path.join(run, "emulator.stderr")
    local frame = path.join(run, "frame.png")
    os.tryrm(log)
    os.tryrm(errors)
    local scale = opt.scale or TIME_SCALE
    local argv = {"boot", "--rootfs", opt.rootfs, "--device", opt.identifier, "--host-cache", opt.cache,
                  "--display", "headless", "--gles-backend", "software", "--control-stdin",
                  "--network", opt.network or "isolated", "--frame-output", frame,
                  "--time-scale", tostring(scale)}
    local input, control = pipe.openpair("BB")
    local envs = {}
    for name, value in pairs(table.join(os.getenvs(), {TMPDIR = opt.tmpdir, VK_ICD_FILENAMES = opt.icd})) do
        table.insert(envs, name .. "=" .. value)
    end
    directory(opt.tmpdir)
    directory(opt.cache)
    local started = os.mclock()
    local proc = process.openv(opt.ilemu, argv, {stdin = input, stdout = log, stderr = errors, envs = envs})
    input:close()
    local state, offset, reason = {}, 0, "deadline"
    local pending = ""
    while true do
        local ok = proc:wait(500)
        if os.isfile(log) then
            local handle = io.open(log, "rb")
            handle:seek("set", offset)
            local chunk = handle:read("a") or ""
            handle:close()
            offset = offset + #chunk
            pending = pending .. chunk
            for line in pending:gmatch("([^\n]*)\n") do
                scan(state, line)
            end
            pending = pending:match("([^\n]*)$") or ""
        end
        if ok ~= 0 then
            reason = "exited"
            break
        end
        if opt.stop and opt.stop(state) then
            reason = "reached"
            break
        end
        if os.mclock() - started > opt.deadline * 1000 then
            break
        end
    end
    if reason ~= "exited" then
        control:write("quit\n", {block = true})
        if proc:wait(30000) == 0 then
            proc:kill()
            proc:wait(5000)
        end
    end
    control:close()
    proc:close()
    state = scan_file(log, {})
    return {state = state, reason = reason, seconds = (os.mclock() - started) / 1000, scale = scale,
            log = log, errors = errors, frame = os.isfile(frame) and frame or nil}
end

function capacity()
    local cores = os.cpuinfo("ncpu")
    local gigabytes = os.meminfo("totalsize") // 1024
    return math.max(1, math.min(cores // 3, gigabytes // 5))
end

function acquire(opt)
    opt = opt or {}
    local folder = directory(opt.folder or path.join(root(), "slots"))
    local count = opt.count or capacity()
    local announced
    local started = os.mclock()
    while true do
        for index = 1, count do
            local lock = io.openlock(path.join(folder, string.format("slot-%d.lock", index)))
            if lock and lock:trylock() then
                return {index = index, lock = lock}
            end
            if lock then
                lock:close()
            end
        end
        if not announced or os.mclock() - announced > 30000 then
            cprint("all %d emulator slots of this machine are taken; waiting for one (%d s so far)", count, (os.mclock() - started) // 1000)
            announced = os.mclock()
        end
        os.sleep(1000)
    end
end

function release(slot)
    slot.lock:unlock()
    slot.lock:close()
end

function clone_golden(rootfs, destination)
    local lock = io.openlock(path.directory(rootfs) .. ".lock")
    lock:lock({shared = true})
    local ok, errors = try {function () clone(rootfs, destination) return true end, catch {function (caught) return false, caught end}}
    lock:unlock()
    lock:close()
    if not ok then
        raise(errors)
    end
end

function retire(parent, opt, kept)
    for _, marker in ipairs(os.files(path.join(parent, opt.identifier .. "_" .. opt.build .. "_*", "golden.json"))) do
        local folder = path.directory(marker)
        local recorded = try {function () return json.loadfile(marker) end}
        if path.filename(folder) ~= kept and recorded and recorded.ilemu ~= opt.ilemu_hash then
            local lock = io.openlock(folder .. ".lock")
            if lock and lock:trylock() then
                remove(folder)
                lock:unlock()
                lock:close()
                os.tryrm(folder .. ".lock")
            end
        end
    end
end

function clean(opt)
    local base = opt.root or root()
    local removed = {}
    for _, name in ipairs({"tmp.noindex", "cache.noindex"}) do
        local folder = path.join(base, name)
        if os.isdir(folder) then
            remove(folder)
            table.insert(removed, folder)
        end
    end
    for _, stale in ipairs(os.dirs(path.join(base, "golden.noindex", "*.partial-*"))) do
        remove(stale)
        table.insert(removed, stale)
    end
    for _, folder in ipairs(opt.images or {}) do
        if os.isdir(folder) then
            remove(folder)
            table.insert(removed, folder)
        end
    end
    if opt.goldens then
        for _, marker in ipairs(os.files(path.join(base, "golden.noindex", "*", "golden.json"))) do
            local folder = path.directory(marker)
            local lock = io.openlock(folder .. ".lock")
            if lock and lock:trylock() then
                remove(folder)
                table.insert(removed, folder)
                lock:unlock()
                lock:close()
                os.tryrm(folder .. ".lock")
            end
        end
    end
    return removed
end

function golden(opt)
    local key = string.format("%s_%s_%s", opt.identifier, opt.build, hash.strhash128(opt.ilemu_hash .. ";" .. table.concat(opt.steps or {"home"}, ";")))
    local parent = path.join(opt.root or root(), "golden.noindex")
    local folder = path.join(parent, key)
    local marker = path.join(folder, "golden.json")
    if os.isfile(marker) then
        return path.join(folder, "rootfs")
    end
    directory(parent)
    local lock = io.openlock(path.join(parent, key .. ".lock"))
    lock:lock()
    local ok, errors = try {
        function ()
            if os.isfile(marker) then
                return true
            end
            for _, stale in ipairs(os.dirs(path.join(parent, key .. ".partial-*"))) do
                remove(stale)
            end
            local staging = path.join(parent, key .. ".partial-" .. os.getpid())
            local rootfs = path.join(staging, "rootfs")
            clone(opt.firmware, rootfs)
            home(rootfs)
            local migrates = os.isfile(guest_path(rootfs, MIGRATOR))
            cprint("${bright}booting %s %s once past its first-boot migration${clear} for a golden image", opt.identifier, opt.build)
            local booted = opt.boot(table.join(opt, {rootfs = rootfs, run = staging, stop = function (state)
                return state.springboard and (state.migrated or not migrates)
            end}))
            if booted.reason ~= "reached" then
                raise("%s %s did not get past %s within %d seconds; the emulator log is %s", opt.identifier, opt.build,
                      milestone(booted.state), opt.deadline, booted.log)
            end
            json.savefile(path.join(staging, "golden.json"), {identifier = opt.identifier, build = opt.build, ilemu = opt.ilemu_hash, seconds = booted.seconds})
            remove(folder)
            os.mv(staging, folder)
            retire(parent, opt, key)
            return true
        end,
        catch {
            function (caught)
                return false, caught
            end
        }
    }
    lock:unlock()
    lock:close()
    if not ok then
        raise(errors)
    end
    return path.join(folder, "rootfs")
end
