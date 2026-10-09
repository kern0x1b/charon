set_project("charoncoremidi")
set_version("0.0.1")
-- The CoreMIDI round trip as a port: a client with a block, a virtual source and destination that speak
-- Universal MIDI Packets, and a note that goes out and comes back, on the emulated 6.1.3 (roundtrip.m).
local root = os.getenv("CHARCOREMIDI_ROOT") or path.join(os.scriptdir(), "../../../..")
add_repositories("charon " .. root)
-- The addon the machine's store holds and names active (~/.xmake/addons/addons.conf), so a resolve moves nothing.
add_addons("charon v0.8.16")
set_config("apple_minimum", os.getenv("CHARCOREMIDI_MINIMUM") or "6.1.3")
add_requires("charon@apple-backports", {alias = "apple-backports", configs = {coremidi = true}})
includes("@addon/charon/apple-ios")
includes("@addon/charon/emulate")
set_defaultplat("iphoneos")
set_defaultarchs("iphoneos|armv7")

target("charoncoremidi")
    add_rules("@addon/charon/daemon")
    add_files(path.join(root, "tests/backports/emulate/coremidi/roundtrip.m"))
    add_mflags("-fobjc-arc")
    add_ldflags("-fobjc-arc", {force = true})
    add_frameworks("Foundation", "CoreMIDI")
    add_packages("apple-backports")
    set_values("charon.libraries", "apple-backports")
    set_values("charon.control", "control")
