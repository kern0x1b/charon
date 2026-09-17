package("apple-backports")
    set_homepage("https://github.com/kern0x1b/charon")
    set_description("Objective-C classes, methods and constants later iOS releases added, for a minimum release that lacks them, as libFoundationBackports.dylib and libUIKitBackports.dylib in /usr/lib/charon/org.charon.apple-backports, which re-export whatever the release already has")
    set_license("MIT")
    set_policy("package.strict_compatibility", true)

    add_deps("charon@firmware-tools", {alias = "firmware-tools"})
    add_deps("charon@ldid 2.1.5-procursus7+23.gaf86971", {alias = "ldid"})

    local digests = {}
    local sources = table.join(os.files(path.join(os.scriptdir(), "*.c")), os.files(path.join(os.scriptdir(), "*", "*.m")),
                               {path.join(os.scriptdir(), "..", "..", "..", "modules", "apple", "backports.lua"),
                                path.join(os.scriptdir(), "..", "..", "..", "addons", "c", "charon", "xmake.lua")})
    table.sort(sources)
    for _, file in ipairs(sources) do
        table.insert(digests, path.filename(file) .. "=" .. hash.sha256(file))
    end
    add_configs("sources", {description = "The digest of the sources, the build module and the Charon releases, so a changed backport or a new release is a different package.", default = hash.strhash128(table.concat(digests, ";")), type = "string", readonly = true})

    add_configs("uikit", {description = "Build libUIKitBackports.dylib beside libFoundationBackports.dylib, for an application; a daemon or a tool leaves UIKit out of its process.", default = false, type = "boolean"})
    add_configs("corelocation", {description = "Build libCoreLocationBackports.dylib, for a port that asks for location authorization; it loads CoreLocation into the process.", default = false, type = "boolean"})

    on_load("iphoneos", function (package)
        package:add("links", table.join(package:config("uikit") and {"UIKitBackports"} or {}, package:config("corelocation") and {"CoreLocationBackports"} or {}, {"FoundationBackports"}))
    end)

    on_install("iphoneos", function (package)
        local modules = path.join(package:scriptdir(), "..", "..", "..", "modules")
        local backports = import("apple.backports", {rootdir = modules, anonymous = true})
        local firmware = import("apple.firmware", {rootdir = modules, anonymous = true})
        local dyld = import("apple.dyld", {rootdir = modules, anonymous = true})
        local toolchain = assert(package:toolchains(), "apple-backports is built with the apple-ios toolchain")[1]
        toolchain:load()
        local linker
        for _, flag in ipairs(table.wrap(toolchain:get("shflags"))) do
            linker = flag:match("^%-fuse%-ld=(.+)$") or linker
        end
        local deployment = toolchain:config("deployment")
        local tool = path.join(package:dep("firmware-tools"):installdir(), "bin", "charon-firmware")
        local cache = firmware.ensure(package:arch(), deployment, {tool = tool})
        local common = {root = package:scriptdir(), architecture = package:arch(), deployment = deployment, sdkdir = toolchain:config("sdkdir"),
                        cc = assert(toolchain:tool("cc"), "the apple-ios toolchain names no compiler for " .. package:arch()),
                        ld = assert(linker, "the apple-ios toolchain names no ld64 for " .. package:arch())}
        backports.build(table.join(common, {cache = cache, builddir = path.absolute("link"), outputdir = package:installdir("lib"),
                                            libraries = table.join({"FoundationBackports"}, package:config("uikit") and {"UIKitBackports"} or {},
                                                                    package:config("corelocation") and {"CoreLocationBackports"} or {})}))
        local released
        for version in io.readfile(path.join(package:scriptdir(), "..", "..", "..", "addons", "c", "charon", "xmake.lua")):gmatch('add_versions%("v(%d[%d%.]*)"') do
            if not released or dyld.compare_versions(version, released) > 0 then
                released = version
            end
        end
        backports.write_deb(table.join(common, {tool = tool, builddir = path.absolute("bands"),
                                                ldid = path.join(package:dep("ldid"):installdir(), "bin", "ldid"),
                                                version = assert(released, "the addon recipe names no Charon release") .. "+" .. package:config("sources"):sub(1, 8),
                                                outputdir = package:installdir("share")}))
        os.vcp(path.join(package:scriptdir(), "registry"), package:installdir("share"))
        os.vcp(path.join(package:scriptdir(), "..", "..", "..", "LICENSE"), package:installdir("licenses"))
    end)

    on_test(function (package)
        for _, name in ipairs(package:get("links")) do
            assert(os.isfile(path.join(package:installdir("lib"), "lib" .. name .. ".dylib")), name)
        end
        assert(#os.files(path.join(package:installdir("share"), "org.charon.apple-backports_*.deb")) == 1)
    end)
