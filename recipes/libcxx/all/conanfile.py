from conan import ConanFile
from conan.tools.cmake import CMake, CMakeToolchain
from conan.tools.files import copy, replace_in_file
import os


class LibCxxArmv7Conan(ConanFile):
    name = "libcxx"
    user = "ios6"
    channel = "stable"
    description = "The C++ runtime for armv7 / iOS 6, which no SDK of that era ships"
    license = "Apache-2.0 WITH LLVM-exception"
    homepage = "https://libcxx.llvm.org"
    package_type = "shared-library"
    settings = "os", "arch", "compiler", "build_type"

    def source(self):
        source = self.conan_data["sources"][self.version]
        # A sparse checkout: the runtimes and what they need, not the compiler.
        self.run(f'git clone --depth 1 --branch {source["tag"]} --filter=blob:none '
                 f'--sparse {source["url"]} llvm-project')
        self.run("git -C llvm-project sparse-checkout set libcxx libcxxabi libunwind "
                 "runtimes cmake third-party llvm/cmake llvm/utils/llvm-lit libc")
        # libc++ decides utimensat exists from a macro the SDK defines, but the
        # function itself arrived in iOS 11. On this target the call would build
        # and then fail on the device, so the detection gets a way to be told no.
        replace_in_file(self, os.path.join(self.source_folder, "llvm-project", "libcxx",
                                           "src", "filesystem", "time_utils.h"),
                        "#if defined(UTIME_OMIT)",
                        "#if defined(UTIME_OMIT) && !defined(_LIBCPP_NO_UTIMENSAT)")

    def generate(self):
        sdk = self.conf.get("tools.apple:sdk_path")
        target = f"{self.settings.arch}-apple-ios{self.settings.os.version}"
        tc = CMakeToolchain(self)
        # Flags belong here rather than in cache variables: CMakeToolchain owns
        # CMAKE_CXX_FLAGS and would overwrite them.
        tc.extra_cflags += ["-mllvm", "-hot-cold-split=false"]
        tc.extra_cxxflags += ["-mllvm", "-hot-cold-split=false",
                              "-D_LIBCPP_NO_UTIMENSAT"]
        tc.cache_variables.update({
            "CMAKE_SYSTEM_NAME": "Darwin",
            "CMAKE_OSX_SYSROOT": sdk,
            "CMAKE_OSX_ARCHITECTURES": str(self.settings.arch),
            "LLVM_ENABLE_RUNTIMES": "libcxx;libcxxabi",
            "LIBCXX_ENABLE_SHARED": True,
            "LIBCXXABI_ENABLE_SHARED": True,
            "LIBCXX_ENABLE_STATIC": False,
            "LIBCXXABI_ENABLE_STATIC": False,
            "LIBCXX_CXX_ABI": "libcxxabi",
            # This target has its own unwinder in the system libraries.
            "LIBCXXABI_USE_LLVM_UNWINDER": False,
            "LIBCXX_INCLUDE_BENCHMARKS": False,
            "LIBCXX_INCLUDE_TESTS": False,
            "LIBCXXABI_INCLUDE_TESTS": False,
        })
        tc.generate()

    def build(self):
        cmake = CMake(self)
        cmake.configure(build_script_folder=os.path.join("llvm-project", "runtimes"))
        cmake.build()
        cmake.install()

    def package(self):
        copy(self, "LICENSE.TXT", os.path.join(self.source_folder, "llvm-project", "libcxx"),
             os.path.join(self.package_folder, "licenses"))

    def package_info(self):
        self.cpp_info.libs = ["c++", "c++abi"]
        self.cpp_info.includedirs = [os.path.join("include", "c++", "v1")]
        self.cpp_info.cxxflags = ["-nostdinc++"]
        self.cpp_info.defines = ["_LIBCPP_DISABLE_AVAILABILITY"]
