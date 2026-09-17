add_repositories("charon ../..")
add_requires("ld64 956.6", "ldid 2.1.5-procursus7+23.gaf86971")

set_allowedplats("macosx")

local function suite(name)
    target(name)
        set_kind("phony")
        add_packages("ld64", "ldid")
        add_tests("default")
        on_test(function (target)
            local modules = path.join(os.projectdir(), "..", "..", "modules")
            local failures = import(target:name(), {rootdir = os.projectdir(), anonymous = true}).failures({
                modules = modules,
                ld64 = path.join(target:pkg("ld64"):installdir(), "bin", "ld"),
                ldid = path.join(target:pkg("ldid"):installdir(), "bin", "ldid")
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
