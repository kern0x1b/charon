import os
from io import StringIO

from conan import ConanFile
from conan.errors import ConanException
from conan.tools.apple import to_apple_arch
from conan.tools.cmake import CMake, CMakeToolchain
from conan.tools.files import apply_conandata_patches, copy, export_conandata_patches


class LibCxxArmv7Conan(ConanFile):
    name = "libcxx"
    user = "ios6"
    channel = "stable"
    description = "The C++ runtime for armv7 / iOS 6, which no SDK of that era ships"
    license = "Apache-2.0 WITH LLVM-exception"
    homepage = "https://libcxx.llvm.org"
    package_type = "shared-library"
    settings = "os", "arch", "compiler", "build_type"

    def export_sources(self):
        export_conandata_patches(self)

    def source(self):
        source = self.conan_data["sources"][self.version]
        self.run(f'git clone --depth 1 --branch {source["tag"]} --filter=blob:none '
                 f'--sparse {source["url"]} llvm-project')
        checked_out = StringIO()
        self.run("git -C llvm-project rev-parse HEAD", stdout=checked_out)
        if checked_out.getvalue().strip() != source["commit"]:
            raise ConanException(f"{source['tag']} is {checked_out.getvalue().strip()} now, not the "
                                 f"{source['commit']} this recipe was written against; a tag that moved is not "
                                 "the release it names")
        self.run("git -C llvm-project sparse-checkout set libcxx libcxxabi libunwind "
                 "runtimes cmake third-party llvm/cmake llvm/utils/llvm-lit libc")
        apply_conandata_patches(self)

    def generate(self):
        sdk = self.conf.get("tools.apple:sdk_path")
        tc = CMakeToolchain(self)
        tc.extra_cflags += ["-mllvm", "-hot-cold-split=false"]
        tc.extra_cxxflags += ["-mllvm", "-hot-cold-split=false",
                              "-D_LIBCPP_NO_UTIMENSAT"]
        tc.cache_variables.update({
            "CMAKE_SYSTEM_NAME": "Darwin",
            "CMAKE_OSX_SYSROOT": sdk,
            "CMAKE_OSX_ARCHITECTURES": to_apple_arch(self),
            "LLVM_ENABLE_RUNTIMES": "libcxx;libcxxabi",
            "LIBCXX_ENABLE_SHARED": True,
            "LIBCXXABI_ENABLE_SHARED": True,
            "LIBCXX_ENABLE_STATIC": False,
            "LIBCXXABI_ENABLE_STATIC": False,
            "LIBCXX_CXX_ABI": "libcxxabi",
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
        headers = self.cpp_info.components["headers"]
        headers.includedirs = [os.path.join("include", "c++", "v1")]
        headers.cxxflags = ["-nostdinc++"]
        headers.libdirs = []
        headers.bindirs = []
        runtime = self.cpp_info.components["runtime"]
        runtime.requires = ["headers"]
        runtime.includedirs = []
        runtime.libs = ["c++", "c++abi"]
        runtime.defines = ["_LIBCPP_DISABLE_AVAILABILITY"]
