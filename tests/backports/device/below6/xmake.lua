set_project("below6")
set_version("0.0.1")
-- The working copy under test, named by run.sh (BELOW6_ROOT); the addon is the tag already in the store (charon/AGENTS.md, Traps: a
-- working copy is never installed as the addon).
local root = os.getenv("BELOW6_ROOT") or path.join(os.scriptdir(), "../../../..")
add_repositories("charon " .. root)
add_addons("charon v0.8.12")
-- One binary for every release it runs on, built for the lowest.
set_config("apple_minimum", "4.3")
add_requires("charon@apple-backports", {alias = "apple-backports", configs = {uikit = os.getenv("BELOW6_UIKIT") == "1"}})
includes("@addon/charon/apple-ios")
includes("@addon/charon/emulate")
set_defaultplat("iphoneos")
set_defaultarchs("iphoneos|armv7")

-- A program per class of the backports that reach below iOS 6 (tests/backports/README.md), each named for its source, tests/backports/device/<name>.m.
for _, name in ipairs({"nsuuid"}) do
    target(name)
        add_rules("@addon/charon/daemon")
        add_files(path.join(root, "tests/backports/device", name .. ".m"), path.join(root, "tests/backports/device/check.m"))
        add_includedirs(path.join(root, "tests/backports/device"))
        add_mflags("-fobjc-arc")
        add_ldflags("-fobjc-arc", {force = true})
        add_frameworks("Foundation")
        add_packages("apple-backports")
        set_values("charon.libraries", "apple-backports")
        set_values("charon.control", "control")
        -- libFoundationBackports.dylib still weakly imports NSProgress (NSItemProvider's progress), which the releases below 6.0 refuse, until the
        -- backports carry that class too; nothing this program does reaches it. Remove the waiver with the last weak import.
        set_values("charon.waive.weak-imports", "libFoundationBackports weakly imports NSProgress until the backports carry it below iOS 6; this program never asks an NSItemProvider for a progress")
end
