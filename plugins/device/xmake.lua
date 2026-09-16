task("device")
    set_category("plugin")
    on_run("main")
    set_menu {
        usage = "xmake device [options] install|log|run|where [arguments]",
        description = "Reach the phone device.env (or device.NAME.env) names: install the packages, read its log, run a command.",
        options = {
            {"d", "device", "kv", nil, "Pick device.NAME.env; CHARON_DEVICE=NAME does it for the whole shell."},
            {"s", "seconds", "kv", "15", "How long log reads, or how long run may take."},
            {},
            {nil, "action", "v", nil, "install, log, run or where."},
            {nil, "arguments", "vs", nil, "The command run executes, or the text log filters on."}
        }
    }
