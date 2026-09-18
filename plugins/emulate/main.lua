import("core.base.json")
import("core.base.option")
import("core.base.task")
import("core.project.config")
import("core.project.project")
import("@self.emulator")
import("@self.packaging")
import("@self.apple.firmware")

local function required(name)
    local package = project.required_package(name)
    if not package then
        raise("the project requires no %s; add includes(\"@addon/charon/emulate\") after includes(\"@addon/charon/apple-ios\")", name)
    end
    return package
end

-- A target says with emulate.timing = "strict" that it measures time itself.
local function timing()
    for _, target in pairs(project.targets()) do
        local value = target:values("emulate.timing")
        if value then
            return value
        end
    end
    return "scaled"
end

local function network()
    if option.get("network") then
        return option.get("network")
    end
    for _, target in pairs(project.targets()) do
        local value = target:values("emulate.network")
        if value then
            return value
        end
    end
    return "isolated"
end

local function context()
    if not is_host("macosx") or os.arch() ~= "arm64" then
        raise("xmake emulate runs on macOS arm64 hosts only, and this is %s %s", os.host(), os.arch())
    end
    task.run("config", {}, {disable_dump = true})
    local ilemu = required("ilemu")
    local guest = required("emulator-guest")
    local swiftshader = required("swiftshader")
    local tool = path.join(required("firmware-tools"):installdir(), "bin", "charon-firmware")
    local program = path.join(ilemu:installdir(), "bin", "ilemu")
    local release = option.get("release") or config.get("apple_minimum") or raise("xmake emulate needs -r RELEASE or set_config(\"apple_minimum\", ...)")
    local chosen = emulator.choose(firmware.catalog().devices, emulator.profiles(program),
                                   {device = option.get("device"), architecture = config.arch(), release = release})
    if not emulator.kernel(program, chosen.build) then
        raise("iLEmu emulates no Darwin kernel for %s iOS %s (%s); it has %s", chosen.identifier, chosen.version, chosen.build,
              table.concat(emulator.kernels(program), ", "))
    end
    local owner = (project.name() or path.filename(os.projectdir())) .. "-" .. hash.strhash32(os.projectdir())
    local image = path.join(emulator.root(), "images.noindex", owner, chosen.identifier .. "_" .. chosen.build)
    return {ilemu = program, ilemu_hash = path.filename(ilemu:installdir()), guest = guest:installdir(), tool = tool,
            icd = path.join(swiftshader:installdir(), "share", "vulkan", "icd.d", "vk_swiftshader_icd.json"),
            identifier = chosen.identifier, version = chosen.version, build = chosen.build, image = image,
            deadline = tonumber(option.get("timeout")), network = network()}
end

local function booter(ctx)
    return function (opt)
        local slot = emulator.acquire()
        local ok, result = try {
            function ()
                return true, emulator.boot(table.join(opt, {
                    scale = tonumber(option.get("scale")) or emulator.TIME_SCALE,
                    cache = path.join(emulator.root(), "cache.noindex", ctx.identifier .. "_" .. ctx.build, "slot-" .. slot.index),
                    tmpdir = path.join(emulator.root(), "tmp.noindex")}))
            end,
            catch {
                function (errors)
                    return false, errors
                end
            }
        }
        emulator.release(slot)
        if not ok then
            raise(result)
        end
        return result
    end
end

local function golden(ctx)
    local firmware_rootfs = firmware.rootfs(ctx.identifier, ctx.version, {tool = ctx.tool})
    return emulator.golden(table.join(ctx, {firmware = firmware_rootfs, boot = booter(ctx)}))
end

local function install(ctx)
    local written = packaging.write()
    local base = golden(ctx)
    local rootfs = path.join(ctx.image, "rootfs")
    emulator.clone_golden(base, rootfs)
    for _, package in ipairs(written) do
        emulator.install_deb(package.deb, rootfs)
        cprint("${bright green}installed${clear} %s into %s %s", path.filename(package.deb), ctx.identifier, ctx.version)
    end
    json.savefile(path.join(ctx.image, "image.json"), {identifier = ctx.identifier, version = ctx.version, build = ctx.build,
                                                        packages = table.imap(written, function (_, item) return path.filename(item.deb) end)})
