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
    -- The six shims and the call that makes a barrier block on a release with no dispatch_block_create of
    -- its own, compiled exactly as packages/a/apple-compat/xmake.lua compiles them: one plain
    -- `clang -Os -fvisibility=hidden -c`, and NO forced include of the renaming headers. The forced
    -- include is what an IMAGE gets, so that the calls in the image bind to the shim. A shim's own call to
    -- the release must not see it - with it, dispatch_source_cancel.c's `dispatch_source_cancel(source)`
    -- is this file's own function again and the shim recurses until the stack runs out - and the probe
    -- must not see it either, or its system column reaches the shim and the two columns are one column.
    local shims = path.join(root, "packages", "a", "apple-compat", "src")
    for _, symbol in ipairs({"dispatch_source_create", "dispatch_set_target_queue",
                             "dispatch_source_set_cancel_handler", "dispatch_source_set_registration_handler",
                             "dispatch_source_cancel", "dispatch_resume"}) do
        add_files(path.join(shims, symbol .. ".c"))
    end
    add_files(path.join(shims, "dispatch_block_create.c"))
    add_includedirs(shims)
    add_frameworks("Foundation")
    set_values("charon.version", "1.0")
    set_values("charon.control", "control")