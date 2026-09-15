from conan import ConanFile
from conan.errors import ConanInvalidConfiguration


class Ios6BaseConan(ConanFile):
    name = "ios6-base"
    version = "1.0"
    package_type = "python-require"
    description = "Conventions every armv7 / iOS 6 port shares"
    license = "MIT"


class Ios6Port:
    """Base class for a port's own conanfile.

    Inherited with python_requires_extend, the way a service inherits a
    convention plugin: the target, the generators and the checks live here, and
    the port's file is left saying only what that port needs.
    """

    settings = "os", "arch", "compiler", "build_type"
    generators = "CMakeDeps", "CMakeToolchain", "VirtualBuildEnv"

    def validate(self):
        if str(self.settings.os) != "iOS" or str(self.settings.arch) != "armv7":
            raise ConanInvalidConfiguration(
                f"{self.name} targets armv7 iOS; got {self.settings.os}/{self.settings.arch}. "
                "Build it with -pr:h ios6-armv7.")
        if str(self.settings.os.version) not in ("6.0", "6.1"):
            raise ConanInvalidConfiguration(
                f"{self.name} targets iOS 6; the profile says {self.settings.os.version}.")

    def layout(self):
        self.folders.generators = "build/conan"
