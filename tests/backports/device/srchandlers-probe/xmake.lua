set_project("srchandlersprobe")
set_version("0.1.0")
-- A barrier source's cancellation and registration handlers on the emulated iPhone3,1 at 6.1.3: the
-- release's own calls beside this package's shims. The host is macOS, whose libdispatch already gives
-- these two handlers the barrier bit, so the host differential cannot show what the shims are for. What a
-- release BEFORE iOS 10 does with such a handler on a concurrent target queue is the premise of the
-- whole design, and this is where it is measured.
--
-- The root is four ".." up from this directory, which is the repository root from
-- tests/backports/device/srchandlers-probe. A fifth lands in tests/backports/device and every add_files()
-- of a shim then fails to match, which xmake reports as a warning and carries on with, so the binary
-- links without the shims and the run answers the wrong question.
local root = os.getenv("SRCH_ROOT") or path.join(os.scriptdir(), "../../../..")
add_repositories("charon " .. root)
add_addons("charon v0.8.14")
set_config("apple_minimum", "6.1.3")
includes("@addon/charon/apple-ios")
includes("@addon/charon/emulate")
set_allowedplats("iphoneos")
set_allowedarchs("iphoneos|armv7")
set_defaultplat("iphoneos")
set_defaultarchs("iphoneos|armv7")

target("sourcehandlers")
    add_rules("@addon/charon/daemon")
    add_files(path.join(os.scriptdir(), "sourcehandlers.c"))
    -- The release's own calls are what this program measures, so no shim of the cancellation or
    -- registration kind is linked into it and the project builds from origin/main on its own. What it does
    -- link is the call that makes a barrier block on a release with no dispatch_block_create of its own,
    -- because a barrier handler has to be made somehow on 6.1.3, and this is the way a caller on this
    -- release makes one.
    --
    -- Everything linked here is compiled exactly as packages/a/apple-compat/xmake.lua compiles it: one
    -- plain `clang -Os -fvisibility=hidden -c`, and NO forced include of the renaming headers. A forced
    -- include is what an IMAGE gets, so that the calls in the image bind to the shim; it must not reach
    -- this program, or the readings below would be a shim's and not the release's.
    local shims = path.join(root, "packages", "a", "apple-compat", "src")
    add_files(path.join(shims, "dispatch_block_create.c"))
    add_includedirs(shims)
    add_frameworks("Foundation")
    set_values("charon.version", "1.0")
    set_values("charon.control", "control")