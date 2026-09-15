import os
import re

from conan import ConanFile
from conan.errors import ConanException, ConanInvalidConfiguration
from conan.tools.scm import Version


class Ios6BaseConan(ConanFile):
    name = "ios6-base"
    user = "ios6"
    channel = "stable"
    version = "1.0"
    package_type = "python-require"
    description = "Conventions every armv7 / iOS 6 port shares"
    license = "MIT"


class DependencyEnv:

    filename = "ios6-deps.env"

    def __init__(self, conanfile):
        self._conanfile = conanfile

    def generate(self):
        dependencies = self._conanfile.dependencies
        lines = []
        for context, graph in (("HOST", dependencies.host), ("BUILD", dependencies.build)):
            for dependency in graph.values():
                folder = dependency.package_folder
                if folder is None:
                    continue
                if re.search(r"[\s'\"$\\#]", folder):
                    raise ConanException(
                        f"{dependency.ref}: {folder} cannot be written as a shell and make assignment")
                name = re.sub(r"[^A-Z0-9]", "_", dependency.ref.name.upper())
                lines.append(f"IOS6_{context}_{name}={folder}")
        path = os.path.join(self._conanfile.generators_folder, self.filename)
        with open(path, "w") as out:
            out.write("\n".join(sorted(lines)) + "\n")


class Ios6Port:
    """Base class for a port's own conanfile.

    Inherited with python_requires_extend, the way a service inherits a
    convention plugin: the target, the generators and the checks live here, and
    the port's file is left saying only what that port needs.
    """

    settings = "os", "arch", "compiler", "build_type"
    generators = "CMakeDeps", "CMakeToolchain", "VirtualBuildEnv"

    def validate(self):
        arch = str(self.settings.arch)
        if str(self.settings.os) != "iOS" or arch not in ("armv7", "armv8"):
            raise ConanInvalidConfiguration(
                f"{self.name} targets iOS on armv7 or arm64; got {self.settings.os}/{arch}. "
                "Build it with -pr:h ios6-armv7 or -pr:h ios-arm64.")
        if arch == "armv8" and Version(str(self.settings.os.version)) < "7.0":
            raise ConanInvalidConfiguration(
                f"{self.name}: arm64 starts at iOS 7.0; the profile says {self.settings.os.version}.")

    def layout(self):
        self.folders.generators = os.path.join("build", "conan", str(self.settings.arch))

    def generate(self):
        DependencyEnv(self).generate()
