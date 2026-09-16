import("core.base.option")
import("@self.device")
import("@self.packaging")

function main()
    local settings = device.bind(os.projectdir(), option.get("device"))
    local action = option.get("action")
    local arguments = table.concat(option.get("arguments") or {}, " ")
    if action == "where" then
        print(device.where(settings))
    elseif action == "run" then
        if arguments == "" then
            raise("xmake device run needs a command")
        end
        device.run(settings, arguments)
    elseif action == "log" then
        device.log(settings, tonumber(option.get("seconds")), arguments)
    elseif action == "install" then
        local refreshed = false
        local written_packages = packaging.write()
        local conflicts = {}
        for _, written in ipairs(written_packages) do
            table.join2(conflicts, device.identity_conflicts(settings, written.stage))
        end
        if #conflicts > 0 then
            raise(table.concat(conflicts, "; "))
        end
        for _, written in ipairs(written_packages) do
            local remote = "/tmp/" .. path.filename(written.deb)
            device.copy(settings, written.deb, remote)
            device.run(settings, string.format("dpkg -i %s && rm -f %s", remote, remote))
            cprint("${bright green}installed${clear} %s on %s", path.filename(written.deb), device.where(settings))
            refreshed = refreshed or os.isdir(path.join(written.stage, "Applications"))
        end
        if refreshed then
            device.run(settings, "su mobile -c uicache")
        end
    else
        raise("xmake device takes install, log, run or where")
    end
end
