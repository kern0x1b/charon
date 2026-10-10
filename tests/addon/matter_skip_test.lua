-- The host differential's skip list (tests/backports/host/matterdifferential/not-built.txt): the clusters that do not build
-- against the host's Matter. Pinned at the count the list holds, every entry has a reason, and every entry names a cluster
-- the generator wrote (packages/a/apple-backports/Matter/clusters-emitted.txt). Pure Lua: it reads two committed files and
-- runs no clang. A cluster that leaves or joins the list changes the pin, and that is a change to be made on purpose.
local pinned = 2

function failures(opt)
    local root = path.join(opt.modules, "..")
    local list = path.join(root, "tests", "backports", "host", "matterdifferential", "not-built.txt")
    local emitted = path.join(root, "packages", "a", "apple-backports", "Matter", "clusters-emitted.txt")
    local out = {}
    if not os.isfile(list) then
        return {"no skip list at " .. list}
    end
    if not os.isfile(emitted) then
        return {"no cluster list at " .. emitted .. ": the generator has not written the package"}
    end
    local written = {}
    for line in io.lines(emitted) do
        local name = line:match("^(%S+)")
        if name then written[name] = true end
    end
    local entries = {}
    for line in io.lines(list) do
        if not line:match("^%s*#") and not line:match("^%s*$") then
            local name = line:match("^(%S+)")
            local reason = line:match("^%S+%s+(.-)%s*$") or ""
            table.insert(entries, {name = name, reason = reason})
        end
    end
    if #entries ~= pinned then
        table.insert(out, "not-built.txt has " .. #entries .. " entries, pinned at " .. pinned)
    end
    for _, entry in ipairs(entries) do
        if not entry.reason or entry.reason == "" then
            table.insert(out, entry.name .. " has no reason in not-built.txt")
        end
        if not written[entry.name] then
            table.insert(out, entry.name .. " is not a cluster the generator wrote (clusters-emitted.txt)")
        end
    end
    return out
end
