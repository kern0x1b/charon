package("compiler-rt")
    set_homepage("https://compiler-rt.llvm.org")
    set_description("compiler-rt's builtins with hidden symbols, installed as libgcc_s.1.a: below iOS 5 clang links -lgcc_s.1, whose arithmetic helpers those releases shipped in a dylib, and armv6 has no builtins in the command line tools")
    set_license("Apache-2.0 WITH LLVM-exception")
    set_policy("package.strict_compatibility", true)

    add_urls("https://github.com/llvm/llvm-project.git")
    add_versions("23.1.1", "6dfe1677ab8dffbc6ec13d53a1e0215d75147689")
    add_deps("cmake", "ninja", {kind = "binary"})

    on_download(function (package, opt)
        local tag = "llvmorg-" .. package:version_str()
        local checkout = opt.sourcedir .. ".tmp"
        os.tryrm(checkout)
        os.vrunv("git", {"clone", "--depth", "1", "--branch", tag, "--filter=blob:none", "--sparse", opt.url, checkout})
        local head = os.iorunv("git", {"-C", checkout, "rev-parse", "HEAD"}):trim()
        local wanted = package:revision(opt.url_alias) or package:commit()
        if head ~= wanted then
            raise("%s is %s now, not the %s this package was written against; a tag that moved is not the release it names", tag, head, tostring(wanted))
        end
        os.vrunv("git", {"-C", checkout, "sparse-checkout", "set", "compiler-rt/lib/builtins", "compiler-rt/cmake", "compiler-rt/include", "cmake", "llvm/cmake"})
        os.tryrm(opt.sourcedir)
        os.mv(checkout, opt.sourcedir)
    end)

    on_install("iphoneos", function (package)
        local cmake = import("apple.cmake", {rootdir = path.join(package:scriptdir(), "..", "..", "..", "modules"), anonymous = true})
        local builddir = cmake.install(package, {
            "-DCMAKE_C_COMPILER_TARGET=" .. package:arch() .. "-apple-ios",
            "-DCMAKE_ASM_COMPILER_TARGET=" .. package:arch() .. "-apple-ios",
            "-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY",
            "-DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON",
            "-DCOMPILER_RT_BAREMETAL_BUILD=ON",
            "-DCOMPILER_RT_BUILTINS_HIDE_SYMBOLS=ON",
            "-DCOMPILER_RT_ARM_OPTIMIZED_FP=OFF",
            "-DLLVM_CMAKE_DIR=" .. path.absolute("cmake")
        }, {sourcedir = "compiler-rt/lib/builtins", system = "Generic", install = false, licenses = {"compiler-rt/LICENSE.TXT"}})
        local archive = assert(os.files(path.join(builddir, "**", "libclang_rt.builtins-" .. package:arch() .. ".a"))[1], "compiler-rt built no builtins archive for " .. package:arch())
        os.vcp(archive, path.join(package:installdir("lib"), "libgcc_s.1.a"))
    end)

    on_test(function (package)
        assert(os.isfile(path.join(package:installdir("lib"), "libgcc_s.1.a")))
    end)
