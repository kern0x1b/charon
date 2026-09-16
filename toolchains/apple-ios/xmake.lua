toolchain("apple-ios")
    set_kind("standalone")
    set_homepage("https://github.com/kern0x1b/charon")
    set_description("iPhoneOS through the command line tools' clang, an SDK package and, for armv7, cctools-port ld64")

    set_toolset("cc", "clang")
    set_toolset("cxx", "clang", "clang++")
    set_toolset("mm", "clang")
    set_toolset("mxx", "clang", "clang++")
    set_toolset("as", "clang")
    set_toolset("ld", "clang", "clang++")
    set_toolset("sh", "clang", "clang++")
    set_toolset("ar", "ar")
    set_toolset("strip", "strip")

    local function parts(toolchain, project)
        local required = project.required_packages() or {}
        local found = {}
        local sdk = required["iphoneos-sdk"]
        if sdk and toolchain:config("sdk") then
            found.sdk = sdk:installdir()
        end
        local ld64 = required["ld64"]
        if ld64 and toolchain:config("ld64") then
            found.linker = path.join(ld64:installdir(), "bin", "ld")
        end
        return found
    end

    on_check(function (toolchain)
        local found = parts(toolchain, import("core.project.project"))
        if not found.sdk or not toolchain:config("minimum") then
            return false
        end
        return not toolchain:is_arch("armv7", "armv7s") or found.linker ~= nil
    end)

    on_load(function (toolchain)
        import("core.base.semver")
        local found = parts(toolchain, import("core.project.project"))
        local declared = toolchain:config("minimum")
        if not found.sdk or not declared then
            raise("toolchain(apple-ios) needs the SDK package and apple_minimum; includes(\"@addon/charon/apple-ios\") provides both")
        end
        local floors = {armv7 = "6.0", armv7s = "6.0", arm64 = "7.0"}
        local floor = floors[toolchain:arch()]
        if not floor then
            raise("toolchain(apple-ios) builds armv7, armv7s and arm64, not %s", toolchain:arch())
        end
        local minimum = semver.compare(declared, floor) < 0 and floor or declared
        toolchain:config_set("sdkdir", found.sdk)
        toolchain:config_set("deployment", minimum)
        local target = {"-target", toolchain:arch() .. "-apple-ios" .. minimum, "-isysroot", found.sdk}
        local linked = table.join(target, found.linker and {"-fuse-ld=" .. found.linker} or {})
        toolchain:add("cxflags", target)
        toolchain:add("mxflags", target)
        toolchain:add("asflags", target)
        toolchain:add("ldflags", linked)
        toolchain:add("shflags", linked)
    end)
