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
    local libraries = {"swiftCore", "swiftSwiftOnoneSupport", "swift_Concurrency", "swiftDarwin", "swiftObjectiveC", "swiftDispatch",
                       "swiftCoreFoundation", "swiftCoreGraphics", "swiftFoundation", "swiftQuartzCore", "swiftUIKit", "swiftCoreData",
                       "swiftSynchronization",
                       "swift_RegexParser", "swift_StringProcessing", "swiftRegexBuilder", "swiftObservation"}

    -- What every image of the runtime and of the port renames, because the release the port is built for either does not
    -- have the call or gives it a narrower meaning.
    local renamed = {"clock_gettime", "clock_getres", "dispatch_get_global_queue"}

    -- With the backports, the files of Foundation's overlay whose iOS 7 marks stay: what they mark the backports do not
    -- carry. Found by building without the marks and reading what the compiler refused: Progress has no entry in the
    -- registry, and the options of NSCalendar and of NSData's base64 are types the headers alone declare, which the
    -- registry does not name yet.
    local still_ios7 = {["Progress.swift"] = true, ["Calendar.swift"] = true, ["Data.swift"] = true}

    -- With the backports, the files of Foundation's overlay whose own marks of iOS 7 to 11 come down to the port's release:
    -- their Swift wraps classes the backports implement. The overlay is compiled against the lifted headers, so a mark
    -- lowered over a call the backports do not carry is refused there.
    -- URL.swift, DateComponents.swift, NSCoder.swift and Measurement.swift are not here: each also marks API the backports
    -- leave out (resource keys and security scope, a component's value, NSCoderValueNotFoundError, MeasurementFormatter),
    -- which the compiler refused when their marks came down.
    local lowered_with_backports = {"URLComponents.swift", "DateInterval.swift", "NSStringAPI.swift"}

    -- The overlays of the system's own frameworks, each taken from the last release whose sources carry it. The C
    -- library's went in swift-6.2 (the build of the SDK overlays on Apple platforms was removed in 15345ef2d5) and the
    -- SDK ships only an arm64 interface of that module; the overlays of Objective-C and the frameworks above it went
    -- earlier, and swift-5.4.3 is the last release that has them: swift-5.5 has no stdlib/public/Darwin at all.
    local sources = {
        {name = "platform", tag = "swift-6.2-RELEASE", commit = "1ff1cc1170617ab23ab74aa8b741c8daca1903f6",
         url = "https://github.com/swiftlang/swift.git", sparse = {"/stdlib/public/Platform/", "/LICENSE.txt"}},
        {name = "overlays", tag = "swift-5.4.3-RELEASE", commit = "282fe25d1757ff9974ade028d92111acdae6876a",
         url = "https://github.com/swiftlang/swift.git",
         sparse = {"/stdlib/public/Darwin/ObjectiveC/", "/stdlib/public/Darwin/Dispatch/", "/stdlib/public/Darwin/CoreFoundation/",
                   "/stdlib/public/Darwin/CoreGraphics/", "/stdlib/public/SwiftShims/ObjectiveCOverlayShims.h",
                   "/stdlib/public/SwiftShims/DispatchOverlayShims.h", "/stdlib/public/Darwin/Foundation/",
                   "/stdlib/public/SwiftShims/Foundation*.h", "/stdlib/public/SwiftShims/NS*Shims.h",
                   "/stdlib/public/SwiftShims/CoreFoundationOverlayShims.h", "/stdlib/public/SwiftShims/CF*Shims.h", "/LICENSE.txt"}},
        -- UIKit's, QuartzCore's and CoreData's went before the others: swift-5.2.5 is the last release that has them.
        {name = "uikit", tag = "swift-5.2.5-RELEASE", commit = "71d85a7c28eed8f46241649a723ddf23989139c6",
         url = "https://github.com/swiftlang/swift.git",
         sparse = {"/stdlib/public/Darwin/UIKit/", "/stdlib/public/Darwin/QuartzCore/", "/stdlib/public/Darwin/CoreData/",
                   "/stdlib/public/SwiftShims/UIKitOverlayShims.h",
                   "/LICENSE.txt"}}
    }

    on_download(function (package, opt)
        local checkout = import("checkout", {rootdir = path.join(package:scriptdir(), "..", "..", "..", "modules"), anonymous = true})
        checkout.pinned(opt.sourcedir, sources)
    end)

    local digests = {"xmake.lua=" .. hash.sha256(path.join(os.scriptdir(), "xmake.lua"))}
    for _, patch in ipairs(os.files(path.join(os.scriptdir(), "patches", "**.patch"))) do
        table.insert(digests, path.relative(patch, path.join(os.scriptdir(), "patches")) .. "=" .. hash.sha256(patch))
    end
    table.insert(digests, "shared_runtime.lua=" .. hash.sha256(path.join(os.scriptdir(), "..", "..", "..", "modules", "apple", "shared_runtime.lua")))
    table.sort(digests)
    add_configs("recipe", {description = "The digest of this recipe and the changes it makes to the runtime's sources, so a changed flag or patch is a different runtime.", default = hash.strhash128(table.concat(digests, ";")), type = "string", readonly = true})

    -- With the backports, what they implement of later releases is available from the port's release: the overlays are
    -- built against headers that say so and linked against the backports' libraries, and a port compiles against the
    -- same headers (modules/apple/lift.lua).
    add_configs("backports", {description = "Build the overlays for a port that carries charon@apple-backports: API the backports implement is available from the port's release, in the overlays and in the port's own Swift.", default = false, type = "boolean"})

    -- The application half of it: UIKit's overlay is linked against the UIKit backports too. A daemon has no use for that
    -- library, and loading it would pull UIKit into the process, so it is a config of its own.
    add_configs("backports_uikit", {description = "With backports: link the overlay of UIKit against libUIKitBackports, for an application that carries charon@apple-backports with its uikit config.", default = false, type = "boolean"})

    -- The runtime as a package of its own, /usr/lib/charon/org.charon.swift-runtime-<build>, that programs depend on and
    -- share, instead of libraries each of them carries. The build is part of the name: with no library evolution a program
    -- runs only against the build it was compiled with (see the mark).
    add_configs("shared", {description = "Install the libraries under absolute install names and write a Debian package that holds them, which the programs built against this runtime depend on instead of carrying the libraries.", default = false, type = "boolean"})

    on_load("iphoneos", function (package)
        if package:config("shared") then
            package:add("deps", "charon@ldid 2.1.5-procursus7+23.gaf86971", {alias = "ldid"})
        end
        if package:config("backports_uikit") and not package:config("backports") then
            raise("swift-runtime's backports_uikit config is the application half of the backports config; set backports too")
        end
        if package:config("backports") then
            -- Foundation's and CoreData's backports: UIKit's overlay keeps the marks its release wrote, so it reaches
            -- nothing the UIKit backports carry, and a daemon built against this runtime keeps UIKit out of its process.
            package:add("deps", "charon@apple-backports", {alias = "apple-backports", configs = {coredata = true, uikit = package:config("backports_uikit") or nil}})
        end
        for _, library in ipairs(libraries) do
            package:add("links", library)
        end
        if package:config("shared") then
            local runtime = import("apple.shared_runtime", {rootdir = path.join(package:scriptdir(), "..", "..", "..", "modules"), anonymous = true})
            package:add("linkdirs", path.join("share", "root", "usr", "lib", "charon", runtime.package_name(package:buildhash())))
        else
            package:add("linkdirs", path.join("lib", "swift", "iphoneos"))
        end
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
        local platform_source = path.join(path.absolute("platform"), "stdlib", "public", "Platform")
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

        -- The overlay of Objective-C: what a port needs to write a selector, to read a BOOL as a Bool and to hold an
        -- autorelease pool. It is the release's own source, built against the C library's overlay as its own build did.
        -- Its shim goes in beside the shims the standard library installed, because those are the ones every build here
        -- reads and the ones a port is given; the standard library installs a list of its own and would not carry it.
        -- The overlays above it are the release's own sources too, built by today's compiler in the language mode they were
        -- written for. What of them the SDK of today no longer lets them write is changed by the patches beside them.
        local overlays = path.absolute("overlays")
        local overlay_patches = os.files(path.join(package:scriptdir(), "patches", "overlays", "*.patch"))
        table.sort(overlay_patches)
        for _, patch in ipairs(overlay_patches) do
            os.vrunv("patch", {"-p1", "-i", patch}, {curdir = overlays})
        end
        -- The backports variant: the headers with what the backports implement lowered to the port's release, for the
        -- overlays here and for every port that compiles against this runtime, which finds them through the environment.
        local lifted, carried = {}, {}
        local backported = package:dep("apple-backports")
        if package:config("backports") then
            local lift = import("apple.lift", {rootdir = modules, anonymous = true})
            local result = lift.lift({clang = toolchain:tool("cc"), sdk = toolchain:config("sdkdir"), triple = triple, minimum = minimum,
                                      registry = backported:installdir("share"), outputdir = path.join(package:installdir("share"), "lift")})
            print("lifted %d marks in %d headers for %d implemented API; %d not declared by the SDK's headers",
                  result.lifted, result.headers, result.implemented, #result.unmatched)
            lifted = {"-vfsoverlay", result.vfs}
            package:setenv("CHARON_SWIFT_LIFTED_HEADERS", result.vfs)
            -- the configs of apple-backports whose libraries the overlays link, which a port must carry as well
            package:setenv("CHARON_SWIFT_RUNTIME_BACKPORTS", package:config("backports_uikit") and "coredata,uikit" or "coredata")
            carried.FoundationBackports = path.join(backported:installdir("lib"), "libFoundationBackports.dylib")
            carried.CoreDataBackports = path.join(backported:installdir("lib"), "libCoreDataBackports.dylib")
            if package:config("backports_uikit") then
                carried.UIKitBackports = path.join(backported:installdir("lib"), "libUIKitBackports.dylib")
            end
            -- The marks the Foundation patch puts on what came with iOS 7 are left out where the backports carry it; what
            -- stays marked is what they do not, named here so that it is a decision rather than a guess.
            local foundation = path.join(overlays, "stdlib", "public", "Darwin", "Foundation")
            for _, file in ipairs(os.files(path.join(foundation, "*.swift"))) do
                if not still_ios7[path.filename(file)] then
                    io.writefile(file, (io.readfile(file):gsub("\n[ \t]*@available%(macOS 10%.9, iOS 7%.0, %*%)\n", "\n")))
                end
            end
            for _, name in ipairs(lowered_with_backports) do
                local file = path.join(foundation, name)
                io.writefile(file, (io.readfile(file):gsub("@available%(([^)]*)%)", function (arguments)
                    return "@available(" .. arguments:gsub("iOS (%d+)%.(%d+)", function (major, minor)
                        local release = tonumber(major)
                        return (release >= 7 and release <= 11) and "iOS " .. minimum or "iOS " .. major .. "." .. minor
                    end) .. ")"
                end)))
            end
        end
        local installed_shims = path.join(install, "shims")
        local shim_modules = path.join(installed_shims, "module.modulemap")
        for _, name in ipairs({"ObjectiveC", "Dispatch", "CoreFoundation", "Foundation"}) do
            os.vcp(path.join(overlays, "stdlib", "public", "SwiftShims", name .. "OverlayShims.h"), installed_shims .. "/")
            local module = "_Swift" .. name .. "OverlayShims"
            if not io.readfile(shim_modules):find(module, 1, true) then
                io.writefile(shim_modules, io.readfile(shim_modules) ..
                             string.format("\nmodule %s {\n  header \"%sOverlayShims.h\"\n}\n", module, name))
            end
        end
        -- The overlay of Foundation reads its shims through the headers they include, one per class or type it reaches.
        local shim_headers = table.join(os.files(path.join(overlays, "stdlib", "public", "SwiftShims", "NS*Shims.h")),
                                        os.files(path.join(overlays, "stdlib", "public", "SwiftShims", "CF*Shims.h")))
        for _, header in ipairs(shim_headers) do
            os.vcp(header, installed_shims .. "/")
        end
        os.vcp(path.join(overlays, "stdlib", "public", "SwiftShims", "FoundationShimSupport.h"), installed_shims .. "/")
        local uikit = path.absolute("uikit")
        local uikit_patches = os.files(path.join(package:scriptdir(), "patches", "uikit", "*.patch"))
        table.sort(uikit_patches)
        for _, patch in ipairs(uikit_patches) do
            os.vrunv("patch", {"-p1", "-i", patch}, {curdir = uikit})
        end
        if package:config("backports_uikit") then
            -- What the UIKit backports carry of the iOS 11 wrappers: UIFontMetrics through UIFont.TextStyle.metrics, and the
            -- comparison of content size categories, from iOS 7 where the type came. NSDirectionalEdgeInsets stays marked (the registry does not carry
            -- every user of the type), and so do the focus and drag and drop wrappers, which nobody carries.
            local file = path.join(uikit, "stdlib", "public", "Darwin", "UIKit", "UIKit.swift")
            local text = io.readfile(file)
            local function lowered(block)
                return (block:gsub("@available%(iOS 11%.0", "@available(iOS " .. minimum))
            end
            local count
            text, count = text:gsub("(extension UIFont%.TextStyle {.-\n})", lowered)
            assert(count == 1, "UIKit.swift has no extension of UIFont.TextStyle")
            -- UIContentSizeCategory itself stays at iOS 7 (one of its users, a limit on a view, is iOS 15 and not carried),
            -- and a member cannot be more available than the extension that holds it: its comparison comes down to 7
            text, count = text:gsub("(extension UIContentSizeCategory {.-\n}\n)", function (block)
                return (block:gsub("@available%(iOS 11%.0", "@available(iOS 7.0"))
            end)
            assert(count == 1, "UIKit.swift has no extension of UIContentSizeCategory")
            io.writefile(file, text)
        end
        os.vcp(path.join(uikit, "stdlib", "public", "SwiftShims", "UIKitOverlayShims.h"), installed_shims .. "/")
        if not io.readfile(shim_modules):find("_SwiftUIKitOverlayShims", 1, true) then
            io.writefile(shim_modules, io.readfile(shim_modules) ..
                         "\nmodule _SwiftUIKitOverlayShims {\n  header \"UIKitOverlayShims.h\"\n}\n")
        end
        local function overlay_sources_of(name, files)
            local found = {}
            for _, file in ipairs(files) do
                table.insert(found, path.join(overlays, "stdlib", "public", "Darwin", name, file))
            end
            return found
        end
        -- One overlay: its module, in the layout the others are installed in, and its library, which a port finds by the
        -- run path it carries.
        local function build_overlay(name, overlay_sources, links, objects, opt)
            local module = path.join(install, name .. ".swiftmodule")
            os.mkdir(module)
            local flags = table.join({"-target", triple, "-resource-dir", resources, "-module-name", name,
                                      "-parse-as-library", "-swift-version", "5", "-O", "-wmo",
                                      "-Xfrontend", "-disable-implicit-string-processing-module-import"}, use_ld,
                                     (opt and opt.concurrency) and {} or {"-Xfrontend", "-disable-implicit-concurrency-module-import"},
                                     runtime_flags, swift.availability(source),
                                     -- the lifted headers only where the backports are linked: an overlay that does not
                                     -- carry them would bind what the headers now call available to the system's library
                                     (opt and opt.backports) and lifted or {})
            local object = path.join(generated, name .. ".o")
            -- The overlays built here are named to the linker by their paths, not by -l: the driver lists every framework
            -- before every -l, and today's SDK's Foundation exports the Swift symbols of its own overlay (marked as moved
            -- only for iOS 12.2 to 16), so an -lswiftFoundation behind -framework Foundation loses them to the system.
            local linked = {}
            -- ahead of the frameworks, for the same reason: the classes the backports carry are bound to them
            for _, library in ipairs(opt and opt.backports or {}) do
                if carried[library] then
                    table.insert(linked, carried[library])
                end
            end
            for _, link in ipairs(links) do
                local library = link:match("^%-l(swift.+)$")
                table.insert(linked, library and path.join(install, "lib" .. library .. ".dylib") or link)
            end
            os.vrunv(swiftc, table.join(flags, {"-emit-module", "-emit-module-path",
                     path.join(module, package:arch() .. "-apple-ios.swiftmodule"),
                     "-emit-object", "-module-link-name", "swift" .. name, "-o", object}, overlay_sources))
            os.vrunv(swiftc, table.join(flags, {"-emit-library", "-o", path.join(install, "libswift" .. name .. ".dylib"),
                     object, table.unpack(objects or {})}, {"-Xlinker", "-install_name", "-Xlinker", "@rpath/libswift" .. name .. ".dylib",
                     "-L" .. install, "-lswiftCore"}, linked))
            offer(module)
            offer(path.join(install, "libswift" .. name .. ".dylib"))
        end
        build_overlay("ObjectiveC", overlay_sources_of("ObjectiveC", {"ObjectiveC.swift"}), {"-lswiftDarwin"})
        -- Dispatch: its queues are Objective-C objects from iOS 6, which is what the overlay takes them for. Its constructor
        -- is Objective-C++, compiled the way the port's own C is; Schedulers+DispatchQueue.swift is left out, being Combine's.
        local dispatch_object = path.join(generated, "Dispatch.mm.o")
        os.vrunv(toolchain:tool("cc"), {"-target", triple, "-miphoneos-version-min=" .. minimum, "-isysroot",
                 -- It adds the protocols of libdispatch's sources to their class, and reads them from the headers the way
                 -- Swift does: the headers declare them only where OS_OBJECT_SWIFT3 is set, which importing them into Swift sets.
                 toolchain:config("sdkdir"), "-Os", "-DOS_OBJECT_SWIFT3=1", "-c",
                 path.join(overlays, "stdlib", "public", "Darwin", "Dispatch", "Dispatch.mm"),
                 "-o", dispatch_object})
        build_overlay("Dispatch", overlay_sources_of("Dispatch", {"Dispatch.swift", "Block.swift", "Data.swift", "IO.swift",
                                                                  "Private.swift", "Queue.swift", "Source.swift", "Time.swift"}),
                      {"-lswiftDarwin", "-lswiftObjectiveC"}, {dispatch_object})
        build_overlay("CoreFoundation", overlay_sources_of("CoreFoundation", {"CoreFoundation.swift"}),
                      {"-lswiftDarwin", "-framework", "CoreFoundation"})
        -- CGFloat is generated for the width of the target's pointer, as the release's own build generated it.
        local graphics = path.join(generated, "CGFloat.swift")
        os.vrunv("python3", {path.join(source, "utils", "gyb.py"),
                             "-DCMAKE_SIZEOF_VOID_P=" .. (package:arch() == "arm64" and "8" or "4"),
                             "--line-directive", "", "-o", graphics,
                             path.join(overlays, "stdlib", "public", "Darwin", "CoreGraphics", "CGFloat.swift.gyb")})
        -- Private.swift is left out: it is the release's migration aid, a declaration of each C call the overlay renamed,
        -- unavailable and ending in fatalError, and in the overlay's own module it hides the C calls the patches reach.
        build_overlay("CoreGraphics", table.join({graphics}, overlay_sources_of("CoreGraphics", {"CoreGraphics.swift", "Geometry.swift"})),
                      {"-lswiftDarwin", "-lswiftObjectiveC", "-lswiftCoreFoundation",
                       "-framework", "CoreGraphics", "-framework", "CoreFoundation"})

        -- Foundation: the release's sources but those of Combine, which no release before iOS 13 has, with its value types
        -- generated as its own build generated them and its two files of Objective-C compiled the way the port's own are.
        local foundation = path.join(overlays, "stdlib", "public", "Darwin", "Foundation")
        local values = path.join(generated, "NSValue.swift")
        os.vrunv("python3", {path.join(source, "utils", "gyb.py"), "-DCMAKE_SIZEOF_VOID_P=" .. (package:arch() == "arm64" and "8" or "4"),
                             "--line-directive", "", "-o", values, path.join(foundation, "NSValue.swift.gyb")})
        local foundation_objects = {}
        for _, file in ipairs({"DataThunks.m", "BundleLookup.mm"}) do
            local object = path.join(generated, file .. ".o")
            os.vrunv(toolchain:tool("cc"), {"-target", triple, "-miphoneos-version-min=" .. minimum, "-isysroot",
                     toolchain:config("sdkdir"), "-Os", "-I" .. path.join(source, "stdlib", "public", "SwiftShims"),
                     "-c", path.join(foundation, file), "-o", object})
            table.insert(foundation_objects, object)
        end
        build_overlay("Foundation", table.join({values}, overlay_sources_of("Foundation", {
            "AffineTransform.swift", "Boxing.swift", "Calendar.swift", "CharacterSet.swift",
            "CheckClass.swift", "Codable.swift", "Collections+DataProtocol.swift", "ContiguousBytes.swift",
            "Data.swift", "DataProtocol.swift", "Date.swift", "DateComponents.swift", "DateInterval.swift",
            "Decimal.swift", "DispatchData+DataProtocol.swift", "FileManager.swift", "Foundation.swift",
            "IndexPath.swift", "IndexSet.swift", "JSONEncoder.swift", "Locale.swift", "Measurement.swift",
            "Notification.swift", "NSArray.swift", "NSCoder.swift", "NSData+DataProtocol.swift",
            "NSDate.swift", "NSDictionary.swift", "NSError.swift", "NSExpression.swift",
            "NSFastEnumeration.swift", "NSGeometry.swift", "NSIndexSet.swift", "NSItemProvider.swift",
            "NSNumber.swift", "NSObject.swift", "NSOrderedCollectionDifference.swift", "NSPredicate.swift",
            "NSRange.swift", "NSSet.swift", "NSSortDescriptor.swift", "NSString.swift", "NSStringAPI.swift",
            "NSStringEncodings.swift", "NSTextCheckingResult.swift", "NSUndoManager.swift", "NSURL.swift",
            "PersonNameComponents.swift", "PlistEncoder.swift", "Pointers+DataProtocol.swift",
            "Progress.swift", "ReferenceConvertible.swift", "Scanner.swift", "String.swift", "TimeZone.swift",
            "URL.swift", "URLCache.swift", "URLComponents.swift", "URLRequest.swift", "URLSession.swift",
            "UUID.swift"})),
                      {"-lswiftDarwin", "-lswiftObjectiveC", "-lswiftDispatch", "-lswiftCoreFoundation", "-lswiftCoreGraphics",
                       "-framework", "Foundation", "-framework", "CoreFoundation"}, foundation_objects,
                      -- URLSession has async calls, which want the concurrency library the runtime already carries.
                      {concurrency = true, backports = {"FoundationBackports"}})

        -- QuartzCore and UIKit, from the release that last had them: CATransform3D and UIKit's structures cross to NSValue,
        -- UIKit's structures compare and are Codable, and its alert and action sheet take their buttons as variadic
        -- arguments through an initializer its one file of Objective-C adds.
        local function generated_from(folder, name)
            local output = path.join(generated, name)
            os.vrunv("python3", {path.join(source, "utils", "gyb.py"), "-DCMAKE_SIZEOF_VOID_P=" .. (package:arch() == "arm64" and "8" or "4"),
                                 "--line-directive", "", "-o", output, path.join(uikit, "stdlib", "public", "Darwin", folder, name .. ".gyb")})
            return output
        end
        local foundation_links = {"-lswiftDarwin", "-lswiftObjectiveC", "-lswiftDispatch", "-lswiftCoreFoundation",
                                  "-lswiftCoreGraphics", "-lswiftFoundation", "-framework", "Foundation", "-framework", "CoreFoundation"}
        build_overlay("QuartzCore", {generated_from("QuartzCore", "NSValue.swift")},
                      table.join(foundation_links, {"-framework", "QuartzCore"}))
        local initializers = path.join(generated, "DesignatedInitializers.mm.o")
        os.vrunv(toolchain:tool("cc"), {"-target", triple, "-miphoneos-version-min=" .. minimum, "-isysroot",
                 toolchain:config("sdkdir"), "-Os", "-c", path.join(uikit, "stdlib", "public", "Darwin", "UIKit", "DesignatedInitializers.mm"),
                 "-o", initializers})
        build_overlay("UIKit", {path.join(uikit, "stdlib", "public", "Darwin", "UIKit", "UIKit.swift"),
                                generated_from("UIKit", "UIKit_FoundationExtensions.swift")},
                      table.join(foundation_links, {"-lswiftQuartzCore", "-framework", "QuartzCore", "-framework", "UIKit"}), {initializers},
                      {backports = package:config("backports_uikit") and {"UIKitBackports", "FoundationBackports"} or nil})

        -- CoreData: the generic fetch and count of a context, CoreData's error codes as CocoaError's, and its one file of
        -- Objective-C, which makes the classes a fetch answers conform to NSFetchRequestResult where the release does not.
        local coredata = path.join(uikit, "stdlib", "public", "Darwin", "CoreData")
        local conformances = path.join(generated, "CoreData.mm.o")
        os.vrunv(toolchain:tool("cc"), {"-target", triple, "-miphoneos-version-min=" .. minimum, "-isysroot",
                 toolchain:config("sdkdir"), "-Os", "-c", path.join(coredata, "CoreData.mm"), "-o", conformances})
        build_overlay("CoreData", {path.join(coredata, "CocoaError.swift"), path.join(coredata, "NSManagedObjectContext.swift")},
                      table.join(foundation_links, {"-framework", "CoreData"}), {conformances},
                      {backports = {"FoundationBackports", "CoreDataBackports"}})

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
        os.vcp(path.join(path.absolute("platform"), "LICENSE.txt"), package:installdir("licenses") .. "/")
        if package:config("shared") then
            local runtime = import("apple.shared_runtime", {rootdir = modules, anonymous = true})
            local released
            local dyld = import("apple.dyld", {rootdir = modules, anonymous = true})
            for version in io.readfile(path.join(package:scriptdir(), "..", "..", "..", "addons", "c", "charon", "xmake.lua")):gmatch('add_versions%("v(%d[%d%.]*)"') do
                if not released or dyld.compare_versions(version, released) > 0 then
                    released = version
                end
            end
            -- libc++ and libc++abi ride in the runtime's folder under the names its libraries and a program link them by: a
            -- process has one copy of them, and the runtime relies on that copy's locks and thread-local storage.
            local extra = {}
            for _, leaf in ipairs({"libc++.1.dylib", "libc++abi.1.dylib"}) do
                local source = path.join(libcxx:installdir("lib"), leaf)
                assert(os.isfile(source), "the C++ runtime of charon@libcxx has no " .. leaf)
                table.insert(extra, {source = source, leaf = leaf})
            end
            local name = runtime.package_name(package:buildhash())
            local libraries = os.files(path.join(platform_dir, "*.dylib"))
            runtime.write({name = name, version = assert(released, "the addon recipe names no Charon release") .. "+" .. package:buildhash():sub(1, 8),
                           libraries = libraries, extra = extra,
                           root = path.join(package:installdir("share"), "root"), workdir = path.absolute("shared-work"),
                           outputdir = package:installdir("share"),
                           ldid = path.join(package:dep("ldid"):installdir(), "bin", "ldid"), strip = {"-x"}})
            -- A program links against the libraries in the package's tree, not against a second copy.
            for _, library in ipairs(libraries) do
                os.rm(library)
            end
            os.tryrm(path.absolute("shared-work"))
            package:setenv("CHARON_SWIFT_RUNTIME_SHARED", name)
        end
        os.tryrm(path.absolute("build"))
        os.tryrm(source)
    end)

    on_test(function (package)
        local swift = import("apple.swift", {rootdir = path.join(package:scriptdir(), "..", "..", "..", "modules"), anonymous = true})
        local resources = path.join(package:installdir("lib"), "swift")
        local install = path.join(resources, "iphoneos")
        local libraries = install
        if package:config("shared") then
            local shared = import("apple.shared_runtime", {rootdir = path.join(package:scriptdir(), "..", "..", "..", "modules"), anonymous = true})
            libraries = path.join(package:installdir("share"), "root", shared.folder_of(shared.package_name(package:buildhash())))
            assert(#os.files(path.join(package:installdir("share"), shared.package_name(package:buildhash()) .. "_*.deb")) == 1,
                   "the shared runtime wrote no package")
            assert(#os.files(path.join(install, "*.dylib")) == 0, "the shared runtime keeps a second copy of its libraries")
        end
        for _, library in ipairs({"swiftCore", "swift_Concurrency", "swiftDarwin", "swiftSynchronization", "swiftObservation",
                                  "swift_StringProcessing", "swift_RegexParser", "swiftRegexBuilder"}) do
            assert(os.isfile(path.join(libraries, "lib" .. library .. ".dylib")), "the runtime has no lib" .. library .. ".dylib")
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
        local exported = os.iorunv("xcrun", {"nm", "-gU", path.join(libraries, "libswiftCore.dylib")})
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
                os.vrunv(toolchain:tool("cc"), table.join(common, {path.join(folder, "port.c"), "-L" .. libraries, "-lswiftCore",
                         "-Wl,-u,_" .. mark, "-o", path.join(folder, "port")}))
                return true
            end }
        end
        assert(links(package:data("mark")), "a port must link against the runtime it was built against, by its mark")
        assert(not links("charon_swift_runtime_not_this_build"),
               "a port must not link against a runtime whose mark it does not name; the mark is what keeps builds apart")
        os.tryrm(folder)
    end)
