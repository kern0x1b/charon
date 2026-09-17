local sdk = {name = "iphoneos-sdk", version = "16.4"}
local ld64 = {name = "ld64", version = "956.6"}
local ldid = {name = "ldid", version = "2.1.5-procursus7+23.gaf86971"}

for _, tool in ipairs({sdk, ld64, ldid}) do
    add_requires("charon@" .. tool.name .. " " .. tool.version, {alias = tool.name})
end

add_requireconfs("**.m4", {system = false})
add_requireconfs("**.pkgconf", {system = false})

local minimum = get_config("apple_minimum")
if minimum then
    local function below(version)
        local have = {}
        for part in minimum:gmatch("%d+") do
            table.insert(have, tonumber(part))
        end
        local want = {}
        for part in version:gmatch("%d+") do
            table.insert(want, tonumber(part))
        end
        for index = 1, 3 do
            local a, b = have[index] or 0, want[index] or 0
            if a ~= b then
                return a < b
            end
        end
        return false
    end
    if below("7.0") then
        add_requires("charon@csu 88", {alias = "csu"})
    end
    if below("5.0") then
        add_requires("charon@compiler-rt 23.1.1", {alias = "compiler-rt"})
    end
    local toolchain = string.format("@addon/charon/apple-ios[minimum=%s,sdk=%s,ld64=%s,optimize=packages]", minimum, sdk.version, ld64.version)
    add_requireconfs("*|" .. sdk.name .. "|" .. ld64.name .. "|" .. ldid.name, {configs = {toolchains = toolchain}})
end
