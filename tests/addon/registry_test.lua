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
    wiring(backports, root, found)
    return found
end

-- The registry is checked against what the backports carry only when every library
-- is built, so a library that no config of the package builds keeps that check from
-- running for every config, and nothing says so. The recipe names each library in
-- the list of links and again in the list it builds, and each config in both.
function wiring(backports, root, found)
    local recipe = io.readfile(path.join(root, "xmake.lua"))
    local function count(text)
        local n, from = 0, 1
        while true do
            local at = recipe:find(text, from, true)
            if not at then
                return n
            end
            n = n + 1
            from = at + #text
        end
    end
    for _, library in ipairs(backports.libraries()) do
        if library.name ~= "FoundationBackports" and count('"' .. library.name .. '"') < 2 then
            table.insert(found, library.name .. " is named fewer than twice in the recipe of the package, so no config builds it and the registry is never checked against the backports")
        end
    end
    for name in recipe:gmatch('add_configs%("([%w]+)"') do
        if name ~= "sources" and count('package:config("' .. name .. '")') < 2 then
            table.insert(found, 'the config "' .. name .. '" is used fewer than twice in the recipe, so it builds no library, or does not link it')
        end
    end
end
