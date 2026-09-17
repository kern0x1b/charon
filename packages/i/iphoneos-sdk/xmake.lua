package("iphoneos-sdk")
    set_kind("toolchain")
    set_homepage("https://github.com/theos/sdks")
    set_description("The iPhoneOS SDK a build compiles and links against, fetched and verified on the machine that uses it, laid out as an Xcode developer folder with what Xcode once shipped and dropped: Csu's startup objects and libgcc_s.1 in usr/lib, and libarclite in the toolchain")
    set_license("LicenseRef-Apple-SDK")

    add_urls("https://github.com/theos/sdks/releases/download/master-146e41f/iPhoneOS16.5.sdk.tar.xz")
    add_versions("16.4", "5e0fd3f01266cce4ce012d4a99b38eb56578fca40d09edc81cd83dee958202fb")
    add_patches("16.4", "patches/16.4-driverkit-22-availability.patch")
    add_resources("16.4", "csu", "https://github.com/apple-oss-distributions/Csu.git", "de2a331398a7d13a132a630bbf4d27c12b2466ec")
    add_deps("charon@ld64", {alias = "ld64"})

    add_configs("layout", {description = "The SDK sits in the package at Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS<version>.sdk, where clang's driver finds the toolchain's libarclite and CMake's iOS platform files the SDK name.", default = "developer-folder", type = "string", readonly = true})

    local digests = {}
    local inputs = table.join({path.join(os.scriptdir(), "xmake.lua")}, os.files(path.join(os.scriptdir(), "usr", "**")), os.files(path.join(os.scriptdir(), "arclite", "*")), os.files(path.join(os.scriptdir(), "blocks", "*")))
    table.sort(inputs)
    for _, file in ipairs(inputs) do
        table.insert(digests, path.relative(file, os.scriptdir()) .. "=" .. hash.sha256(file))
    end
    add_configs("additions", {description = "The digest of this recipe and the files it adds to the SDK, so a changed addition is a different package.", default = hash.strhash128(table.concat(digests, ";")), type = "string", readonly = true})

    on_install("@macosx", function (package)
        import("core.base.json")
        local settings = json.loadfile("SDKSettings.json")
        local wanted = "iphoneos" .. package:version_str()
        if settings.CanonicalName ~= wanted then
            raise("the archive describes itself as %s, not %s", tostring(settings.CanonicalName), wanted)
        end
        local developer = path.join(package:installdir(), "Developer.app", "Contents", "Developer")
        local folder = path.join(developer, "Platforms", "iPhoneOS.platform", "Developer", "SDKs", "iPhoneOS" .. package:version_str() .. ".sdk")
        os.mkdir(folder)
        os.vcp("*", folder .. "/")
        local libraries = path.join(folder, "usr", "lib")

        local extended = 0
        for _, stub in ipairs(os.files(path.join(libraries, "libSystem*.tbd"))) do
            local text, count = io.readfile(stub):gsub("'%$ld%$hide%$os3%.0%$([%w_]+)'", function (symbol)
                return string.format("'$ld$hide$os2.0$%s', '$ld$hide$os2.1$%s', '$ld$hide$os2.2$%s', '$ld$hide$os3.0$%s'", symbol, symbol, symbol, symbol)
            end)
            if count > 0 then
                io.writefile(stub, text)
                extended = extended + 1
            end
        end
        if extended == 0 then
            raise("no libSystem stub in %s hides anything from iOS 3.0, so none says which of its symbols older releases took from libgcc_s", libraries)
        end
        os.vcp(path.join(package:scriptdir(), "usr", "lib", "*"), libraries .. "/")

        local csu = package:resourcedir("csu")
        local linker = path.join(package:dep("ld64"):installdir("bin"), "ld")
        local objects = {
            {"crt1.o", "2.0", {"start.s", "crt.c", "dyld_glue.s"}, {"-DCRT"}},
            {"crt1.3.1.o", "3.1", {"start.s", "crt.c"}, {"-DADD_PROGRAM_VARS"}},
            {"dylib1.o", "2.0", {"dyld_glue.s"}, {"-DCFM_GLUE"}},
            {"bundle1.o", "2.0", {"dyld_glue.s"}, {}}
        }
        for _, object in ipairs(objects) do
            local slices = {}
            for _, architecture in ipairs({"armv6", "armv7", "armv7s"}) do
                local slice = path.absolute(architecture .. "-" .. object[1])
                local sources = {}
                for _, source in ipairs(object[3]) do
                    table.insert(sources, path.join(csu, source))
                end
                os.vrunv("xcrun", table.join({"clang", "-r", "-target", architecture .. "-apple-ios", "-miphoneos-version-min=" .. object[2],
                                              "-isysroot", folder, "-Os", "-nostdlib", "-Wl,-keep_private_externs", "-fuse-ld=" .. linker},
                                             object[4], sources, {"-o", slice}))
                table.insert(slices, slice)
            end
            os.vrunv("xcrun", table.join({"lipo", "-create"}, slices, {"-output", path.join(libraries, object[1])}))
        end

        local archives = {}
        for _, architecture in ipairs({"armv6", "armv7", "armv7s", "arm64"}) do
            local objects = {}
            for _, source in ipairs(os.files(path.join(package:scriptdir(), "arclite", "*.m"))) do
                local object = path.absolute(architecture .. "-" .. path.basename(source) .. ".o")
                os.vrunv("xcrun", {"clang", "-target", architecture .. "-apple-ios2.0", "-isysroot", folder, "-Os", "-fno-objc-arc",
                                   "-c", source, "-o", object})
                table.insert(objects, object)
            end
            local archive = path.absolute(architecture .. "-libarclite.a")
            os.vrunv("xcrun", table.join({"libtool", "-static", "-o", archive}, objects))
            table.insert(archives, archive)
        end
        local blocks = {}
        for _, architecture in ipairs({"armv6", "armv7"}) do
            local object = path.absolute(architecture .. "-BlocksRuntime.o")
            os.vrunv("xcrun", {"clang", "-target", architecture .. "-apple-ios2.0", "-isysroot", folder, "-Os", "-fno-objc-arc",
                               "-c", path.join(package:scriptdir(), "blocks", "BlocksRuntime.m"), "-o", object})
            local archive = path.absolute(architecture .. "-libBlocksRuntime.a")
            os.vrunv("xcrun", {"libtool", "-static", "-o", archive, object})
            table.insert(blocks, archive)
        end
        os.vrunv("xcrun", table.join({"lipo", "-create"}, blocks, {"-output", path.join(libraries, "libBlocksRuntime.a")}))

        local arc = path.join(developer, "Toolchains", "XcodeDefault.xctoolchain", "usr", "lib", "arc")
        os.mkdir(arc)
        os.vrunv("xcrun", table.join({"lipo", "-create"}, archives, {"-output", path.join(arc, "libarclite_iphoneos.a")}))
    end)

    on_test(function (package)
        local developer = path.join(package:installdir(), "Developer.app", "Contents", "Developer")
        local folder = path.join(developer, "Platforms", "iPhoneOS.platform", "Developer", "SDKs", "iPhoneOS" .. package:version_str() .. ".sdk")
        assert(os.isfile(path.join(developer, "Toolchains", "XcodeDefault.xctoolchain", "usr", "lib", "arc", "libarclite_iphoneos.a")))
        assert(os.isfile(path.join(folder, "usr", "include", "simd", "base.h")))
        for _, name in ipairs({"crt1.o", "crt1.3.1.o", "dylib1.o", "bundle1.o", "libgcc_s.1.tbd", "libBlocksRuntime.a"}) do
            assert(os.isfile(path.join(folder, "usr", "lib", name)))
        end
    end)
