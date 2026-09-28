package("swift-syntax")
    set_kind("library")
    set_homepage("https://github.com/swiftlang/swift-syntax")
    set_description("SwiftSyntax, the parser and macro machinery Apple ships inside its own toolchain, built for the host so that a port's macro plugin has a CompilerPlugin to conform to. The toolchain on this machine exports every macro protocol (AccessorMacro, PeerMacro, MemberAttributeMacro, MemberMacro, ExtensionMacro, FreestandingMacro, Macro) and *no* CompilerPlugin: it is behind @_spi(PluginMessage) in SwiftCompilerPluginMessageHandling, which is why a -load-plugin-executable cannot be written against the toolchain's own modules. This is the Apache-2.0 upstream at the tag that matches the 6.4 toolchain, built by upstream's own SwiftPM build for the host, and it is the one such package: TipKit's macros, AppIntents' and SwiftData's all take this one")
    set_license("Apache-2.0")
    set_policy("package.strict_compatibility", true)

    add_urls("https://github.com/swiftlang/swift-syntax.git")
    add_versions("604.0.0", "050f1a346fbbac0ca2cfb15a95274f7bd1cf0ccf")

    -- The digest covers the recipe *and* the upstream it pins: the sources are not in this tree, so
    -- the commit is the only thing that identifies them, and a recipe that changed its pin has to be
    -- a different package or a port keeps linking the modules of another release.
    add_configs("recipe", {description = "The digest of this recipe and the upstream commit it pins, so a changed flag or pin is a different package.",
                           default = "", type = "string", readonly = true})

    -- Where a dependent finds the modules and the archives: `rules/macro` reads this to compile a
    -- plugin executable, and the Swift side reads it to typecheck an expansion test.
    add_configs("envs", {description = "The modules and the archives of this package's host build, for a macro plugin or a test that links them.",
                         default = "", type = "string"})

    -- The modules a macro plugin needs, and the ones an expansion test needs on top of them. The C
    -- shims are in the list because SwiftParser and SwiftSyntax are built on them; they are not
    -- modules, and the SwiftPM build makes them as part of the same graph.
    local modules = {
        "SwiftBasicFormat", "SwiftCompilerPlugin", "SwiftCompilerPluginMessageHandling", "SwiftDiagnostics",
        "SwiftIDEUtils", "SwiftParser", "SwiftParserDiagnostics", "SwiftSyntax", "SwiftSyntaxBuilder",
        "SwiftSyntaxMacroExpansion", "SwiftSyntaxMacros", "SwiftSyntaxMacrosTestSupport",
    }

    on_load("@macosx", function (package)
        -- The digest is computed here and not in the config's default, because `package:commit()` is
        -- not callable while the recipe body is being read -- it is `attempt to call a nil value
        -- (global 'package')`, which is how this recipe did not load (kits r4). libcxx and llvm
        -- compute theirs in on_load for the same reason.
        package:set("recipe", hash.strhash128(path.join(hash.sha256(path.join(os.scriptdir(), "xmake.lua")),
                                                       package:commit() or package:revision())))
        -- The host compiler goes out with the modules: a plugin is built for the host, and nothing
        -- else in the fleet publishes one (rules/macro reads it, and there is no producer for it
        -- before this), so it is named here beside what it is for.
        package:add("envs", {CHARON_SWIFT_SYNTAX = package:installdir("lib"),
                             CHARON_HOST_SWIFTC = os.getenv("SWIFT_EXEC") or "/usr/bin/swiftc"})
    end)

    on_install("@macosx", function (package)
        -- Upstream's own build, for the host, at the host's own architecture. This is not a
        -- convenience: swift-syntax's module graph (SwiftSyntax before SwiftParser before
        -- SwiftSyntaxMacros, the C shims under both) is upstream's to order, and a second
        -- hand-written compile of twenty modules would be a second thing to keep right.
        local build = path.join(package:installdir(), "build")
        os.mkdir(build)
        os.vrunv("swift", {"build", "--package-path", path.join(package:sourcefile(), ".."), "--scratch-path", build,
                           "--triple", "arm64-apple-macosx13.0", "-c", "release-only"}, {curdir = package:sourcefile()})
        -- The products: the modules under Modules/, the archives beside them, and the resources
        -- SwiftSyntax keeps as files.
        local products = path.join(build, "release-only")
        for _, name in ipairs(modules) do
            local module = path.join(products, "Modules", name)
            if os.isfile(module) then
                os.cp(module, path.join(package:installdir("lib"), "swift", "host", path.basename(module)))
            end
        end
        for _, pattern in ipairs({"*.a", "*.dylib", "lib*.so"}) do
            for _, archive in ipairs(os.files(path.join(products, pattern))) do
                os.cp(archive, path.join(package:installdir("lib"), path.filename(archive)))
            end
        end
        for _, dir in ipairs({"SwiftSyntax", "_SwiftSyntaxCShims", "SwiftSyntaxPrivate"}) do
            local resources = path.join(products, "..", dir)
            if os.isdir(resources) then os.cp(resources, path.join(package:installdir("share"), dir)) end
        end
        print("%s: %s at %s, %s modules for the host", package:name(), package:version_str(),
              package:installdir("lib"), #modules)
    end)
