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

    -- Where the CoreSpotlight registry is read from: the backports package beside this one when the
    -- port carries it, and the source tree it was built from otherwise, so the overlay is the same
    -- whether the package is installed or worked on in place.
    local function opt_backports_registry(package)
        for _, dep in ipairs(package:orderdeps() or {}) do
            if dep:name() == "apple-backports" then
                return path.join(dep:installdir("share"))
            end
        end
        return path.join(os.scriptdir(), "..", "apple-backports", "registry")
    end

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
        local probe_dir = path.absolute("probe")
        os.mkdir(objects)
        os.mkdir(swiftdir)
        os.mkdir(probe_dir)

        -- The CoreSpotlight classes this module extends. The release runs no Spotlight index and the
        -- CoreSpotlight backports carry the three classes, but the SDK marks them iOS 9 in macros
        -- `apple.lift` does not rewrite, and the lift's FRAMEWORKS does not name the framework - so
        -- the package asks for the three of them itself, through apple.spotlight_lift, which lowers
        -- what the CoreSpotlight registry carries and checks both ways. With the overlay the module
        -- compiles the five AppIntents extensions on them; without it they are left out and their
        -- rows read `missing`, which is what they are until the lift covers the framework.
        local spot = import("apple.spotlight_lift", {rootdir = modules, anonymous = true})
        local overlays, defs = {}, {}
        local registry = opt_backports_registry(package)
        if registry then
            local result = spot.spotlight_lift({sdk = sdk, target = triple, minimum = minimum,
                                                registry = registry, outputdir = path.join(package:installdir("share"), "spotlight")})
            if result.ok then
                table.insert(overlays, result.vfs)
                table.insert(defs, "-DCHARON_APPINTENTS_CORESPOTLIGHT")
                print("%s: CoreSpotlight's %s are available at %s, their AppIntents extensions are in the module",
                      package:name(), table.concat(result.lifted, ", "), minimum)
            else
                print("%s: CoreSpotlight is not reachable at %s (%s), its AppIntents rows are left out of the module",
                      package:name(), minimum, result.reason)
            end
        end
        -- The headers the runtime itself lifted, when it was built with the backports: that is what
        -- makes Foundation's NSUserActivity and CoreLocation's CLPlacemark visible at this release.
        local lifted = table.wrap((runtime:envs() or {}).CHARON_SWIFT_LIFTED_HEADERS)[1]
        if lifted then
            table.insert(overlays, lifted)
            table.insert(defs, "-DCHARON_APPINTENTS_LIFTED_HEADERS")
        end

        -- `LocalizedStringResource`: this module carries the type when the runtime's Foundation has
        -- not got it, and leaves it out when the platform brings its own. Which is which is measured
        -- with a probe, not assumed, and the file is taken out of the source list either way - two
        -- types of one name in one image is not something a caller could use.
        local sources, carries = {}, false
        for _, file in ipairs(os.files(path.join("Sources", "AppIntents", "**.swift"))) do
            if path.filename(file) ~= "LocalizedStringResource.swift" then
                table.insert(sources, file)
            end
        end
        local platform_resource = path.join(probe_dir, "localized.swift")
        io.writefile(platform_resource, "import Foundation\npublic func probe() -> LocalizedStringResource { return LocalizedStringResource(\"\") }")
        local has = try {function ()
            os.vrunv(swiftc, table.join(swift.runtime_flags({
                architecture = package:arch(), deployment = minimum, sdk = sdk,
                resources = path.join(runtime:installdir(), "lib", "swift"),
                plugins = table.wrap((runtime:envs() or {}).SWIFT_PLUGIN_PATH)[1],
                module = "CharonAppIntentsProbe", optimize = "none", prefix_map = os.curdir() .. "=/appintents"}),
                {"-I", path.join(runtime:installdir(), "lib", "swift", "iphoneos"), "-typecheck", platform_resource}))
            return true
        end}
        os.tryrm(platform_resource)
        if has then
            carries = true
            table.insert(defs, "-DCHARON_APPINTENTS_CARRIES_LOCALIZED_STRING")
            print("%s: this runtime's Foundation has LocalizedStringResource, the module uses the platform's and carries none",
                  package:name())
        else
            table.insert(sources, path.join("Sources", "AppIntents", "LocalizedStringResource.swift"))
            print("%s: this runtime's Foundation has no LocalizedStringResource, the module carries it (AppIntents' whole API is written in it)",
                  package:name())
        end

        -- The Foundation types AppIntents' API is written in that this runtime may not have yet. Each is
        -- measured, not assumed: a probe that uses the type the way the conformance does compiles only
        -- when the runtime has it and is available at the port's release, and only then is the block
        -- of Gated.swift that conforms it compiled into the module. What is left out is printed, so a
        -- row that is missing is never mistaken for one that is placed.
        local defs = {}
        local probes = {
            {flag = "CHARON_APPINTENTS_ATTRIBUTED_STRING", name = "AttributedString",
             body = "import Foundation\npublic func probe() -> AttributedString { return AttributedString(\"x\") }"},
            {flag = "CHARON_APPINTENTS_MEASUREMENT", name = "Measurement",
             body = "import Foundation\npublic func probe() -> Measurement { return Measurement(value: 1, unit: UnitLength.meters) }"},
            {flag = "CHARON_APPINTENTS_RECURRENCE_RULE", name = "Calendar.RecurrenceRule",
             body = "import Foundation\npublic func probe() -> Calendar.RecurrenceRule { return Calendar.RecurrenceRule(weekOfMonth: 1, weekOfYear: 2, month: 3, dayOfWeek: 4) }"}}
        for _, probe in ipairs(probes) do
            local source = path.join(probe_dir, "probe.swift")
            io.writefile(source, probe.body)
            local ok = try {function ()
                os.vrunv(swiftc, table.join(swift.runtime_flags({
                    architecture = package:arch(), deployment = minimum, sdk = sdk,
                    resources = path.join(runtime:installdir(), "lib", "swift"),
                    plugins = table.wrap((runtime:envs() or {}).SWIFT_PLUGIN_PATH)[1],
                    module = "CharonAppIntentsProbe", optimize = "none", prefix_map = os.curdir() .. "=/appintents"}),
                    {"-I", path.join(runtime:installdir(), "lib", "swift", "iphoneos"), "-typecheck", source}))
                return true
            end}
            os.tryrm(source)
            if ok then
                table.insert(defs, "-D" .. probe.flag)
                print("%s: the runtime has %s, its conformance is in the module", package:name(), probe.name)
            else
                print("%s: the runtime has no %s at this release, its rows are left out of the module",
                      package:name(), probe.name)
            end
        end

        -- One module, as Styx's Combine is one module: the whole framework in a single compile, so a
        -- declaration of one file sees every other. Availability checking stays on; what the port's
        -- release has, the module declares, because the module IS the port's own copy of the API.
        local module = path.join(swiftdir, "AppIntents.swiftmodule")
        os.mkdir(module)
        local overlay_flags = {}
        for _, overlay in ipairs(overlays) do
            table.insert(overlay_flags, "-Xcc")
            table.insert(overlay_flags, "-ivfsoverlay")
            table.insert(overlay_flags, "-Xcc")
            table.insert(overlay_flags, overlay)
        end
        local argv = table.join(swift.runtime_flags({
            architecture = package:arch(), deployment = minimum, sdk = sdk,
            resources = path.join(runtime:installdir(), "lib", "swift"),
            plugins = table.wrap((runtime:envs() or {}).SWIFT_PLUGIN_PATH)[1],
            module = "AppIntents", optimize = "fastest", prefix_map = os.curdir() .. "=/appintents"}),
            defs, overlay_flags, {"-I", swiftdir, "-emit-module", "-emit-module-path",
             path.join(module, package:arch() .. "-apple-ios.swiftmodule"), "-c"},
            sources, {"-o", path.join(objects, "AppIntents.o")})
        os.vrunv(swiftc, argv)
        os.vrunv(toolchain:tool("ar"), {"-rcs", path.join(package:installdir("lib"), "libAppIntents.a"), path.join(objects, "AppIntents.o")})

        os.tryrm(probe_dir)
        package:setenv("CHARON_SWIFT_MODULES", swiftdir)
        os.cp(path.join(os.scriptdir(), "..", "..", "..", "LICENSE"), path.join(package:installdir("licenses")))
        os.cp("README.md", package:installdir("share"))
    end)
