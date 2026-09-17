import("core.base.option")
import("core.base.task")
import("core.project.config")
import("core.project.project")

function main()
    local firmware = import("apple.firmware", {rootdir = path.join(os.scriptdir(), "..", "..", "modules"), anonymous = true})
    local dyld = import("apple.dyld", {rootdir = path.join(os.scriptdir(), "..", "..", "modules"), anonymous = true})
    local action = option.get("action")
    if action == "list" then
        for _, folder in ipairs(os.dirs(path.join(dyld.root(), "*"))) do
            local held = {}
            for _, file in ipairs(os.filedirs(path.join(folder, "*"))) do
                local architecture = path.filename(file):match("^dyld_shared_cache_([%w_]+)$") or path.filename(file):match("^libraries_([%w_]+)$")
                if architecture then
                    table.insert(held, architecture)
                end
            end
            if #held > 0 then
                print("%s  %s", path.filename(folder), table.concat(held, " "))
            end
        end
        return
    end
    if action ~= "fetch" then
        raise("xmake firmware takes fetch or list, not %s", tostring(action))
    end
    local release = option.get("release") or raise("xmake firmware fetch needs the release")
    task.run("config", {}, {disable_dump = true})
    local architecture = option.get("arch") or config.arch()
    local tool = project.required_package("firmware-tools")
    if not tool then
        raise("the project requires no firmware-tools; includes(\"@addon/charon/apple-ios\") provides it")
    end
    local held, fetched = firmware.fetch(architecture, release, {tool = path.join(tool:installdir(), "bin", "charon-firmware")})
    cprint("${bright}%s${clear}: iOS %s for %s", held, fetched, architecture)
end
