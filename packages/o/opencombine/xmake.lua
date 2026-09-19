package("opencombine")
    set_homepage("https://github.com/OpenCombine/OpenCombine")
    set_description("OpenCombine, the open-source Combine, built against the charon@swift-runtime a port carries: OpenCombine, OpenCombineDispatch and OpenCombineFoundation as static libraries with their modules; below iOS 7 the URLSession publishers are left out and a timer's tolerance is set only where the release has it")
    set_license("MIT")
    set_policy("package.strict_compatibility", true)

    add_urls("https://github.com/OpenCombine/OpenCombine.git")
    add_versions("2023.10.11", "1c6f02c7ed8140c0ba7a783aaddb6e0685a0037b")

    add_deps("charon@swift-runtime", {alias = "swift-runtime"})
    add_deps("charon@libcxx", {alias = "libcxx"})

    local digests = {}
    local sources = {path.join(os.scriptdir(), "xmake.lua"), path.join(os.scriptdir(), "files", "DispatchTimeDistance.swift")}
    for _, file in ipairs(sources) do
        table.insert(digests, path.filename(file) .. "=" .. hash.sha256(file))
    end
    add_configs("recipe", {description = "The digest of this recipe and the source it adds, so a changed recipe is a different package.", default = hash.strhash128(table.concat(digests, ";")), type = "string", readonly = true})

    local libraries = {"OpenCombineFoundation", "OpenCombineDispatch", "OpenCombine", "COpenCombineHelpers"}

    on_load("iphoneos", function (package)
        for _, library in ipairs(libraries) do
            package:add("links", library)
        end
        package:add("frameworks", "Foundation", "CoreFoundation")
    end)

    on_install("iphoneos", function (package)
        import("core.base.semver")
        local modules = path.join(package:scriptdir(), "..", "..", "..", "modules")
        local swift = import("apple.swift", {rootdir = modules, anonymous = true})
        local toolchain = assert(package:toolchains(), "OpenCombine is built with the apple-ios toolchain")[1]
        toolchain:load()
        local runtime = assert(package:dep("swift-runtime"), "OpenCombine is compiled against charon@swift-runtime")
        local libcxx = assert(package:dep("libcxx"), "OpenCombine's C++ helper is compiled against charon@libcxx")
        local swiftc = assert(table.wrap((runtime:envs() or {}).SWIFT_EXEC)[1], "swift-runtime names no compiler; reinstall it")
        local minimum = toolchain:config("deployment")
        local triple = package:arch() .. "-apple-ios" .. minimum
        local sdk = toolchain:config("sdkdir")
        local swiftdir = path.join(package:installdir("lib"), "swift", "iphoneos")
        local helpers = path.join("Sources", "COpenCombineHelpers")
        local objects = path.absolute("objects")
        os.mkdir(objects)
        os.mkdir(swiftdir)

        os.cp(path.join(package:scriptdir(), "files", "DispatchTimeDistance.swift"), path.join("Sources", "OpenCombineDispatch"))

        if semver.compare(minimum, "7.0") < 0 then
            os.rm(path.join("Sources", "OpenCombineFoundation", "URLSession.swift"))
            local portability = path.join("Sources", "OpenCombineFoundation", "Helpers", "Portability.swift")
            local text, reads = io.readfile(portability):gsub("return CFRunLoopTimerGetTolerance%(underlyingTimer%)",
                "if #available(iOS 7.0, *) { return CFRunLoopTimerGetTolerance(underlyingTimer) }\n            return 0")
            local written, writes = text:gsub("CFRunLoopTimerSetTolerance%(underlyingTimer, newValue%)",
                "if #available(iOS 7.0, *) { CFRunLoopTimerSetTolerance(underlyingTimer, newValue) }")
            assert(reads == 1 and writes == 1, "OpenCombine " .. package:version_str() ..
                   " no longer reads and sets a timer's tolerance the way this recipe guards")
            io.writefile(portability, written)
        end

        os.vrunv(toolchain:tool("cxx"), {"-target", triple, "-isysroot", sdk, "-nostdinc++", "-isystem",
                 path.join(libcxx:installdir("include"), "c++", "v1"), "-std=c++17", "-O2", "-include", "exception",
                 "-I", path.join(helpers, "include"), "-c", path.join(helpers, "COpenCombineHelpers.cpp"),
                 "-o", path.join(objects, "COpenCombineHelpers.o")})
        os.vrunv(toolchain:tool("ar"), {"-rcs", path.join(package:installdir("lib"), "libCOpenCombineHelpers.a"),
                 path.join(objects, "COpenCombineHelpers.o")})
        os.cp(path.join(helpers, "include", "*"), path.join(package:installdir("include"), "COpenCombineHelpers") .. "/")

        for _, name in ipairs({"OpenCombine", "OpenCombineDispatch", "OpenCombineFoundation"}) do
            local object = path.join(objects, name .. ".o")
            local module = path.join(swiftdir, name .. ".swiftmodule")
            os.mkdir(module)
            local argv = table.join(swift.runtime_flags({
                architecture = package:arch(), deployment = minimum, sdk = sdk,
                resources = path.join(runtime:installdir(), "lib", "swift"),
                plugins = table.wrap((runtime:envs() or {}).SWIFT_PLUGIN_PATH)[1],
                module = name, optimize = "fastest", prefix_map = os.curdir() .. "=/opencombine"}),
                {"-I", swiftdir, "-I", path.join(helpers, "include"), "-emit-module", "-emit-module-path",
                 path.join(module, package:arch() .. "-apple-ios.swiftmodule"), "-c"},
                os.files(path.join("Sources", name, "**.swift")), {"-o", object})
            os.vrunv(swiftc, argv)
            os.vrunv(toolchain:tool("ar"), {"-rcs", path.join(package:installdir("lib"), "lib" .. name .. ".a"), object})
        end

        package:setenv("CHARON_SWIFT_MODULES", swiftdir, path.join(package:installdir("include"), "COpenCombineHelpers"))
        os.cp("LICENSE", package:installdir("licenses"))
    end)
