set_project("charoncalls")
set_version("0.0.1")
-- The generated call test as a port: every class and every member the registry carries is called
-- with neutral arguments, each in a process of its own, and what the port answers is compared with
-- what the host's own framework answers (tools/callgen/run-host.sh, the same generated file).
--
-- It is a measurement program and not a released image: it calls every member of the framework it
-- is handed, including the ones that refuse a neutral value, and it forks a thousand times. The
-- waiver below is the same one the display probe carries, and for the same reason.
local root = os.getenv("CHARCALLS_ROOT") or path.join(os.scriptdir(), "../../../..")
add_repositories("charon " .. root)
add_addons("charon v0.8.13")
set_config("apple_minimum", os.getenv("CHARCALLS_MINIMUM") or "6.1.3")
local package = os.getenv("CHARCALLS_PACKAGE") ~= "0"
if package then
    add_requires("charon@apple-backports", {alias = "apple-backports", configs = {intents = true}})
end
includes("@addon/charon/apple-ios")
includes("@addon/charon/emulate")
set_defaultplat("iphoneos")
set_defaultarchs("iphoneos|armv7")

local calls = os.getenv("CHARCALLS_GENERATED") or path.join(root, "tests/backports/callgen/generated")

target("charoncalls")
    add_rules("@addon/charon/daemon")
    add_files(path.join(root, "tests/backports/callgen/harness.m"))
    add_files(path.join(root, "tests/backports/callgen/main.m"))
    add_files(path.join(calls, "Calls.m"))
    add_includedirs(path.join(root, "tests/backports/callgen"))
    add_mflags("-fobjc-arc", "-I" .. path.join(root, "tests/backports/callgen"))
    add_ldflags("-fobjc-arc", {force = true})
    add_frameworks("Foundation")
    if package then
        add_packages("apple-backports")
        set_values("charon.libraries", "apple-backports")
        set_values("charon.waive.weak-imports",
                   "measurement program, not a released image: it calls every member of the framework it is handed and forks once per member")
    end
    set_values("charon.control", "control")