end

local function run(ctx, argv)
    local refusal = emulator.timing_refusal(timing(), tonumber(option.get("scale")) or emulator.TIME_SCALE)
    if refusal then
        raise(refusal)
    end
    local image = path.join(ctx.image, "rootfs")
    if not os.isdir(image) then
        raise("%s %s has no image yet; run xmake emulate install first", ctx.identifier, ctx.version)
    end
    local folder = path.join(ctx.image, "run")
    emulator.remove(folder)
    local rootfs = path.join(folder, "rootfs")
    emulator.clone(image, rootfs)
    local seconds = tonumber(option.get("seconds"))
    emulator.install_runner(rootfs, ctx.guest, argv, seconds)
    local results = emulator.results(rootfs)
    local booted = booter(ctx)(table.join(ctx, {rootfs = rootfs, run = folder, stop = function ()
        return os.isfile(path.join(results, "verdict.json"))
    end}))
    local reports = emulator.reports(rootfs)
    local result = emulator.verdict(booted.state, results, {frame = booted.frame, errors = booted.errors,
                                                            scale = booted.scale, host_seconds = booted.seconds,
                                                            reports = reports})
    os.cp(results, path.join(folder, "results"))
    for _, report in ipairs(reports) do
        os.cp(report.file, path.join(folder, "results", "reports", path.filename(report.file)))
        report.file = path.join(folder, "results", "reports", path.filename(report.file))
    end
    result.stdout = path.join(folder, "results", "test.stdout")
    result.stderr = path.join(folder, "results", "test.stderr")
    json.savefile(path.join(folder, "verdict.json"), table.join(result, {reason = booted.reason, seconds = booted.seconds}))
    if not option.get("keep") then
        emulator.remove(rootfs)
        emulator.remove(path.join(folder, "runtime"))
        emulator.remove(path.join(folder, ".ilemu-device-state"))
    end
    for _, name in ipairs({"test.stdout", "test.stderr"}) do
        local file = path.join(folder, "results", name)
        if os.isfile(file) and os.filesize(file) > 0 then
            io.write(io.readfile(file))
        end
    end
    local described = emulator.describe(result)
    -- Both clocks are named whatever the outcome, so a run is never read as
    -- fast or slow without the scale that produced it.
    local timing = string.format("%.1f guest s / %.1f host s at time scale %s",
                                 result.guest_seconds or 0, result.host_seconds or 0, result.scale)
    if result.state == "pass" then
        cprint("${bright green}%s${clear} on %s %s (%s) in %s", described, ctx.identifier, ctx.version,
               ctx.build, timing)
    else
        raise("%s on %s %s (%s) in %s; the emulator log is %s", described, ctx.identifier, ctx.version,
              ctx.build, timing, booted.log)
    end
end

local function log(ctx, text)
    local results = path.join(ctx.image, "run", "results")
    for _, name in ipairs({"test.stdout", "test.stderr", "runner.stdout", "runner.stderr"}) do
        local file = path.join(results, name)
        if os.isfile(file) then
            for line in io.readfile(file):gmatch("[^\n]+") do
                if text == "" or line:find(text, 1, true) then
                    print("%s: %s", name, line)
                end
            end
        end
    end
    local emulated = path.join(ctx.image, "run", "emulator.log")
    if os.isfile(emulated) then
        for line in io.readfile(emulated, {encoding = "binary"}):gmatch("[^\n]+") do
            local wanted = text ~= "" and line:find(text, 1, true)
            wanted = wanted or (text == "" and (line:startswith("[cpu] fatal") or line:match("^%[process%] exit .*signal=[1-9]")))
            if wanted then
                print("emulator: %s", line)
            end
        end
    end
end

