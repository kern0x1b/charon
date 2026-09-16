local sdk = {name = "iphoneos-sdk", version = "16.4"}
local ld64 = {name = "ld64", version = "956.6"}
local ldid = {name = "ldid", version = "2.1.5-procursus7+23.gaf86971"}

for _, tool in ipairs({sdk, ld64, ldid}) do
    add_requires("charon@" .. tool.name .. " " .. tool.version, {alias = tool.name})
end

add_requireconfs("**.m4", {system = false})

local minimum = get_config("apple_minimum")
if minimum then
    local toolchain = string.format("@addon/charon/apple-ios[minimum=%s,sdk=%s,ld64=%s,optimize=packages]", minimum, sdk.version, ld64.version)
    add_requireconfs("*|" .. sdk.name .. "|" .. ld64.name .. "|" .. ldid.name, {configs = {toolchains = toolchain}})
end
