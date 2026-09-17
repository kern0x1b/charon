rule("swift")
    add_deps("@self/apple-ios")
    set_extensions(".swift")

    on_load(function (target)
        import("core.project.project")
        if not project.required_package("swift-embedded") then
            raise("target(%s) compiles Swift, and its project requires no swift-embedded: add_requires(\"charon@swift-embedded\", {alias = \"swift-embedded\"})", target:name())
        end
        target:add("packages", "swift-embedded")
    end)

    on_config(function (target)
        local sourcebatch = target:sourcebatches()["@addon/charon/swift"] or target:sourcebatches()["swift"]
        if sourcebatch and #sourcebatch.sourcefiles > 0 then
            local objectfile = path.join(target:objectdir(), "swift", target:name() .. ".o")
            target:data_set("swift.objectfile", objectfile)
            table.insert(target:objectfiles(), objectfile)
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
            local package = target:pkg("swift-embedded")
            local swiftc = table.wrap((package:envs() or {}).SWIFT_EXEC)[1]
            if not swiftc or not os.isfile(swiftc) then
                raise("swift-embedded at %s names no compiler its Swift module was built with; reinstall it", package:installdir())
            end
            local has_main = false
            for _, file in ipairs(sourcebatch.sourcefiles) do
                if path.filename(file) == "main.swift" then
                    has_main = true
                end
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
