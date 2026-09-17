task("device")
    set_category("plugin")
    on_run("main")
    set_menu {
        usage = "xmake device [options] install|log|run|where|list|claim|release [arguments]",
        description = "Reach the phone device.env (or device.NAME.env) names: install the packages, read its log, run a command, or claim it so other sessions wait.",
        options = {
            {"d", "device", "kv", nil, "Pick device.NAME.env; CHARON_DEVICE=NAME does it for the whole shell."},
            {"s", "seconds", "kv", "15", "How long log reads, or how long run may take."},
            {nil, "holder", "kv", nil, "Who claims or releases the device; CHARON_DEVICE_HOLDER does it for the whole shell, and every command checks it against the claim."},
            {nil, "minutes", "kv", "30", "How long a claim lasts unless it is released or claimed again."},
            {},
            {nil, "action", "v", nil, "install, log, run, where, list, claim or release."},
            {nil, "arguments", "vs", nil, "The command run executes, or the text log filters on."}
        }
    }
