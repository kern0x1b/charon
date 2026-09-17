package("csu")
    set_homepage("https://github.com/apple-oss-distributions/Csu")
    set_description("Apple's C startup objects - crt1.o, crt1.3.1.o, dylib1.o, bundle1.o - which a binary for a release before iOS 6 links and current SDKs no longer ship")
    set_license("APSL-2.0")
    set_policy("package.strict_compatibility", true)

    add_urls("https://github.com/apple-oss-distributions/Csu.git")
    add_versions("88", "de2a331398a7d13a132a630bbf4d27c12b2466ec")

    on_install("iphoneos", function (package)
        local toolchain = assert(package:toolchains(), "csu is built with the apple-ios toolchain")[1]
        toolchain:load()
        local base = {"-target", package:arch() .. "-apple-ios", "-isysroot", toolchain:config("sdkdir"), "-Os", "-nostdlib",
                      "-Wl,-keep_private_externs"}
        for _, flag in ipairs(table.wrap(toolchain:get("shflags"))) do
            if flag:startswith("-fuse-ld=") then
                table.insert(base, flag)
            end
        end
        local objects = {
            {"crt1.o", "2.0", {"start.s", "crt.c", "dyld_glue.s"}, {"-DCRT"}},
            {"crt1.3.1.o", "3.1", {"start.s", "crt.c"}, {"-DADD_PROGRAM_VARS"}},
            {"dylib1.o", "2.0", {"dyld_glue.s"}, {"-DCFM_GLUE"}},
            {"bundle1.o", "2.0", {"dyld_glue.s"}, {}}
        }
        for _, object in ipairs(objects) do
            os.vrunv("xcrun", table.join({"clang", "-r"}, base, {"-miphoneos-version-min=" .. object[2]}, object[3], object[4],
                                         {"-o", path.join(package:installdir("lib"), object[1])}))
        end
    end)

    on_test(function (package)
        for _, name in ipairs({"crt1.o", "crt1.3.1.o", "dylib1.o", "bundle1.o"}) do
            assert(os.isfile(path.join(package:installdir("lib"), name)))
        end
    end)
