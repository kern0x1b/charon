package("apple-compat")
    set_homepage("https://github.com/kern0x1b/charon")
    set_description("What a current library calls and an old Apple system does not have, provided as hidden definitions linked into the image that calls them")
    set_license("MIT")
    set_policy("package.strict_compatibility", true)

    local digests = {}
    local sources = table.join(os.files(path.join(os.scriptdir(), "src", "*.c")), os.files(path.join(os.scriptdir(), "include", "charon", "*.h")))
    table.sort(sources)
    for _, file in ipairs(sources) do
        table.insert(digests, path.filename(file) .. "=" .. hash.sha256(file))
    end
    add_configs("sources", {description = "The digest of the shims this package compiles, so a changed shim is a different package.", default = hash.strhash128(table.concat(digests, ";")), type = "string", readonly = true})

    on_load("iphoneos", function (package)
        import("core.base.semver")
        local compat = import("apple.compat", {rootdir = path.join(package:scriptdir(), "..", "..", "..", "modules"), anonymous = true})
        local toolchain = assert(package:toolchains(), "apple-compat is built with the apple-ios toolchain")[1]
        toolchain:load()
        local symbols = {}
        for symbol, release in pairs(compat.arrived("iOS")) do
            if semver.compare(toolchain:config("deployment"), release) < 0 then
                table.insert(symbols, symbol)
            end
        end
        table.sort(symbols)
        package:data_set("provided", symbols)
        if #symbols > 0 then
            package:add("links", "apple-compat")
        end
    end)

    on_install("iphoneos", function (package)
        local toolchain = package:toolchains()[1]
        toolchain:load()
        local triple = package:arch() .. "-apple-ios"
        local objects = {}
        for _, symbol in ipairs(package:data("provided")) do
            local object = path.absolute(symbol .. ".o")
            os.vrunv("xcrun", {"clang", "-target", triple, "-miphoneos-version-min=" .. toolchain:config("deployment"), "-isysroot", toolchain:config("sdkdir"), "-Os",
                               "-fvisibility=hidden", "-c", path.join(package:scriptdir(), "src", symbol .. ".c"), "-o", object})
            table.insert(objects, object)
            local header = path.join(package:scriptdir(), "include", "charon", symbol .. ".h")
            if os.isfile(header) then
                os.vcp(header, path.join(package:installdir("include"), "charon") .. "/")
            end
        end
        if #objects > 0 then
            os.vrunv("xcrun", table.join({"libtool", "-static", "-o", path.join(package:installdir("lib"), "libapple-compat.a")}, objects))
        end
        os.vcp(path.join(package:scriptdir(), "..", "..", "..", "LICENSE"), package:installdir("licenses"))
    end)

    on_test(function (package)
        local symbols = package:data("provided") or {}
        if #symbols > 0 then
            assert(os.isfile(path.join(package:installdir("lib"), "libapple-compat.a")))
        end
    end)
