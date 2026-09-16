import os

from conan import ConanFile
from conan.tools.files import copy


class Ios6ImportsCheckConan(ConanFile):
    name = "ios6-imports-check"
    user = "ios6"
    channel = "stable"
    description = ("Refuses a build whose binaries import a symbol the device's iOS does not export, "
                   "which loads fine and kills the process at its first call")
    license = "MIT"
    package_type = "application"
    exports_sources = "src/*"

    def package(self):
        copy(self, "ios6-imports-check", os.path.join(self.source_folder, "src"),
             os.path.join(self.package_folder, "bin"))
        os.chmod(os.path.join(self.package_folder, "bin", "ios6-imports-check"), 0o755)

    def package_info(self):
        self.cpp_info.includedirs = []
        self.cpp_info.libdirs = []
