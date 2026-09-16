local toolchain_packages = {
    sdk = {name = "iphoneos-sdk", version = "16.4"},
    ld64 = {name = "ld64", version = "956.6"}
}

local host_tools = {
    ldid = {name = "ldid", version = "2.1.5-procursus7+23.gaf86971"}
}

function apple_ios(opt)
    opt = opt or {}
    if not opt.minimum then
        raise("apple_ios() takes the oldest release the port runs on, e.g. apple_ios({minimum = \"6.0\"})")
    end
    local configs = {"minimum=" .. opt.minimum}
    for _, key in ipairs({"sdk", "ld64"}) do
        local package = toolchain_packages[key]
        local version = opt[key] or package.version
        add_requires("charon@" .. package.name .. " " .. version, {alias = package.name})
        table.insert(configs, key .. "=" .. version)
    end
    for key, tool in pairs(host_tools) do
        add_requires("charon@" .. tool.name .. " " .. (opt[key] or tool.version), {alias = tool.name})
    end
    set_toolchains("@addon/charon/apple-ios[" .. table.concat(configs, ",") .. "]")
    set_policy("package.requires_lock", true)
    set_policy("build.ccache", false)
    local mapped = "-ffile-prefix-map=" .. os.projectdir() .. "=/port"
    add_cxflags(mapped)
    add_mxflags(mapped)
    add_asflags(mapped)
    if opt.distribution then
        set_values("charon.distribution", opt.distribution)
    end
end
