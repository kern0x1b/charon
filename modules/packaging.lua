import("core.base.task")
import("core.project.config")
import("core.project.project")
import("debian")

function packages()
    local grouped = {}
    for _, target in ipairs(project.ordertargets()) do
        local control = target:values("charon.control")
        if control then
            control = path.absolute(control, target:scriptdir())
            grouped[control] = grouped[control] or {targets = {}, scripts = nil}
            table.insert(grouped[control].targets, target)
            local scripts = target:values("charon.maintainer-scripts")
            if scripts then
                grouped[control].scripts = path.absolute(scripts, target:scriptdir())
            end
        end
    end
    return grouped
end

function write(opt)
    opt = opt or {}
    task.run("config", {}, {disable_dump = true})
    local version = project.version()
    if not version then
        raise("the project has no set_version(), and a Debian package cannot be written without one")
    end
    local written = {}
    local grouped = packages()
    for _, control in ipairs(table.orderkeys(grouped)) do
        local described = grouped[control]
        local wanted = not opt.target
        for _, target in ipairs(described.targets) do
            wanted = wanted or target:name() == opt.target
        end
        if wanted then
            local stage = path.join(config.builddir(), ".charon", "stage", path.basename(control))
            os.tryrm(stage)
            for _, target in ipairs(described.targets) do
                task.run("build", {target = target:name()})
                task.run("install", {target = target:name(), installdir = stage})
            end
            local output = debian.write({control = control, version = version, root = stage,
                                         scripts = described.scripts,
                                         outputdir = opt.outputdir or config.builddir()})
            cprint("${bright green}deb${clear} %s", output)
            table.insert(written, {deb = output, stage = stage})
        end
    end
    if #written == 0 then
        raise("no target names a control file with set_values(\"charon.control\", ...), so there is no package to write")
    end
    return written
end
