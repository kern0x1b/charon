import("core.base.option")
import("core.base.task")
import("core.project.project")
import("@self.checks")

function main()
    if option.get("install-hook") then
        local hooks = os.iorunv("git", {"-C", os.projectdir(), "rev-parse", "--git-path", "hooks"}):trim()
        hooks = path.absolute(hooks, os.projectdir())
        os.mkdir(hooks)
        local hook = path.join(hooks, "pre-commit")
        io.writefile(hook, "#!/bin/sh\nexec xmake check -P \"$(git rev-parse --show-toplevel)\" --staged\n")
        os.runv("chmod", {"755", hook})
        cprint("${bright green}hook${clear} %s", hook)
        return
    end
    task.run("config", {}, {disable_dump = true})
    local wanted = option.get("names")
    local targets = {}
    for _, target in ipairs(project.ordertargets()) do
        if target:rule("@addon/charon/check") or target:values("check.command") or target:values("check.script") then
            if not wanted or table.contains(wanted, target:name()) then
                table.insert(targets, target)
            end
        end
    end
    if #targets == 0 then
        raise("the project declares no check; a check is a target with add_rules(\"@addon/charon/check\") and set_values(\"check.command\", ...)")
    end
    local ran, failed = checks.run(targets, {staged = option.get("staged"), changed = option.get("changed")})
    if #failed > 0 then
        raise("%d of %d checks failed: %s", #failed, ran, table.concat(failed, ", "))
    end
    cprint("${bright green}%d checks passed", ran)
end
