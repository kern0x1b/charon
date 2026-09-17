add_repositories("charon ../..")
add_requires("ld64 956.6", "ldid 2.1.5-procursus7+23.gaf86971", "iphoneos-sdk 16.4", "llvm 23.1.1")
add_requires("swift 6.4.0", {system = false})

set_allowedplats("macosx")

local function suite(name)
    target(name)
        set_kind("phony")
        add_packages("ld64", "ldid", "iphoneos-sdk", "llvm", "swift")
        add_tests("default")
        on_test(function (target)
            local modules = path.join(os.projectdir(), "..", "..", "modules")
            local failures = import(target:name(), {rootdir = os.projectdir(), anonymous = true}).failures({
                modules = modules,
                ld64 = path.join(target:pkg("ld64"):installdir(), "bin", "ld"),
                ldid = path.join(target:pkg("ldid"):installdir(), "bin", "ldid"),
                clang = path.join(target:pkg("llvm"):installdir(), "bin", "clang"),
                swift = target:pkg("swift"):installdir(),
                sdk = os.dirs(path.join(target:pkg("iphoneos-sdk"):installdir(), "Developer.app", "Contents", "Developer", "Platforms",
                                        "iPhoneOS.platform", "Developer", "SDKs", "iPhoneOS*.sdk"))[1]
            })
            for _, failure in ipairs(failures) do
                cprint("${red}%s: %s", target:name(), failure)
            end
            return #failures == 0
        end)
    target_end()
end

suite("macho_test")
suite("dyld_test")
suite("debian_test")
suite("device_test")
suite("checks_test")
suite("blocks_test")
suite("weak_test")
suite("tls_test")
suite("atomics_test")
suite("swift_test")
suite("objc_test")
suite("carried_test")
suite("operators_test")
suite("backports_test")
