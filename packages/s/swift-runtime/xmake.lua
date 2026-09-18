package("swift-runtime")
    set_homepage("https://www.swift.org")
    set_description("The Swift runtime an iOS older than Swift itself does not ship: the standard library, concurrency, synchronization, regular expressions and observation, built for the port's architecture and oldest release from the sources of the swift package")
    set_license("Apache-2.0 WITH Swift-exception")
    set_policy("package.strict_compatibility", true)

    -- The runtime is built from the sources the swift package installs; what this download brings is the C library's
    -- overlay, which that release no longer carries.
    add_urls("https://github.com/swiftlang/swift.git")
    add_versions("6.4.0", "b8189d766d86ad7fc8106787d6ce9e402f38dd72")

    add_deps("charon@swift 6.4.0", {alias = "swift", host = true, private = true, system = false})
    add_deps("charon@libcxx", {alias = "libcxx"})
    add_deps("charon@apple-compat", {alias = "apple-compat"})

    -- The libraries, in the order they are built: each one's modules are what the next ones compile against. The C library's
    -- Swift overlay comes from swift-6.2-RELEASE, the last release whose sources carry it, because Synchronization and
    -- Observation import Darwin and the SDK has only an interface for arm64.
    local libraries = {"swiftCore", "swiftSwiftOnoneSupport", "swift_Concurrency", "swiftDarwin", "swiftSynchronization",
                       "swift_RegexParser", "swift_StringProcessing", "swiftRegexBuilder", "swiftObservation"}

    -- What every image of the runtime and of the port renames, because the release the port is built for either does not
    -- have the call or gives it a narrower meaning.
    local renamed = {"clock_gettime", "clock_getres", "dispatch_get_global_queue"}

    -- The C library's Swift overlay: swift-6.2-RELEASE is the last release whose sources carry it (the build of the SDK
    -- overlays on Apple platforms was removed in 15345ef2d5), and the SDK ships only an arm64 interface of the module.
    local overlay = {tag = "swift-6.2-RELEASE", commit = "1ff1cc1170617ab23ab74aa8b741c8daca1903f6",
                     url = "https://github.com/swiftlang/swift.git"}

    on_download(function (package, opt)
        local checkout = import("checkout", {rootdir = path.join(package:scriptdir(), "..", "..", "..", "modules"), anonymous = true})
        checkout.pinned(opt.sourcedir, {{url = overlay.url, tag = overlay.tag, commit = overlay.commit,
                                         sparse = {"/stdlib/public/Platform/", "/LICENSE.txt"}}})
    end)

    local digests = {"xmake.lua=" .. hash.sha256(path.join(os.scriptdir(), "xmake.lua"))}
    for _, patch in ipairs(os.files(path.join(os.scriptdir(), "patches", "*.patch"))) do
        table.insert(digests, path.filename(patch) .. "=" .. hash.sha256(patch))
    end
    table.sort(digests)
    add_configs("recipe", {description = "The digest of this recipe and the changes it makes to the runtime's sources, so a changed flag or patch is a different runtime.", default = hash.strhash128(table.concat(digests, ";")), type = "string", readonly = true})

    on_load("iphoneos", function (package)
        for _, library in ipairs(libraries) do
            package:add("links", library)
        end
        package:add("linkdirs", path.join("lib", "swift", "iphoneos"))
        package:data_set("mark", "charon_swift_runtime_" .. package:buildhash())
    end)

    on_install("iphoneos", function (package)
        local modules = path.join(package:scriptdir(), "..", "..", "..", "modules")
        local swift = import("apple.swift", {rootdir = modules, anonymous = true})
        local cmake = import("apple.cmake", {rootdir = modules, anonymous = true})
        local compat = import("apple.compat", {rootdir = modules, anonymous = true})
        local compiler = assert(package:dep("swift"), "the runtime is built with charon@swift")
        local libcxx = assert(package:dep("libcxx"), "the runtime links the C++ runtime of charon@libcxx")
        local shims = assert(package:dep("apple-compat"), "the runtime takes what the release lacks from charon@apple-compat")
        local toolchain = cmake.toolchain(package)
        local minimum = toolchain:config("deployment")
        local triple = package:arch() .. "-apple-ios" .. minimum
        local swiftc = path.join(compiler:installdir("bin"), "swiftc")

        -- What a port needs to compile against this runtime, written where it is read from afterwards: the compiler this
        -- was built with, the way charon@swift-embedded names the one its modules were built with, its macro plugins, and
        -- the symbol a port binds to so that a program compiled against this build cannot be linked against another.
        package:setenv("SWIFT_EXEC", swiftc)
        package:setenv("SWIFT_PLUGIN_PATH", path.join(compiler:installdir("lib"), "swift", "host", "plugins"))
        package:setenv("CHARON_SWIFT_RUNTIME_MARK", package:data("mark"))
        local jobs = math.min(import("core.base.option").get("jobs") or os.cpuinfo("ncpu"), 8)
        local install = path.join(package:installdir("lib"), "swift")

        -- A writable copy of the sources: the changes below are made in it, and the standalone runtime build takes its
        -- copies of the standard library from it afterwards.
        -- A copy into a directory that is already there would land inside it, so what an install that failed halfway left
        -- behind goes first: the sources are copied, not kept.
        -- CMake takes the flags of a toolchain file only while their cache entries are unset, so a build tree an install
        -- that failed left behind would keep the flags of that run; this build makes its own.
        os.tryrm(path.absolute("build"))

        local source = path.absolute("swift-source")
        os.tryrm(source)
        os.vcp(path.join(compiler:installdir("share"), "swift-source"), source)
        local patches = os.files(path.join(package:scriptdir(), "patches", "*.patch"))
        table.sort(patches)
        for _, patch in ipairs(patches) do
            os.vrunv("patch", {"-p1", "-i", patch}, {curdir = source})
        end

        -- Every availability macro of the standard library becomes always available: the macros name the OS releases whose
        -- Swift runtime a library may rely on, and this runtime is the program's own, whatever the release.
        io.writefile(path.join(source, "utils", "availability-macros.def"), swift.bundled_availability(source))

        -- The standalone runtime build keeps its own copies of the standard library's sources; this brings them up to date
        -- with the changes above, and copies in the regular expression sources, which live in their own repository.
        -- The shims of the standard library reach the C library through static inline functions, and one of them calls
        -- openat, which iOS 8 brought. A call written inside a header of a clang module cannot be renamed from outside:
        -- a forced include reaches the file being compiled, not the module the header belongs to, which the compiler's
        -- own output shows. So the shims built here call apple-compat's function by name, which is that call itself
        -- where the release has it, and everything that reads them - the standard library, the overlay and a port's own
        -- Swift - reaches the shim.
        local overlay_shims = path.join(source, "stdlib", "public", "SwiftShims", "swift", "shims", "LibcOverlayShims.h")
        local renamed_shims, calls = io.readfile(overlay_shims):gsub("return openat%(", "return charon_openat(")
        assert(calls == 1, "the shims of Swift " .. package:version_str() ..
               " no longer call openat exactly once, and this runtime would ship a header that does not say what it does")
        local declared, declarations = renamed_shims:gsub("(int static inline _swift_stdlib_openat)",
                                                          "extern int charon_openat(int directory, const char *path, int flags, ...);\n%1", 1)
        assert(declarations == 1, "the shims of Swift " .. package:version_str() .. " no longer declare _swift_stdlib_openat as they did")
        io.writefile(overlay_shims, declared)

        os.vrunv("cmake", {"-DStringProcessing_ROOT_DIR=" .. compiler:installdir("share"), "-P",
                           path.join(source, "Runtimes", "Resync.cmake")})
        assert(os.isdir(path.join(source, "Runtimes", "Supplemental", "StringProcessing", "_RegexParser")),
               "the resync left the regular expression libraries without sources; the swift package installs them beside the release's")

        -- The mark every image of a port binds to, so that a program built against one build of this runtime cannot be
        -- linked against another: the libraries carry no ABI stability, and everything is compiled together.
        local mark = package:data("mark")
        io.writefile("mark.c", string.format("/* The build of the Swift runtime a program was compiled against. */\n__attribute__((visibility(\"default\")))\nconst char %s = 0;\n", mark))
        os.vrunv(toolchain:tool("cc"), {"-target", triple, "-miphoneos-version-min=" .. minimum, "-isysroot",
                 toolchain:config("sdkdir"), "-Os", "-c", "mark.c", "-o", path.absolute("mark.o")})

        -- The Swift driver hands the link to clang, which reads the linker's version to know what it understands; the
        -- toolchain names the one the port links with, and clang would otherwise assume the one it shipped against.
        local linker_version = toolchain:config("linker_version") and
                               {"-Xclang-linker", "-mlinker-version=" .. toolchain:config("linker_version")} or {}

        -- The linker the port links with, in the Swift driver's spelling. Where nothing names it the driver's clang finds
        -- the host's own, which reads a 32-bit image's absolute symbols as offsets and refuses the standard library's
        -- immortal reference count ("vmOffset too large for __swiftImmortalRefCount").
        local use_ld = {}
        for _, flag in ipairs(table.wrap(toolchain:get("shflags"))) do
            if flag:startswith("-fuse-ld=") then
                use_ld = {"-use-ld=" .. flag:sub(#"-fuse-ld=" + 1)}
            end
        end

        local includes = compat.force_includes(shims, renamed)
        local shim_library = os.isfile(path.join(shims:installdir("lib"), "libapple-compat.a")) and
                             {"-L" .. shims:installdir("lib"), "-lapple-compat"} or {}
        local runtime_flags = table.join({"-clang-target", triple, "-Xfrontend", "-bundled-swift-runtime",
                                          "-runtime-compatibility-version", "none",
                                          "-disable-autolinking-runtime-compatibility-dynamic-replacements",
                                          "-Xfrontend", "-disable-autolinking-runtime-compatibility-concurrency",
                                          "-tools-directory", path.directory(toolchain:tool("cc")),
                                          "-sdk", toolchain:config("sdkdir"),
                                          "-Xclang-linker", "-nostdlib++"}, linker_version, {
                                          "-L" .. libcxx:installdir("lib"), "-lc++", "-lc++abi"}, shim_library)
        local linked = table.join({"-nostdlib++", "-L" .. libcxx:installdir("lib"), "-lc++", "-lc++abi"}, shim_library)

        -- CMake takes the flags of a language from the toolchain file only while its cache entry is unset, so a build that
        -- needs its own flags gets its own toolchain file rather than a -DCMAKE_<LANG>_FLAGS that would drop the rest.
        local function toolchain_file(name, extra)
            extra = extra or {}
            return cmake.toolchain_file(package, {
                system = "Darwin", builddir = path.absolute(path.join("build", name)),
                cflags = includes, cxxflags = table.join(includes, extra.cxxflags or {}), ldflags = linked,
                shflags = extra.shflags or {},
                swift = {compiler = swiftc, flags = table.join(runtime_flags, extra.swiftflags or {})}})
        end

        local ninja = assert(import("lib.detect.find_tool")("ninja"), "ninja builds the Swift runtime").program
        local function configure(name, sourcedir, extra, configs)
            local builddir = path.absolute(path.join("build", name))
            os.vrunv("cmake", table.join({"-G", "Ninja", "-S", sourcedir, "-B", builddir,
                "-DCMAKE_TOOLCHAIN_FILE=" .. toolchain_file(name, extra), "-DCMAKE_POLICY_DEFAULT_CMP0195=NEW",
                "-DCMAKE_BUILD_TYPE=Release", "-DBUILD_SHARED_LIBS=ON", "-DCMAKE_INSTALL_PREFIX=" .. package:installdir(),
                "-DCMAKE_INSTALL_LIBDIR=lib", "-DCMAKE_MAKE_PROGRAM=" .. ninja}, configs))
            os.vrunv(ninja, {"-C", builddir, "-j" .. jobs})
            os.vrunv("cmake", {"--install", builddir})
        end

        -- The standard library, the runtime and concurrency. Library evolution is off: the runtime ships with the program,
        -- so nothing needs ABI stability, and a resilient layout would make a client's class need the metadata update of
        -- iOS 12's Objective-C runtime, which the releases this is for do not have.
        configure("core", path.join(source, "Runtimes", "Core"), {
            -- The compiler emits the pre-stable Swift bit for a deployment target below 12.2, and the runtime hardcodes the
            -- stable one on Apple platforms; built this way, a Swift class is recognised as one. The layouts of the
            -- resilient types of older releases are not there to read, and with library evolution off every type this
            -- runtime has is laid out here.
            cxxflags = {"-DSWIFT_CLASS_IS_SWIFT_MASK=1ULL"},
            swiftflags = {"-Xfrontend", "-disable-legacy-type-info"},
            shflags = {path.absolute("mark.o")}
        }, {
            "-DSwiftCore_SWIFTC_SOURCE_DIR=" .. source,
            "-DSwiftCore_ARCH_SUBDIR=" .. package:arch(), "-DSwiftCore_PLATFORM_SUBDIR=iphoneos",
            "-DSwiftCore_MODULE_TRIPLE=" .. package:arch() .. "-apple-ios",
            "-Ddispatch_IMPLIB=" .. path.join(toolchain:config("sdkdir"), "usr", "lib", "libSystem.tbd"),
            "-Ddispatch_INCLUDE_DIR=" .. path.join(toolchain:config("sdkdir"), "usr", "include"),
            "-DSwiftCore_ENABLE_CRASH_REPORTER_CLIENT=OFF", "-DSwiftCore_ENABLE_BACKTRACING=OFF",
            "-DSwiftCore_ENABLE_STDLIB_TRACING=OFF", "-DSwiftCore_ENABLE_CONCURRENCY=ON",
            "-DSwiftCore_ENABLE_STRICT_AVAILABILITY=OFF", "-DSwiftCore_ENABLE_LIBRARY_EVOLUTION=OFF",
            "-DSwiftCore_ENABLE_OBJC_INTEROP=ON", "-DSwiftCore_ENABLE_TYPE_PRINTING=ON", "-DSwiftCore_ENABLE_REFLECTION=ON",
            "-DSwiftCore_INSTALL_NESTED_SUBDIR=OFF"})

        -- A resource directory the compiler accepts: its own shims and clang headers beside the runtime built here, under
        -- the platform folder the target names.
        local resources = path.absolute(path.join("build", "resources"))
        local platform = path.join(resources, "iphoneos")
        os.mkdir(platform)
        -- The shims are the ones the standard library just installed; the rest belong to the compiler. Two paths to the
        -- same clang headers in one build would leave two modules of the same name, and a compile that reads both stops.
        os.ln(path.join(install, "shims"), path.join(resources, "shims"))
        for _, entry in ipairs({"clang", "apinotes", "module.modulemap"}) do
            os.ln(path.join(compiler:installdir("lib"), "swift", entry), path.join(resources, entry))
        end
        local function offer(pattern)
            for _, built in ipairs(os.filedirs(pattern)) do
                os.tryrm(path.join(platform, path.filename(built)))
                os.ln(built, path.join(platform, path.filename(built)))
            end
        end
        offer(path.join(install, "*.swiftmodule"))
        offer(path.join(install, "*.dylib"))

        -- The C library's overlay, which the SDK has only as an interface for another architecture. It is built the way the
        -- release that still carried it did: the generated sources, the platform sources and the error types.
        local platform_source = path.join(path.absolute("stdlib"), "public", "Platform")
        local generated = path.absolute(path.join("build", "overlay"))
        os.mkdir(generated)
        local overlay_sources = {}
        for _, name in ipairs({"Darwin", "tgmath"}) do
            local output = path.join(generated, name .. ".swift")
            os.vrunv("python3", {path.join(source, "utils", "gyb.py"),
                                 "-DCMAKE_SIZEOF_VOID_P=" .. (package:arch() == "arm64" and "8" or "4"),
                                 "--line-directive", "", "-o", output, path.join(platform_source, name .. ".swift.gyb")})
            table.insert(overlay_sources, output)
        end
        for _, name in ipairs({"Platform.swift", "TiocConstants.swift", "POSIXError.swift", "MachError.swift"}) do
            table.insert(overlay_sources, path.join(platform_source, name))
        end
        local overlay_flags = table.join({"-target", triple, "-resource-dir", resources, "-module-name", "Darwin",
                                          "-parse-as-library", "-swift-version", "5", "-O", "-wmo",
                                          "-Xfrontend", "-disable-implicit-concurrency-module-import",
                                          "-Xfrontend", "-disable-implicit-string-processing-module-import",
                                          "-Xfrontend", "-disable-objc-attr-requires-foundation-module"}, use_ld,
                                         runtime_flags, swift.availability(source))
        -- The module is installed the way the ones built above are, a directory holding the module of this target's triple.
        -- A single file beside them is read on a release the SDK has no Swift for, and passed over where it has one: on
        -- arm64 the compiler would take the SDK's own Darwin interface instead of this overlay.
        local darwin_module = path.join(install, "Darwin.swiftmodule")
        os.mkdir(darwin_module)
        os.vrunv(swiftc, table.join(overlay_flags, {"-emit-module", "-emit-module-path",
                 path.join(darwin_module, package:arch() .. "-apple-ios.swiftmodule"),
                 "-emit-object", "-module-link-name", "swiftDarwin", "-o", path.join(generated, "Darwin.o")}, overlay_sources))
        os.vrunv(swiftc, table.join(overlay_flags, {"-emit-library", "-o", path.join(install, "libswiftDarwin.dylib"),
                 path.join(generated, "Darwin.o"), "-Xlinker", "-install_name", "-Xlinker", "@rpath/libswiftDarwin.dylib",
                 "-L" .. install, "-lswiftCore"}))
        offer(path.join(install, "Darwin.swiftmodule"))
        offer(path.join(install, "libswiftDarwin.dylib"))

        -- The supplemental libraries, each its own project, against the standard library built above.
        for _, library in ipairs({"Synchronization", "Observation", "StringProcessing"}) do
            configure(library:lower(), path.join(source, "Runtimes", "Supplemental", library),
                      {swiftflags = {"-resource-dir", resources}}, {
                "-DSwiftCore_DIR=" .. path.join(package:installdir("lib"), "cmake", "SwiftCore"),
                "-DCMAKE_FIND_PACKAGE_PREFER_CONFIG=YES"})
            offer(path.join(install, "*.swiftmodule"))
            offer(path.join(install, "iphoneos", "*.swiftmodule"))
            offer(path.join(install, "iphoneos", package:arch(), "*.dylib"))
        end

        -- What is installed is a resource directory, the layout the compiler reads: the shims, the clang headers and the
        -- API notes of the compiler at the root, and under the platform's folder the libraries and their modules,
        -- whichever subdirectory each project installed them into. A port compiles against this directory, so it needs
        -- nothing of the compiler beside the compiler itself.
        local platform_dir = path.join(install, "iphoneos")
        os.mkdir(platform_dir)
        for _, built in ipairs(table.join(os.filedirs(path.join(install, "*.swiftmodule")), os.files(path.join(install, "*.dylib")),
                                          os.files(path.join(platform_dir, package:arch(), "*.dylib")))) do
            os.vmv(built, path.join(platform_dir, path.filename(built)))
        end
        os.tryrm(path.join(platform_dir, package:arch()))
        -- What a port reads beside the shims the standard library installed: the clang headers, the API notes and the
        -- module map of the compiler this was built with, so a port passes one directory and needs nothing else.
        for _, entry in ipairs({"clang", "apinotes", "module.modulemap"}) do
            os.tryrm(path.join(install, entry))
            os.vcp(path.join(compiler:installdir("lib"), "swift", entry), path.join(install, entry))
        end
        os.vcp(path.join(path.absolute("."), "LICENSE.txt"), package:installdir("licenses") .. "/")
        os.tryrm(path.absolute("build"))
        os.tryrm(source)
    end)

    on_test(function (package)
        local swift = import("apple.swift", {rootdir = path.join(package:scriptdir(), "..", "..", "..", "modules"), anonymous = true})
        local resources = path.join(package:installdir("lib"), "swift")
        local install = path.join(resources, "iphoneos")
        for _, library in ipairs({"swiftCore", "swift_Concurrency", "swiftDarwin", "swiftSynchronization", "swiftObservation",
                                  "swift_StringProcessing", "swift_RegexParser", "swiftRegexBuilder"}) do
            assert(os.isfile(path.join(install, "lib" .. library .. ".dylib")), "the runtime has no lib" .. library .. ".dylib")
        end
        for _, module in ipairs({"Swift", "_Concurrency", "Darwin", "Synchronization", "Observation", "_StringProcessing"}) do
            assert(os.isdir(path.join(install, module .. ".swiftmodule")) or os.isfile(path.join(install, module .. ".swiftmodule")),
                   "the runtime has no " .. module .. " module")
        end
        -- What a port passes as its resource directory is this one, so the compiler's own parts are here too.
        for _, entry in ipairs({"shims", "clang", "apinotes", "module.modulemap"}) do
            assert(os.exists(path.join(resources, entry)),
                   "the runtime installs no " .. entry .. ", and a port could not use it as a resource directory")
        end
        local exported = os.iorunv("xcrun", {"nm", "-gU", path.join(install, "libswiftCore.dylib")})
        assert(exported:find("%s_" .. package:data("mark") .. "%s"),
               "libswiftCore.dylib does not carry the mark of the build it is, so a program could be linked against another")

        -- The modules of this runtime are the ones a port compiles against. Where the SDK carries Swift for an
        -- architecture - it does for arm64 - its own module of the same name is a candidate too, and a port that read it
        -- would compile against the API of the SDK's release and link against the libraries here.
        local toolchain = assert(package:toolchains(), "the runtime is built with the apple-ios toolchain")[1]
        toolchain:load()
        local compiler = assert(package:dep("swift"), "the runtime is built with charon@swift")
        local source = os.tmpfile() .. ".swift"
        io.writefile(source, "import Darwin\nimport Synchronization\npublic func held() -> Int32 { return Darwin.getpid() }\n")
        local _, loaded = os.iorunv(path.join(compiler:installdir("bin"), "swiftc"),
                                 {"-target", package:arch() .. "-apple-ios" .. toolchain:config("deployment"),
                                  "-clang-target", package:arch() .. "-apple-ios" .. toolchain:config("deployment"),
                                  "-sdk", toolchain:config("sdkdir"), "-resource-dir", resources, "-Rmodule-loading",
                                  "-Xfrontend", "-bundled-swift-runtime", "-typecheck", source})
        for _, module in ipairs({"Darwin", "Synchronization", "Swift"}) do
            local from = loaded:match("loaded module '" .. module .. "'; source: '([^']*)'")
            assert(from and from:startswith(resources),
                   "a port would compile against " .. module .. " from " .. (from or "nowhere") .. ", not against this runtime's own")
        end
        os.tryrm(source)

        -- The mark is what a port binds to, so a program built against this runtime does not link against another build of
        -- it: these libraries carry no ABI stability, and a mismatch has to be a link that fails, not a program that runs.
        local folder = os.tmpfile() .. ".dir"
        os.mkdir(folder)
        io.writefile(path.join(folder, "port.c"), "int main(void) { return 0; }\n")
        local common = {"-target", package:arch() .. "-apple-ios", "-miphoneos-version-min=" .. toolchain:config("deployment"),
                        "-isysroot", toolchain:config("sdkdir"), "-Wno-incompatible-sysroot"}
        for _, flag in ipairs(table.wrap(toolchain:get("shflags"))) do
            if flag:startswith("-fuse-ld=") or flag:startswith("-mlinker-version=") then
                table.insert(common, flag)
            end
        end
        local function links(mark)
            return try { function ()
                os.vrunv(toolchain:tool("cc"), table.join(common, {path.join(folder, "port.c"), "-L" .. install, "-lswiftCore",
                         "-Wl,-u,_" .. mark, "-o", path.join(folder, "port")}))
                return true
            end }
        end
        assert(links(package:data("mark")), "a port must link against the runtime it was built against, by its mark")
        assert(not links("charon_swift_runtime_not_this_build"),
               "a port must not link against a runtime whose mark it does not name; the mark is what keeps builds apart")
        os.tryrm(folder)
    end)