-- The program is started as the guest's first process and stopped where it
-- crashes, and what the debugger reads is printed as it is read: the signal,
-- the frames named by the images the guest says it loaded, and the registers.
local function debug_command(ctx, command)
    local image = path.join(ctx.image, "rootfs")
    if not os.isdir(image) then
        raise("%s %s has no image yet; run xmake emulate install first", ctx.identifier, ctx.version)
    end
    local folder = path.join(ctx.image, "debug")
    emulator.remove(folder)
    local rootfs = path.join(folder, "rootfs")
    emulator.clone(image, rootfs)
    local slot = emulator.acquire()
    local report = try {
        function ()
            return emulator.debugged(table.join(ctx, {rootfs = rootfs, run = folder, guest = command,
                                                      architecture = config.arch(), network = network(),
                                                      cache = path.join(emulator.root(), "cache.noindex", ctx.identifier .. "_" .. ctx.build, "slot-" .. slot.index),
                                                      tmpdir = path.join(emulator.root(), "tmp.noindex")}))
        end,
        catch {
            function (errors)
                emulator.release(slot)
                raise(errors)
            end
        }
    }
    emulator.release(slot)
    json.savefile(path.join(folder, "debug.json"), report)
    if report.exited then
        cprint("${bright}%s${clear} ran to its own exit %d on %s %s (%s), with nothing to debug", command, report.exited,
               ctx.identifier, ctx.version, ctx.build)
        return
    end
    cprint("${bright}%s${clear} stopped with signal %d on %s %s (%s)", command, report.signal, ctx.identifier, ctx.version, ctx.build)
    for index, frame in ipairs(report.frames) do
        cprint("  #%-2d %-6s 0x%08x  %s", index - 1, frame.kind, frame.address, frame.name)
    end
    local told = {}
    for _, name in ipairs(emulator.REGISTERS or {}) do
        table.insert(told, string.format("%s=0x%08x", name, report.registers[name] or 0))
    end
    if #told > 0 then
        print(table.concat(told, " "))
    end
    cprint("${dim}%d images loaded; the report is %s and the emulator log is %s", #report.images,
           path.join(folder, "debug.json"), report.log)
end

function main()
    local action = option.get("action")
    local arguments = option.get("arguments") or {}
    if action ~= "install" and action ~= "run" and action ~= "debug" and action ~= "log" and action ~= "shot" and action ~= "clean" then
        raise("xmake emulate takes install, run, debug, log, shot or clean")
    end
    if action == "clean" then
        local owner = (project.name() or path.filename(os.projectdir())) .. "-" .. hash.strhash32(os.projectdir())
        local removed = emulator.clean({images = option.get("all") and os.dirs(path.join(emulator.root(), "images.noindex", "*")) or {path.join(emulator.root(), "images.noindex", owner)},
                                        goldens = option.get("all")})
        for _, folder in ipairs(removed) do
            cprint("${bright}removed${clear} %s", folder)
        end
        return
    end
    local ctx = context()
    emulator.directory(path.directory(ctx.image))
    local lock = io.openlock(ctx.image .. ".lock")
    if not lock:trylock() then
        cprint("another xmake emulate is using %s %s of this port; waiting for it", ctx.identifier, ctx.version)
        lock:lock()
    end
    if action == "install" then
        install(ctx)
    elseif action == "run" then
        if #arguments == 0 then
            raise("xmake emulate run needs a command")
        end
        run(ctx, arguments)
    elseif action == "debug" then
        if #arguments == 0 then
            raise("xmake emulate debug needs the command to start under the debugger")
        end
        debug_command(ctx, arguments[1])
    elseif action == "log" then
        log(ctx, table.concat(arguments, " "))
    else
        local frame = path.join(ctx.image, "run", "frame.png")
        if not os.isfile(frame) then
            raise("%s %s has no frame yet; xmake emulate run leaves one", ctx.identifier, ctx.version)
        end
        local output = arguments[1] or path.join(config.builddir(), ctx.identifier .. "_" .. ctx.build .. ".png")
        os.cp(frame, output)
        print(output)
    end
end
