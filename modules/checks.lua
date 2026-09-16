function pattern(glob)
    local escaped = glob:gsub("[%^%$%(%)%%%.%[%]%+%-]", "%%%0")
    escaped = escaped:gsub("%*%*/", "\001"):gsub("%*%*", "\002"):gsub("%*", "[^/]*"):gsub("%?", "[^/]")
    escaped = escaped:gsub("\001", ".-/?"):gsub("\002", ".*")
    return "^" .. escaped .. "$"
end

function matching(files, globs)
    local found = {}
    for _, file in ipairs(files) do
        for _, glob in ipairs(globs) do
            if file:match(pattern(glob)) then
                table.insert(found, file)
                break
            end
        end
    end
    return found
end

function changed(opt)
    local argv = opt.staged and {"diff", "--cached", "--name-only", "--diff-filter=ACMR"} or {"diff", "--name-only", "--diff-filter=ACMR", "HEAD"}
    local listed = os.iorunv("git", table.join({"-C", os.projectdir()}, argv))
    local files = {}
    for line in listed:gmatch("[^\n]+") do
        table.insert(files, line)
    end
    return files
end

function run(targets, opt)
    opt = opt or {}
    local files = (opt.staged or opt.changed) and changed(opt) or nil
    local failed, ran = {}, 0
    for _, target in ipairs(targets) do
        local command = table.wrap(target:values("check.command"))
        local globs = table.wrap(target:values("check.files"))
        local selected = files and (#globs > 0 and matching(files, globs) or files) or nil
        if not selected or #selected > 0 then
            local argv = table.slice(command, 2)
            if target:values("check.pass-files") and selected then
                table.join2(argv, selected)
            end
            ran = ran + 1
            local ok = try { function ()
                os.execv(command[1], argv, {curdir = os.projectdir()})
                return true
            end }
            if ok then
                cprint("${bright green}check${clear} %s", target:name())
            else
                cprint("${bright red}check${clear} %s failed", target:name())
                table.insert(failed, target:name())
            end
        end
    end
    return ran, failed
end
