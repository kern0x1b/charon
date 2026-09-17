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
                         "third-party", "llvm/cmake", "llvm/utils/llvm-lit", "libc"})
        os.tryrm(opt.sourcedir)
        os.mv(checkout, opt.sourcedir)
    end)

    on_install("iphoneos", function (package)
        local cmake = import("apple.cmake", {rootdir = path.join(package:scriptdir(), "..", "..", "..", "modules"), anonymous = true})
        os.vrunv("git", {"apply", path.join(package:scriptdir(), "patches", "utimensat-told-no.patch"), "-p2"})
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
        cmake.install(package, {
            "-DLLVM_ENABLE_RUNTIMES=libcxx;libcxxabi",
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
        os.cp("libcxx/LICENSE.TXT", package:installdir("licenses") .. "/")
    end)

    on_test(function (package)
        assert(os.isfile(path.join(package:installdir("lib"), "libc++.1.0.dylib")))
        assert(os.isfile(path.join(package:installdir("include", "c++", "v1"), "vector")))
    end)
