set_project("charonmatterapp")
set_version("0.0.1")
-- The Matter cluster port as an installed application, launched through SpringBoard (xmake emulate launch): the library
-- is the apple-backports package with its matter config (libMatterClusterBackports.dylib), and the application looks
-- its classes up by name, so it names none of them at build time.
local root = os.getenv("CHARMATTER_ROOT") or path.join(os.scriptdir(), "../../../../..")
add_repositories("charon " .. root)
add_addons("charon v0.8.16")
set_config("apple_minimum", os.getenv("CHARMATTER_MINIMUM") or "6.1.3")
add_requires("charon@apple-backports", {alias = "apple-backports", configs = {matter = true}})
includes("@addon/charon/apple-ios")
includes("@addon/charon/emulate")
set_defaultplat("iphoneos")
set_defaultarchs("iphoneos|armv7")

target("charonmatterapp")
    add_rules("@addon/charon/app")
    add_files(path.join(root, "tests/backports/emulate/matter/app/main.m"))
    if os.getenv("CHARMATTER_RED") then
        add_defines("CHARON_MATTER_RED=1")
    end
    add_mflags("-fobjc-arc")
    add_ldflags("-fobjc-arc", {force = true})
    add_frameworks("Foundation", "UIKit")
    -- The package is built with its matter config, so the 6.1.3 band of the installed package carries the library the
    -- application loads by name (main.m, dlopen).
    add_packages("apple-backports")
    set_values("charon.libraries", "apple-backports")
    set_values("app.plist-file", "Info.plist")
    set_values("charon.control", "control")
