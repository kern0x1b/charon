package("iphoneos-sdk")
    set_kind("toolchain")
    set_homepage("https://github.com/theos/sdks")
    set_description("The iPhoneOS SDK a build compiles and links against, fetched and verified on the machine that uses it")
    set_license("LicenseRef-Apple-SDK")

    add_urls("https://github.com/theos/sdks/releases/download/master-146e41f/iPhoneOS16.5.sdk.tar.xz")
    add_versions("16.4", "5e0fd3f01266cce4ce012d4a99b38eb56578fca40d09edc81cd83dee958202fb")
    add_patches("16.4", "patches/16.4-driverkit-22-availability.patch")

    on_install("@macosx", function (package)
        import("core.base.json")
        local settings = json.loadfile("SDKSettings.json")
        local wanted = "iphoneos" .. package:version_str()
        if settings.CanonicalName ~= wanted then
            raise("the archive describes itself as %s, not %s", tostring(settings.CanonicalName), wanted)
        end
        os.vcp("*", package:installdir())
    end)

    on_test(function (package)
        assert(os.isfile(path.join(package:installdir(), "usr", "include", "simd", "base.h")))
    end)
