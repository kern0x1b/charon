import os

from conan import ConanFile
from conan.tools.apple import to_apple_arch
from conan.errors import ConanInvalidConfiguration
from conan.tools.files import copy
from conan.tools.scm import Version


class AppleCompatConan(ConanFile):
    name = "apple-compat"
    user = "charon"
    channel = "stable"
    description = ("What a current library calls and an old Apple system does not have, provided as hidden "
                   "definitions linked into the image that calls them")
    license = "MIT"
    package_type = "static-library"
    settings = "os", "arch", "compiler", "build_type"
    exports_sources = "src/*", "include/*"

    ARRIVED = {
        "aligned_alloc": {"iOS": "13.0", "Macos": "10.15", "tvOS": "13.0", "watchOS": "6.0"},
    }

    @property
    def _provided(self):
        system, release = str(self.settings.os), Version(str(self.settings.os.version))
        return sorted(symbol for symbol, arrived in self.ARRIVED.items()
                      if system in arrived and release < Version(arrived[system]))

    def validate(self):
        if not any(str(self.settings.os) in arrived for arrived in self.ARRIVED.values()):
            raise ConanInvalidConfiguration(f"{self.name} knows nothing an {self.settings.os} build lacks")

    def build(self):
        objects = []
        for symbol in self._provided:
            source = os.path.join(self.source_folder, "src", f"{symbol}.c")
            compiled = os.path.join(self.build_folder, f"{symbol}.o")
            flags = " ".join(self.conf.get("tools.build:cflags", default=[], check_type=list))
            sysroot = self.conf.get("tools.apple:sdk_path", check_type=str)
            target = f"-target {self._triple} -isysroot \"{sysroot}\"" if sysroot else ""
            self.run(f'xcrun clang {target} {flags} -Os -fvisibility=hidden -c "{source}" -o "{compiled}"')
            objects.append(f'"{compiled}"')
        if objects:
            self.run(f'xcrun libtool -static -o "{os.path.join(self.build_folder, "libapple-compat.a")}" '
                     + " ".join(objects))

    @property
    def _triple(self):
        return f"{to_apple_arch(self)}-apple-{str(self.settings.os).lower()}{self.settings.os.version}"

    def package(self):
        copy(self, "libapple-compat.a", self.build_folder, os.path.join(self.package_folder, "lib"))
        for symbol in self._provided:
            copy(self, f"{symbol}.h", os.path.join(self.source_folder, "include", "charon"),
                 os.path.join(self.package_folder, "include", "charon"))

    def package_info(self):
        provided = self._provided
        self.cpp_info.includedirs = ["include"] if provided else []
        self.cpp_info.libs = ["apple-compat"] if provided else []
        if not provided:
            self.cpp_info.libdirs = []
        self.cpp_info.set_property("charon_provides", provided)
        self.cpp_info.set_property("charon_force_includes",
                                   [os.path.join("charon", f"{symbol}.h") for symbol in provided])
