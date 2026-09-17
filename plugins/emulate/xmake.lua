task("emulate")
    set_category("plugin")
    on_run("main")
    set_menu {
        usage = "xmake emulate [options] install|run|log|shot|clean [arguments]",
        description = "Reach an emulated device: install the packages into its image, run a command in a fresh clone of it, read what the run left, take its last frame, or remove what emulation left on disk.",
        options = {
            {"d", "device", "kv", nil, "The device to emulate, e.g. iPhone3,1 (default: the first device of the configured architecture iLEmu emulates that runs the release)."},
            {"r", "release", "kv", nil, "The iOS release, the earliest firmware not older than it (default: apple_minimum)."},
            {"s", "seconds", "kv", "60", "How long the command run starts may take."},
            {"t", "timeout", "kv", "900", "The wall-clock limit of a whole boot, after which the emulator is told to quit and then killed."},
            {"k", "keep", "k", nil, "Keep the root filesystem a run booted, beside its log, instead of removing it after the verdict."},
            {"a", "all", "k", nil, "With clean: every port's images and every golden image, not only this port's images."},
            {"n", "network", "kv", nil, "isolated, loopback or host (default: the emulate.network value of the project's targets, else isolated)."},
            {},
            {nil, "action", "v", nil, "install, run, log, shot or clean."},
            {nil, "arguments", "vs", nil, "The command run executes, the text log filters on, or the file shot writes."}
        }
    }
