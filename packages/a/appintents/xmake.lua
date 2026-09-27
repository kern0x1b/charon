package("appintents")
    set_homepage("https://github.com/kern0x1b/charon")
    set_description("The AppIntents framework of iOS 16, as one Swift module a port writes `import AppIntents` for, built against the charon@swift-runtime a port carries. The API, the protocols, the parameters, the entities, the queries, the results and in-process `perform` are the port's own; what the framework leaves to a system service - Siri, Shortcuts, Spotlight, a widget, a live activity - is the seam this README and facts/AppIntents say it is, and the API surface for it exists either way")
    set_license("MIT")
    set_policy("package.strict_compatibility", true)

    local digests = {}
    local inputs = table.join({path.join(os.scriptdir(), "xmake.lua")}, os.files(path.join(os.scriptdir(), "Sources", "AppIntents", "**.swift")))
    table.sort(inputs)
    for _, file in ipairs(inputs) do
        table.insert(digests, path.relative(file, os.scriptdir()) .. "=" .. hash.sha256(file))
    end
    add_configs("sources", {description = "The digest of this recipe and the module's sources, so a changed declaration is a different package.", default = hash.strhash128(table.concat(digests, ";")), type = "string", readonly = true})

    add_configs("shared", {description = "Compile against a shared swift-runtime and its packaged libc++, for a port that requires them so.", default = false, type = "boolean"})
    add_configs("backports", {description = "Compile against the swift-runtime built with the backports, for a port that requires it so.", default = false, type = "boolean"})
    add_configs("backports_uikit", {description = "With backports: the runtime whose UIKit overlay is linked to the UIKit backports, for an application.", default = false, type = "boolean"})

    on_load("iphoneos", function (package)
        package:add("deps", "charon@swift-runtime", {alias = "swift-runtime", configs = {shared = package:config("shared") or nil,
                    backports = package:config("backports") or nil, backports_uikit = package:config("backports_uikit") or nil}})
        package:add("links", "AppIntents")
        package:add("frameworks", "Foundation", "CoreFoundation")
    end)

    on_install("iphoneos", function (package)
        local modules = path.join(package:scriptdir(), "..", "..", "..", "modules")
        local swift = import("apple.swift", {rootdir = modules, anonymous = true})
        local toolchain = assert(package:toolchains(), "AppIntents is built with the apple-ios toolchain")[1]
        toolchain:load()
        local runtime = assert(package:dep("swift-runtime"), "AppIntents is compiled against charon@swift-runtime")
        local swiftc = assert(table.wrap((runtime:envs() or {}).SWIFT_EXEC)[1], "swift-runtime names no compiler; reinstall it")
        local minimum = toolchain:config("deployment")
        local triple = package:arch() .. "-apple-ios" .. minimum
        local sdk = toolchain:config("sdkdir")
        local swiftdir = path.join(package:installdir("lib"), "swift", "iphoneos")
        local objects = path.absolute("objects")
        os.mkdir(objects)
        os.mkdir(swiftdir)

        -- One module, as Styx's Combine is one module: the whole framework in a single compile, so a
        -- declaration of one file sees every other. Availability checking stays on; what the port's
        -- release has, the module declares, because the module IS the port's own copy of the API.
        local module = path.join(swiftdir, "AppIntents.swiftmodule")
        os.mkdir(module)
        local argv = table.join(swift.runtime_flags({
            architecture = package:arch(), deployment = minimum, sdk = sdk,
            resources = path.join(runtime:installdir(), "lib", "swift"),
            plugins = table.wrap((runtime:envs() or {}).SWIFT_PLUGIN_PATH)[1],
            module = "AppIntents", optimize = "fastest", prefix_map = os.curdir() .. "=/appintents"}),
            {"-I", swiftdir, "-emit-module", "-emit-module-path",
             path.join(module, package:arch() .. "-apple-ios.swiftmodule"), "-c"},
            os.files(path.join("Sources", "AppIntents", "**.swift")), {"-o", path.join(objects, "AppIntents.o")})
        os.vrunv(swiftc, argv)
        os.vrunv(toolchain:tool("ar"), {"-rcs", path.join(package:installdir("lib"), "libAppIntents.a"), path.join(objects, "AppIntents.o")})

        package:setenv("CHARON_SWIFT_MODULES", swiftdir)
        os.cp(path.join(os.scriptdir(), "..", "..", "..", "LICENSE"), path.join(package:installdir("licenses")))
        os.cp("README.md", package:installdir("share"))
    end)
