rule("swift")
    add_deps("@self/apple-ios")
    set_extensions(".swift")

    -- Swift comes in two kinds here. Embedded Swift is the subset with no runtime library, and a port that uses it needs
    -- nothing beside its own binary. The whole language needs the runtime, which charon@swift-runtime builds for the
    -- port's architecture and oldest release and the port carries with it; a port says which one it takes by the package
    -- it requires, and taking both would leave two standard libraries in one program.
    on_load(function (target)
        import("core.project.project")
        local runtime = project.required_package("swift-runtime")
        local embedded = project.required_package("swift-embedded")
        if runtime and embedded then
            raise("target(%s) compiles Swift, and its project requires both swift-runtime and swift-embedded: a program takes one standard library or the other", target:name())
        end
        if not runtime and not embedded then
            raise("target(%s) compiles Swift, and its project requires neither: add_requires(\"charon@swift-runtime\", {alias = \"swift-runtime\"}) for the whole language, or add_requires(\"charon@swift-embedded\", {alias = \"swift-embedded\"}) for the subset with no runtime library", target:name())
        end
        if embedded then
            target:add("packages", "swift-embedded")
            return
        end
        -- The C++ runtime is the port's too: libc++abi exports the locks, the atomics and the emulated thread-local
        -- storage once for the process, and the Swift libraries are linked against it.
        if not project.required_package("libcxx") then
            raise("target(%s) compiles Swift against the runtime it carries, which links the C++ runtime: add_requires(\"charon@libcxx\", {alias = \"libcxx\"})", target:name())
        end
        target:add("packages", "swift-runtime", "libcxx")
    end)

    on_config(function (target)
        -- The runtime is shared libraries; the program carries them the way it carries any package's - a tweak or a
        -- daemon in its package's folder, an application inside its bundle. A shared runtime is a package of its own that
        -- the program depends on instead: it carries none of it, and its libc++ is the one in that package's folder.
        local runtime = target:pkg("swift-runtime")
        if runtime and runtime:requireconf("configs", "shared") then
            -- The runtime's libraries are all on the link line, and the program loads the ones it uses: a daemon that
            -- never touches UIKit loads no UIKit overlay, and depends on no package that holds it.
            target:add("ldflags", "-Wl,-dead_strip_dylibs", {force = true})
        end
        if runtime and not runtime:requireconf("configs", "shared") then
            for _, carried in ipairs({"swift-runtime", "libcxx"}) do
                target:add("values", "charon.libraries", carried)
                target:add("values", "app.frameworks", carried)
            end
        end
        local sourcebatch = target:sourcebatches()["@addon/charon/swift"] or target:sourcebatches()["swift"]
        if sourcebatch and #sourcebatch.sourcefiles > 0 then
            local objectfile = path.join(target:objectdir(), "swift", target:name() .. ".o")
            target:data_set("swift.objectfile", objectfile)
            table.insert(target:objectfiles(), objectfile)
        end
        -- The program names the build of the runtime it was compiled against, and the link fails against any other: the
        -- libraries are built without library evolution, so two builds of them do not answer for each other.
        local package = target:pkg("swift-runtime")
        if package then
            local mark = table.wrap((package:envs() or {}).CHARON_SWIFT_RUNTIME_MARK)[1]
            if not mark then
                raise("swift-runtime at %s names no build of itself; reinstall it", package:installdir())
            end
            target:add("ldflags", "-Wl,-u,_" .. mark, {force = true})
            -- A runtime built with the backports hands its lifted headers to the port's own Swift too, and the port carries
            -- the backports that make them true.
            local lifted = table.wrap((package:envs() or {}).CHARON_SWIFT_LIFTED_HEADERS)[1]
            if lifted then
                local carried = target:pkg("apple-backports")
                if not carried then
                    raise("target(%s) compiles against swift-runtime built with the backports, and does not carry them: add_requires(\"charon@apple-backports\", {alias = \"apple-backports\"}) and add_packages(\"apple-backports\")", target:name())
                end
                -- The lifted headers let the port write a call the backports implement; the call finds its implementation
                -- only where that library is loaded. A library the runtime was built to link is one the port must carry too:
                -- its config says so, and a class message that reaches a library that is not there is not a link error but
                -- an unrecognized selector at run time.
                local libraries = {coredata = "CoreDataBackports", uikit = "UIKitBackports"}
                for _, config in ipairs(table.wrap((package:envs() or {}).CHARON_SWIFT_RUNTIME_BACKPORTS)[1]:split(",")) do
                    local found = false
                    for _, folder in ipairs(table.wrap(carried:get("linkdirs"))) do
                        found = found or os.isfile(path.join(folder, "lib" .. libraries[config] .. ".dylib"))
                    end
                    if not found then
                        raise("target(%s) compiles against swift-runtime built with the %s backports, and its apple-backports package holds no lib%s.dylib: add_requires(\"charon@apple-backports\", {alias = \"apple-backports\", configs = {%s = true}})", target:name(), config, libraries[config], config)
                    end
                end
                target:add("values", "swift.flags", "-vfsoverlay", lifted)
            end
        end
    end)

    on_build_files(function (target, jobgraph, sourcebatch, opt)
        jobgraph:add(target:fullname() .. "/swift/module", function (index, total, jobopt)
            import("core.project.depend")
            import("utils.progress")
            local swift = import("@self.apple.swift")
            local objectfile = target:data("swift.objectfile")
            local toolchain = target:toolchain("apple-ios")
            toolchain:load()
            local package = target:pkg("swift-runtime") or target:pkg("swift-embedded")
            local swiftc = table.wrap((package:envs() or {}).SWIFT_EXEC)[1]
            if not swiftc or not os.isfile(swiftc) then
                raise("%s at %s names no compiler its Swift was built with; reinstall it", package:name(), package:installdir())
            end
            local has_main = false
            for _, file in ipairs(sourcebatch.sourcefiles) do
                if path.filename(file) == "main.swift" then
                    has_main = true
                end
            end

            -- With the runtime the program carries, the compiler writes the object itself: the code is the release's own
            -- and needs none of the lowering Embedded Swift is put through. It reads the runtime's resource directory,
            -- and so takes that Swift rather than the one the SDK carries for the architecture.
            if target:pkg("swift-runtime") then
                local modules = {}
                for _, dependency in ipairs(target:orderpkgs()) do
                    for _, folder in ipairs(table.wrap((dependency:envs() or {}).CHARON_SWIFT_MODULES)) do
                        table.join2(modules, {"-I", folder})
                    end
                end
                local argv = table.join(swift.runtime_flags({
                    architecture = target:arch(),
                    deployment = toolchain:config("deployment"),
                    sdk = toolchain:config("sdkdir"),
                    resources = path.join(package:installdir(), "lib", "swift"),
                    plugins = table.wrap((package:envs() or {}).SWIFT_PLUGIN_PATH)[1],
                    module = target:values("swift.module") or target:name(),
                    optimize = target:get("optimize"),
                    symbols = table.contains(table.wrap(target:get("symbols")), "debug"),
                    prefix_map = os.projectdir() .. "=/port",
                    has_main = has_main
                }), modules, table.wrap(target:values("swift.flags")), {"-c"}, sourcebatch.sourcefiles, {"-o", objectfile})
                depend.on_changed(function ()
                    progress.show(jobopt.progress, "${color.build.object}compiling.swift %s", target:name())
                    os.mkdir(path.directory(objectfile))
                    os.vrunv(swiftc, argv)
                end, {files = sourcebatch.sourcefiles, dependfile = objectfile .. ".d", values = argv, changed = target:is_rebuilt()})
                return
            end
            local bitcode = objectfile .. ".bc"
            local argv = table.join(swift.compile_flags({
                architecture = target:arch(),
                deployment = toolchain:config("deployment"),
                sdk = toolchain:config("sdkdir"),
                modules = path.join(package:installdir(), "lib", "swift", "embedded"),
                module = target:values("swift.module") or target:name(),
                optimize = target:get("optimize"),
                symbols = table.contains(table.wrap(target:get("symbols")), "debug"),
                prefix_map = os.projectdir() .. "=/port",
                has_main = has_main
            }), table.wrap(target:values("swift.flags")), {"-emit-bc"}, sourcebatch.sourcefiles, {"-o", bitcode})
            local codegen = table.join(table.wrap(toolchain:get("cxflags")), swift.codegen_flags({optimize = target:get("optimize")}),
                                       {"-c", bitcode, "-o", objectfile})
            depend.on_changed(function ()
                progress.show(jobopt.progress, "${color.build.object}compiling.swift %s", target:name())
                os.mkdir(path.directory(objectfile))
                os.vrunv(swiftc, argv)
                os.vrunv(toolchain:tool("cc"), codegen, {envs = {IPHONEOS_DEPLOYMENT_TARGET = toolchain:config("deployment")}})
            end, {files = sourcebatch.sourcefiles, dependfile = objectfile .. ".d", values = table.join(argv, codegen), changed = target:is_rebuilt()})
        end)
    end, {jobgraph = true, batch = true})
