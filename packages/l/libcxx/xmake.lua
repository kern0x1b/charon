package("libcxx")
    set_homepage("https://libcxx.llvm.org")
    set_description("The C++ runtime an old iOS does not ship, as the shared libraries an application carries in its bundle")
    set_license("Apache-2.0 WITH LLVM-exception")
    set_policy("package.strict_compatibility", true)

    add_urls("https://github.com/llvm/llvm-project.git")
    add_versions("23.1.1", "6dfe1677ab8dffbc6ec13d53a1e0215d75147689")
    add_deps("charon@apple-compat", {alias = "apple-compat"})
    add_deps("cmake", "ninja", {kind = "binary"})

    add_configs("shared", {description = "The runtime is always the shared pair an application bundles.", default = true, type = "boolean", readonly = true})

    add_includedirs("include/c++/v1")
    add_links("c++", "c++abi")
    add_defines("_LIBCPP_DISABLE_AVAILABILITY")
    add_cxxflags("-nostdinc++")
    add_mxxflags("-nostdinc++")
    add_ldflags("-nostdlib++")
    add_shflags("-nostdlib++")

    on_download(function (package, opt)
        local tag = "llvmorg-" .. package:version_str()
        local checkout = opt.sourcedir .. ".tmp"
        os.tryrm(checkout)
        os.vrunv("git", {"clone", "--depth", "1", "--branch", tag, "--filter=blob:none", "--sparse", opt.url, checkout})
        local head = os.iorunv("git", {"-C", checkout, "rev-parse", "HEAD"}):trim()
        if head ~= package:revision(opt.url_alias) and head ~= package:commit() then
            local wanted = package:revision(opt.url_alias) or package:commit()
            if head ~= wanted then
                raise("%s is %s now, not the %s this package was written against; a tag that moved is not the release it names", tag, head, tostring(wanted))
            end
        end
        os.vrunv("git", {"-C", checkout, "sparse-checkout", "set", "libcxx", "libcxxabi", "libunwind", "runtimes", "cmake",
                         "third-party", "llvm/cmake", "llvm/utils/llvm-lit", "libc", "compiler-rt/lib/builtins"})
        os.tryrm(opt.sourcedir)
        os.mv(checkout, opt.sourcedir)
    end)

    on_install("iphoneos", function (package)
        import("core.base.semver")
        local cmake = import("apple.cmake", {rootdir = path.join(package:scriptdir(), "..", "..", "..", "modules"), anonymous = true})
        for _, patch in ipairs({"utimensat-told-no.patch", "reexport-when-dyld-can.patch", "one-emulated-tls-runtime.patch", "one-atomic-runtime.patch"}) do
            os.vrunv("git", {"apply", path.join(package:scriptdir(), "patches", patch), "-p2"})
        end
        local compat = package:dep("apple-compat")
        local cxxflags = {"-mllvm", "-hot-cold-split=false", "-D_LIBCPP_NO_UTIMENSAT"}
        local shflags = {}
        for _, symbol in ipairs(compat:data("provided") or {}) do
            local header = path.join(compat:installdir("include"), "charon", symbol .. ".h")
            if os.isfile(header) then
                table.insert(cxxflags, "-include" .. header)
            end
        end
        if #(compat:data("provided") or {}) > 0 then
            table.join2(shflags, {"-L" .. compat:installdir("lib"), "-Wl,-hidden-lapple-compat"})
        end
        local deployment = cmake.toolchain(package):config("deployment")
        local emulated_tls = cmake.toolchain(package):config("emulated_tls") and true or false
        local atomic_libcalls = cmake.toolchain(package):config("atomic_libcalls") and true or false
        cmake.install(package, {
            "-DLIBCXXABI_ENABLE_EMULATED_TLS=" .. (emulated_tls and "ON" or "OFF"),
            "-DLIBCXXABI_ENABLE_ATOMIC_LIBCALLS=" .. (atomic_libcalls and "ON" or "OFF"),
            "-DLLVM_ENABLE_RUNTIMES=libcxx;libcxxabi",
            "-DLIBCXXABI_REEXPORT_FROM_LIBCXX=" .. (semver.compare(deployment, "4.2") < 0 and "OFF" or "ON"),
            "-DLIBCXX_ENABLE_SHARED=ON", "-DLIBCXXABI_ENABLE_SHARED=ON",
            "-DLIBCXX_ENABLE_STATIC=OFF", "-DLIBCXXABI_ENABLE_STATIC=OFF",
            "-DLIBCXX_CXX_ABI=libcxxabi", "-DLIBCXXABI_USE_LLVM_UNWINDER=OFF",
            "-DLIBCXX_INCLUDE_BENCHMARKS=OFF", "-DLIBCXX_INCLUDE_TESTS=OFF", "-DLIBCXXABI_INCLUDE_TESTS=OFF"
        }, {sourcedir = "runtimes", system = "Darwin", cflags = {"-mllvm", "-hot-cold-split=false"}, cxxflags = cxxflags, shflags = shflags})
        for _, library in ipairs({"libc++.1.0.dylib", "libc++abi.1.0.dylib"}) do
            local imported = {}
            for name in os.iorunv("xcrun", {"nm", "-u", path.join(package:installdir("lib"), library)}):gmatch("%S+") do
                if name:startswith("_") then
                    imported[name:sub(2)] = true
                end
            end
            local leaked = {}
            for _, symbol in ipairs(compat:data("provided") or {}) do
                if imported[symbol] or imported["charon_" .. symbol] then
                    table.insert(leaked, symbol)
                end
            end
            if #leaked > 0 then
                raise("%s still imports %s from the system, which iOS %s does not have; apple-compat was not linked into it", library, table.concat(leaked, ", "), cmake.toolchain(package):config("deployment"))
            end
        end
        local exported = os.iorunv("xcrun", {"nm", "-gU", path.join(package:installdir("lib"), "libc++abi.1.0.dylib")})
        if emulated_tls then
            for _, symbol in ipairs({"___emutls_get_address", "___cxa_thread_atexit"}) do
                if not exported:find(" T " .. symbol .. "\n", 1, true) then
                    raise("libc++abi.1.0.dylib does not export %s, and code compiled with -femulated-tls for iOS %s calls it", symbol, deployment)
                end
            end
        end
        for _, symbol in ipairs({"___atomic_load", "___atomic_store", "___atomic_exchange", "___atomic_compare_exchange", "___atomic_is_lock_free"}) do
            local found = exported:find(" T " .. symbol .. "\n", 1, true)
            if atomic_libcalls and not found then
                raise("libc++abi.1.0.dylib does not export %s, and code compiled for iOS %s calls it for an atomic the processor cannot update in one instruction", symbol, deployment)
            elseif not atomic_libcalls and found then
                raise("libc++abi.1.0.dylib exports %s, which libSystem has from iOS 7.0, so code built for iOS %s would bind a second copy with locks of its own", symbol, deployment)
            end
        end
        os.cp("libcxx/LICENSE.TXT", package:installdir("licenses") .. "/")
    end)

    on_test(function (package)
        assert(os.isfile(path.join(package:installdir("lib"), "libc++.1.0.dylib")))
        assert(os.isfile(path.join(package:installdir("include", "c++", "v1"), "vector")))
    end)
