set_project("metalchainprobe")
set_version("0.1.0")
-- The Metal 4 command chain on the emulated iPhone3,1 6.1.3 guest, against the answers Apple's own Metal
-- gave on the host and which are written down in tests/backports/device/metalchain-expectations.h.
--
-- WHY IT IS ITS OWN PROJECT, like vdsp-probe and sampler-probe: a case has to be something
-- `xmake emulate install` can put in the image, and that means a target with a control file and a
-- daemon rule - not a source file in tests/backports/device/.
--
-- THE PORT'S FILE IS COMPILED IN, NOT THE LIBRARY, so the probe's answers come from the code in this
-- tree and a reader can see exactly which file is under test: Metal/MTL4CommandQueue26.m is the queue,
-- its two device factories and the capture scope, and it imports CharonMetal.h, so it cannot be built
-- for a host at all. That is why this case exists rather than a host differential.
local root = os.getenv("METALCHAINPROBE_ROOT") or path.join(os.scriptdir(), "../../../..")
add_repositories("charon " .. root)
add_addons("charon v0.8.13")
local minimum = os.getenv("METALCHAINPROBE_MINIMUM") or "6.1.3"
set_config("apple_minimum", minimum)
includes("@addon/charon/apple-ios")
includes("@addon/charon/emulate")
set_defaultplat("iphoneos")
set_defaultarchs("iphoneos|armv7")

target("metalchain-probe")
    add_rules("@addon/charon/daemon")
    add_files(path.join(root, "tests/backports/device/metalchain-probe/metalchain.m"))
    add_files(path.join(root, "packages/a/apple-backports/Metal/MTL4CommandQueue26.m"))
    add_files(path.join(root, "packages/a/apple-backports/Metal/MTL4CommandChain26.m"))
    add_files(path.join(root, "packages/a/apple-backports/Metal/CharonMetalQueue.m"))
    add_frameworks("Foundation", "Metal", "MetalKit", "QuartzCore", "UIKit")
    add_includedirs(path.join(root, "tests/backports/device"),
                    path.join(root, "packages/a/apple-backports/Metal"))
    add_mflags("-fobjc-arc")
    add_ldflags("-fobjc-arc", {force = true})
    set_values("charon.control", "control")
