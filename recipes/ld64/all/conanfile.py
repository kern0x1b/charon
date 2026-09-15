from conan import ConanFile
from conan.tools.files import get, copy, replace_in_file, chdir
from conan.errors import ConanInvalidConfiguration
import os
import shutil


class Ld64Armv7Conan(ConanFile):
    name = "ld64"
    user = "ios6"
    channel = "stable"
    description = "Apple's ld64 from cctools-port, the linker that still inserts branch islands for armv7"
    license = "APSL-2.0"
    homepage = "https://github.com/tpoechtrager/cctools-port"
    package_type = "application"
    settings = "os", "arch", "compiler", "build_type"

    def validate(self):
        if self.settings_build.os != "Macos":
            raise ConanInvalidConfiguration("this package builds on macOS")

    def _llvm_prefix(self):
        prefix = os.environ.get("LLVM_PREFIX")
        if prefix:
            return prefix
        brew = shutil.which("brew")
        if not brew:
            raise ConanInvalidConfiguration("LLVM_PREFIX is not set and brew was not found")
        with open("llvm_prefix.txt", "w") as out:
            self.run(f"{brew} --prefix llvm", stdout=out)
        return open("llvm_prefix.txt").read().strip()

    def source(self):
        data = self.conan_data["sources"][self.version]
        get(self, **data["libtapi"], strip_root=True, destination="libtapi")
        get(self, **data["cctools"], strip_root=True, destination="cctools-port")
        # Its vendored LLVM does not ship the CMake helper its clang calls.
        replace_in_file(self, os.path.join(self.source_folder, "libtapi", "src", "clang", "CMakeLists.txt"),
                        'if (APPLE AND NOT CMAKE_LINKER MATCHES ".*lld.*")\n  get_darwin_linker_version(HOST_LINK_VERSION)',
                        'if (APPLE AND NOT CMAKE_LINKER MATCHES ".*lld.*")\n'
                        '  if (COMMAND get_darwin_linker_version)\n'
                        '    get_darwin_linker_version(HOST_LINK_VERSION)\n'
                        '  else()\n'
                        '    set(HOST_LINK_VERSION "1053.12")\n'
                        '  endif()')

    def build(self):
        llvm = self._llvm_prefix()
        tapi_install = os.path.join(self.build_folder, "tapi-install")
        tapi_src = os.path.join(self.source_folder, "libtapi")
        with chdir(self, tapi_src):
            self.run(f'INSTALLPREFIX="{tapi_install}" ./build.sh')
            self.run(f'INSTALLPREFIX="{tapi_install}" ./install.sh')

        cctools = os.path.join(self.source_folder, "cctools-port", "cctools")
        # cctools' own llvm-c headers reach for a newer LLVM's config header.
        shutil.copy(os.path.join(llvm, "include", "llvm-c", "Visibility.h"),
                    os.path.join(cctools, "include", "llvm-c"))
        install = os.path.join(self.build_folder, "cctools-install")
        with chdir(self, cctools):
            # otool's disassembler still uses the old LLVMOpInfoCallback
            # signature. Only ld is wanted here, and newer clang makes that
            # mismatch an error by default.
            cflags = "-Wno-error=incompatible-function-pointer-types"
            self.run(f'CPPFLAGS="-I{llvm}/include" CFLAGS="{cflags}" CXXFLAGS="{cflags}" ./configure'
                     f' --prefix="{install}" --target=arm-apple-darwin11'
                     f' --with-libtapi="{tapi_install}"'
                     f' --with-llvm-config="{llvm}/bin/llvm-config"')
            self.run(f"make -j{os.cpu_count()}")
            self.run("make install")

    def package(self):
        install = os.path.join(self.build_folder, "cctools-install")
        tapi_install = os.path.join(self.build_folder, "tapi-install")
        copy(self, "*", os.path.join(install, "bin"), os.path.join(self.package_folder, "bin"))
        copy(self, "libtapi.dylib", os.path.join(tapi_install, "lib"),
             os.path.join(self.package_folder, "lib"))
        ld = os.path.join(self.package_folder, "bin", "arm-apple-darwin11-ld")
        os.symlink("arm-apple-darwin11-ld", os.path.join(self.package_folder, "bin", "ld"))
        self.run(f'install_name_tool -rpath "{tapi_install}/lib" @executable_path/../lib "{ld}"')

    def package_info(self):
        self.cpp_info.includedirs = []
        self.cpp_info.libdirs = []
        bindir = os.path.join(self.package_folder, "bin")
        self.buildenv_info.append_path("PATH", bindir)
        # -B is what makes the compiler driver pick this ld over the system one.
        self.conf_info.append("tools.build:exelinkflags", f"-B{bindir}")
        self.conf_info.append("tools.build:sharedlinkflags", f"-B{bindir}")
