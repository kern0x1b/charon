local sdk = {name = "iphoneos-sdk", version = "16.4"}
local ld64 = {name = "ld64", version = "956.6"}
local ldid = {name = "ldid", version = "2.1.5-procursus7+23.gaf86971"}
local llvm = {name = "llvm", version = "23.1.1"}

for _, tool in ipairs({sdk, ld64, ldid, llvm}) do
    add_requires("charon@" .. tool.name .. " " .. tool.version, {alias = tool.name})
end

add_requires("charon@firmware-tools", {alias = "firmware-tools"})

add_requireconfs("**.m4", {system = false})
add_requireconfs("**.pkgconf", {system = false})

local minimum = get_config("apple_minimum")
if minimum then
    local root = path.join(os.scriptdir(), "..", "..")
    local digests = {}
    for _, file in ipairs({"toolchains/apple-ios/xmake.lua", "modules/apple/cmake.lua", "modules/apple/sources.lua", "modules/apple/deps.lua", "modules/apple/swift.lua"}) do
        table.insert(digests, file .. "=" .. hash.sha256(path.join(root, file)))
    end
    local toolchain = string.format("@addon/charon/apple-ios[minimum=%s,sdk=%s,ld64=%s,llvm=%s,optimize=packages,flags=%s]", minimum, sdk.version, ld64.version, llvm.version, hash.strhash128(table.concat(digests, ";")))
    add_requireconfs("*|" .. sdk.name .. "|" .. ld64.name .. "|" .. ldid.name .. "|" .. llvm.name .. "|firmware-tools|ilemu|swiftshader", {configs = {toolchains = toolchain}})
end
