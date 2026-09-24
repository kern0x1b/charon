set_project("maptable6")
set_version("0.0.1")
-- The addon as a port pins it, from the tag already in the store: a working copy of this repository is never installed as
-- the addon (charon/AGENTS.md, Traps), and the sources under test are named by path below.
add_repositories("charon https://github.com/kern0x1b/charon.git charon-repo-0.8.10")
add_addons("charon v0.8.10")
set_config("apple_minimum", "4.3")
includes("@addon/charon/apple-ios")
includes("@addon/charon/emulate")
set_allowedplats("iphoneos")
set_allowedarchs("iphoneos|armv7")
set_defaultplat("iphoneos")
set_defaultarchs("iphoneos|armv7")

-- differential.m as a device binary: the port, under names of its own, against the release's factories where the release
-- has them (6.0), and alone where it does not (4.3, 5.1.1). One binary, built for the lowest release, runs on all three.
local root = os.getenv("MAPTABLE6_ROOT") or path.join(os.scriptdir(), "../../../../..")
local port = {defines = {"weakToStrongObjectsMapTable=charonHost_weakToStrongObjectsMapTable",
                         "strongToWeakObjectsMapTable=charonHost_strongToWeakObjectsMapTable",
                         "weakToWeakObjectsMapTable=charonHost_weakToWeakObjectsMapTable",
                         "strongToStrongObjectsMapTable=charonHost_strongToStrongObjectsMapTable"}}
target("maptable6")
    add_rules("@addon/charon/daemon")
    add_files(path.join(root, "packages/a/apple-backports/Foundation/NSMapTable+Objects6.m"), port)
    add_files(path.join(root, "tests/backports/host/maptable6/differential.m"),
              path.join(root, "tests/backports/device/check.m"))
    add_includedirs(path.join(root, "tests/backports/device"))
    add_mflags("-fobjc-arc", "-fvisibility=hidden", "-Wno-deprecated-declarations")
    add_ldflags("-fobjc-arc")
    add_frameworks("Foundation")
    set_values("charon.version", "1.0")
    set_values("charon.control", "control")
