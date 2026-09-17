package("apple-backports")
    set_homepage("https://github.com/kern0x1b/charon")
    set_description("Objective-C classes, methods and constants later iOS releases added, for a minimum release that lacks them, as libFoundationBackports.dylib and libUIKitBackports.dylib in /usr/lib/charon/org.charon.apple-backports, which re-export whatever the release already has")
    set_license("MIT")
    set_policy("package.strict_compatibility", true)

    add_deps("charon@firmware-tools", {alias = "firmware-tools"})

    local digests = {}
    local sources = table.join(os.files(path.join(os.scriptdir(), "*.c")), os.files(path.join(os.scriptdir(), "*", "*.m")),
                               {path.join(os.scriptdir(), "..", "..", "..", "modules", "apple", "backports.lua")})
    table.sort(sources)
    for _, file in ipairs(sources) do
        table.insert(digests, path.filename(file) .. "=" .. hash.sha256(file))
    end
    add_configs("sources", {description = "The digest of the sources and the build module, so a changed backport is a different package.", default = hash.strhash128(table.concat(digests, ";")), type = "string", readonly = true})

    add_configs("uikit", {description = "Build libUIKitBackports.dylib beside libFoundationBackports.dylib, for an application; a daemon or a tool leaves UIKit out of its process.", default = false, type = "boolean"})

    on_load("iphoneos", function (package)
        package:add("links", table.join(package:config("uikit") and {"UIKitBackports"} or {}, {"FoundationBackports"}))
    end)

    on_install("iphoneos", function (package)
        local modules = path.join(package:scriptdir(), "..", "..", "..", "modules")
        local backports = import("apple.backports", {rootdir = modules, anonymous = true})
        local firmware = import("apple.firmware", {rootdir = modules, anonymous = true})
        local toolchain = assert(package:toolchains(), "apple-backports is built with the apple-ios toolchain")[1]
        toolchain:load()
        local linker
        for _, flag in ipairs(table.wrap(toolchain:get("shflags"))) do
            linker = flag:match("^%-fuse%-ld=(.+)$") or linker
        end
        local deployment = toolchain:config("deployment")
        local cache = firmware.ensure(package:arch(), deployment, {tool = path.join(package:dep("firmware-tools"):installdir(), "bin", "charon-firmware")})
        backports.build({root = package:scriptdir(), architecture = package:arch(), deployment = deployment, cache = cache,
                         sdkdir = toolchain:config("sdkdir"), ld = assert(linker, "the apple-ios toolchain names no ld64 for " .. package:arch()),
                         builddir = path.absolute("backports"), outputdir = package:installdir("lib"),
                         libraries = package:config("uikit") and {"FoundationBackports", "UIKitBackports"} or {"FoundationBackports"}})
        os.vcp(path.join(package:scriptdir(), "..", "..", "..", "LICENSE"), package:installdir("licenses"))
    end)

    on_test(function (package)
        for _, name in ipairs(package:get("links")) do
            assert(os.isfile(path.join(package:installdir("lib"), "lib" .. name .. ".dylib")), name)
        end
    end)
