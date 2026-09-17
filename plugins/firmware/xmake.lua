task("firmware")
    set_category("plugin")
    on_run("main")
    set_menu {
        usage = "xmake firmware [--arch=ARCH] fetch RELEASE | xmake firmware --device=IDENTIFIER rootfs RELEASE | xmake firmware list",
        description = "Fetch the system libraries of an iOS release from Apple's firmware for the import check, or list what is held.",
        options = {
            {"a", "arch", "kv", nil, "The architecture whose libraries to fetch: armv6, armv7, armv7s, arm64 or arm64e (default: the configured one)."},
            {"d", "device", "kv", nil, "The device whose root filesystem to unpack, e.g. iPhone3,1, iPod4,1, iPad2,1."},
            {nil, "action", "v", nil, "fetch, rootfs or list."},
            {nil, "release", "v", nil, "The minimum release; the earliest release of the architecture not older than it is fetched."}
        }
    }
