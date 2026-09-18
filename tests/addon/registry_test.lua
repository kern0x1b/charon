-- The registry is what the backports say they carry, and the package build
-- refuses one that contradicts itself - after an hour of building. The suite
-- asks the registry of the repository the same question in a hundredth of a
-- second, so a duplicate entry is a failed test and not a failed release.
function failures(opt)
    local backports = import("apple.backports", {rootdir = opt.modules, anonymous = true})
    local found = {}
    local root = path.join(opt.modules, "..", "packages", "a", "apple-backports")
    if not os.isdir(path.join(root, "registry")) then
        table.insert(found, root .. " holds no registry to read")
        return found
    end
    local listed, incomplete = backports.registry(root)
    for index, complaint in ipairs(incomplete or {}) do
        if index <= 8 then
            table.insert(found, "the registry says: " .. complaint)
        end
    end
    if #(incomplete or {}) > 8 then
        table.insert(found, string.format("and %d more of the same", #incomplete - 8))
    end
    local named = 0
    for _ in pairs(listed or {}) do
        named = named + 1
    end
    if named == 0 then
        table.insert(found, "the registry of the repository names no API at all, which is not what it is for")
    end
    return found
end
