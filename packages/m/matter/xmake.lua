package("matter")
    set_homepage("https://github.com/project-chip/connectedhomeip")
    set_description("The Matter stack, built as the port builds it: connectedhomeip's own GN build of libCHIP for the release, and then the framework's own Objective-C++ wrapper over it")
    set_license("Apache-2.0")
    set_policy("package.strict_compatibility", true)

    -- submodules = false: connectedhomeip declares about two hundred submodules, almost all of them the
    -- vendor SDKs of embedded platforms this build never reads, and xmake clones a git source's submodules
    -- recursively unless a url says otherwise. The six this build does read are checked out below, at the
    -- commits the tag pins.
    add_urls("https://github.com/project-chip/connectedhomeip.git", {submodules = false})
    add_versions("v1.6.1.0", "3bcdd56ba54fb88b2afb4bfef575014671df7aa7")
    add_patches("v1.6.1.0", "patches/clock-alignment.patch")

    add_deps("charon@apple-compat", {alias = "apple-compat"})
    add_deps("charon@apple-backports", {alias = "backports", configs = {network = true}})
    add_deps("charon@ld64", {alias = "ld64"})
    add_deps("charon@libcxx", {alias = "libcxx"})
    add_deps("gn 20211117", {alias = "gn"})

    -- The submodules //src/lib:lib reads, at the commits the tag pins (read from the tag's own git objects, with
    -- `git submodule status`): the two nestlabs assert/logging headers under src/include, BoringSSL, pigweed's gni
    -- files, and - with chip_enable_all_clusters, which is what carries every cluster the SDK's Matter framework has -
    -- jsoncpp and uriparser. Nothing else is fetched: the tree this package builds does not read a byte of the rest.
    local submodules = {
        ["third_party/nlassert/repo"] = "c5892c5ae43830f939ed660ff8ac5f1b91d336d3",
        ["third_party/nlio/repo"] = "0e725502c2b17bb0a0c22ddd4bcaee9090c8fb5c",
        ["third_party/boringssl/repo/src"] = "9cac8a6b38c1cbd45c77aee108411d588da006fe",
        ["third_party/pigweed/repo"] = "8bc35d07baf8000f8db57674a23c5e06f7516d79",
        ["third_party/jsoncpp/repo"] = "8519b8381f3c741ad1421f88237b1deda0b11412",
        ["third_party/uriparser/repo"] = "04d8b8df5e0c6bf6c06e472540c015943a613bd2"
    }
    -- GN's spelling of each architecture the port builds.
    local cpus = {armv7 = "arm", armv7s = "arm", arm64 = "arm64"}

    on_install("iphoneos", function (package)
        local modules = path.join(package:scriptdir(), "..", "..", "..", "modules")
        local toolchain = import("apple.cmake", {rootdir = modules, anonymous = true}).toolchain(package)
        local sdk = assert(toolchain:config("sdkdir"), "the apple-ios toolchain names no SDK")
        local minimum = assert(toolchain:config("deployment"), "the apple-ios toolchain names no minimum release")
        local cpu = assert(cpus[package:arch()], "Matter builds armv7, armv7s and arm64, not " .. package:arch())

        -- The flags, taken from the toolchain rather than written out here, the way modules/apple/cmake.lua takes them:
        -- the release's own triple, sysroot and deployment target, and its own emulated-TLS flag, which is what an
        -- armv7 build below iOS 9 needs because that release's libSystem has no real __thread.
        local flags = table.join({"-target", package:arch() .. "-apple-ios", "-miphoneos-version-min=" .. minimum, "-isysroot", sdk},
                                 toolchain:config("linker_version") and {"-mlinker-version=" .. toolchain:config("linker_version")} or {})
        -- -Wno-incompatible-sysroot: clang's own warning that a sysroot newer than the deployment target is being
        -- used, which is every build on this port - the port compiles against a current SDK for a release far older -
        -- and GN compiles the tree with -Werror, so the warning would stop the build over the port's own arrangement.
        local compiled = table.join(flags, toolchain:config("emulated_tls") and {"-femulated-tls"} or {},
                                    {"-Wno-incompatible-sysroot"})

        for _, name in ipairs(table.orderkeys(submodules)) do
            os.vrunv("git", {"submodule", "update", "--init", "--depth", "1", name})
            assert(os.isdir(path.join(os.curdir(), name)), "the submodule " .. name .. " is not there after git checked it out")
        end

        -- //build_overrides/pigweed.gni imports //build_overrides/pigweed_environment.gni, a file upstream's bootstrap
        -- step writes into the source tree and its .gitignore lists. This build has no pigweed environment at all - no
        -- CIPD toolchain, no pw_env_setup, a compiler and an archiver of the port's own passed to GN - so the file is
        -- written here, empty of declarations, which is what the generated one comes to for a build that has none of
        -- the variables it would declare: every one of them (pw_env_setup_CIPD_PIGWEED, pw_env_setup_CIPD_RUST and the
        -- rest) is read through defined() by the pigweed gni files that import this one.
        io.writefile(path.join(os.curdir(), "build_overrides", "pigweed_environment.gni"),
                     "# Written by charon@matter's install step in place of the file pigweed's bootstrap step generates.\n" ..
                     "# This build has no pigweed environment: no CIPD toolchain, no pw_env_setup, and a compiler and\n" ..
                     "# an archiver of the port's own passed to GN as target_cc, target_cxx and target_ar. Every variable\n" ..
                     "# the pigweed gni files read out of this one is read through defined(), and a build that has none of\n" ..
                     "# them set is what the declarations come to, so the file declares nothing.\n")

        local function quoted(values)
            local parts = {}
            for _, value in ipairs(values) do
                table.insert(parts, "\"" .. value:gsub("\\", "\\\\"):gsub("\"", "\\\"") .. "\"")
            end
            return table.concat(parts, ", ")
        end

        -- build_overrides/../gn_build.sh and the framework's own chip_xcode_build_connector.sh write this list; the
        -- two flags GN's own custom toolchain exists for are the port's compiler, archiver and flags, and everything
        -- else is the framework's own build configuration (the second import, //config/darwin/args.gni, is what makes
        -- the sources the darwin platform's and not a fake platform's).
        local args = {
            'import("//config/darwin/args.gni")',
            "default_configs_cosmetic=[]",
            "is_clang=true",
            "is_debug=false",
            'custom_toolchain="custom"',
            'target_os="ios"',
            'target_cpu="' .. cpu .. '"',
            "target_cc=" .. string.format("%q", assert(toolchain:tool("cc"), "the apple-ios toolchain names no compiler for " .. package:arch())),
            "target_cxx=" .. string.format("%q", assert(toolchain:tool("cxx"), "the apple-ios toolchain names no C++ compiler for " .. package:arch())),
            "target_ar=" .. string.format("%q", assert(toolchain:tool("ar"), "the apple-ios toolchain names no archiver")),
            "target_cflags=[" .. quoted(compiled) .. "]",
            "target_cflags_c=[]",
            "target_cflags_cc=[]",
            "target_ldflags=[" .. quoted(flags) .. "]",
            "target_defines=[]",
            "mac_target_arch=" .. string.format("%q", package:arch()),
            "mac_deployment_target=" .. string.format("%q", minimum),
            'chip_crypto="boringssl"',
            "chip_build_controller_dynamic_server=false",
            "chip_build_tools=false",
            "chip_build_tests=false",
            -- Every cluster, because the framework's zap-generated sources name every cluster's Objective-C class and
            -- each one is a C++ cluster below it; the SDK's own Matter framework has them all.
            "chip_enable_all_clusters=true",
            "chip_enable_wifi=false",
            "chip_enable_nfc_based_commissioning=true",
            "chip_enable_python_modules=false",
            "chip_device_config_enable_dynamic_mrp_config=true",
            "chip_log_message_max_size=4096",
            'chip_logging_backend="none"',
            "chip_disable_platform_kvs=true",
            "enable_fuzz_test_targets=false"
        }

        -- One build tree per configuration: the sources are one directory for every architecture and every release the
        -- port builds, so a shared tree would build the second one with the first one's flags.
        local out = path.absolute("out-" .. package:buildhash())
        os.mkdir(out)
        os.vrunv(path.join(package:dep("gn"):installdir("bin"), "gn"),
                 {"--root=" .. path.absolute(os.curdir()), "gen", out, "--args=" .. table.concat(args, " ")})
        os.vrunv("ninja", {"-C", out, "src/lib:lib"})
        os.cp(path.join(out, "lib", "libCHIP.a"), package:installdir("lib"))

        -- Stage 2: the framework's own Objective-C++ wrapper, compiled and linked as libMatterBackports.dylib.
        -- Its sources name each other as <Matter/...>, which is the framework's own include layout, so the headers
        -- are gathered into one Matter directory first - the same directory a port will import them from, and the
        -- one installed below.
        local framework = path.join(os.curdir(), "src", "darwin", "Framework", "CHIP")
        local headers = path.join(out, "include", "Matter")
        os.mkdir(headers)
        for _, header in ipairs(os.files(path.join(framework, "**", "*.h"))) do
            os.cp(header, headers)
        end
        for _, header in ipairs(os.files(path.join(framework, "*.h"))) do
            os.cp(header, headers)
        end
        local search = table.join({path.join(out, "include"), framework, path.join(framework, "zap-generated"),
                                  path.join(framework, "ServerEndpoint"), path.join(framework, "XPC Protocol"),
                                  path.join(os.curdir(), "src"), path.join(os.curdir(), "src", "include"),
                                  path.join(os.curdir(), "zzz_generated"), path.join(os.curdir(), "zzz_generated", "app-common"),
                                  path.join(os.curdir(), "third_party", "nlassert", "repo", "include"),
                                  path.join(os.curdir(), "third_party", "nlio", "repo", "include")},
                                 {path.join(package:dep("libcxx"):installdir("include"), "c++", "v1")})
        local wrapper = table.join(compiled, {"-fobjc-arc", "-fno-c++-static-destructors", "-fmacro-prefix-map=" .. framework .. "/=",
                                             "-DCHIP_HAVE_CONFIG_H=1", "-DCHIP_CONFIG_SKIP_APP_SPECIFIC_GENERATED_HEADER_INCLUDES=1",
                                             "-DCHIP_CONFIG_GLOBALS_NO_DESTRUCT=1"})
        local objects = {}
        for _, source in ipairs(os.files(path.join(framework, "**", "*.mm"))) do
            -- The object keeps the source's own place under the framework: two directories hold sources of the same
            -- name (MTRCommandTimedCheck.mm is in CHIP/ and in CHIP/zap-generated/), and one flat name for both
            -- would be one object written twice.
            local object = path.absolute(path.join("framework", path.relative(source, framework) .. ".o"))
            os.mkdir(path.directory(object))
            local arguments = table.join(wrapper, {"-I" .. path.join(out, "gen", "include")})
            for _, directory in ipairs(search) do
                table.insert(arguments, "-I" .. directory)
            end
            os.vrunv(assert(toolchain:tool("mxx"), "the apple-ios toolchain names no Objective-C++ compiler for " .. package:arch()),
                     table.join(arguments, {"-c", source, "-o", object}))
            table.insert(objects, object)
        end
        assert(#objects > 0, "the framework at " .. framework .. " has no Objective-C++ source")

        local libcxx = package:dep("libcxx"):installdir("lib")
        -- The framework's device browser asks Network for a connection (MTRDeviceConnectivityMonitor.mm), and iOS 6
        -- has no Network.framework, so the nw_* calls come from the backport that carries them over BSD sockets.
        local backports = package:dep("backports"):installdir("lib")
        local output = path.join(package:installdir("lib"), "libMatterBackports.dylib")
        os.vrunv(assert(toolchain:tool("mxx"), "the apple-ios toolchain names no Objective-C++ compiler for " .. package:arch()),
                 table.join(flags, {"-fuse-ld=" .. path.join(package:dep("ld64"):installdir("bin"), "ld"),
                                    "-dynamiclib", "-install_name", "/usr/lib/charon/org.charon.apple-backports/libMatterBackports.dylib",
                                    "-o", output, path.join(out, "lib", "libCHIP.a")}, objects,
                           {"-L" .. backports, "-lNetworkBackports", "-lFoundationBackports",
                            "-L" .. libcxx, "-lc++abi", "-lc++",
                            path.join(package:dep("apple-compat"):installdir("lib"), "libapple-compat.a"),
                            "-framework", "Foundation", "-framework", "Security", "-framework", "CoreData",
                            "-framework", "CoreBluetooth",
                            "-Wl,-rpath," .. libcxx, "-Wl,-rpath,@loader_path"}))

        os.vcp(headers, path.join(package:installdir("include"), "Matter"))
        os.mkdir(path.join(package:installdir("include"), "Matter", "Modules"))
        os.cp(path.join(framework, "Matter.modulemap"), path.join(package:installdir("include"), "Matter", "Modules", "module.modulemap"))
        package:add("links", "Matter")
    end)

    on_test(function (package)
        assert(os.isfile(path.join(package:installdir("lib"), "libCHIP.a")))
        assert(os.isfile(path.join(package:installdir("lib"), "libMatterBackports.dylib")))
    end)
