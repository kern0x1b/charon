import os
import plistlib

from conan import ConanFile
from conan.errors import ConanException
from conan.tools.layout import basic_layout


class TestPackage(ConanFile):
    settings = "os", "arch", "compiler", "build_type"
    test_type = "explicit"

    def build_requirements(self):
        self.tool_requires(self.tested_reference_str)

    def layout(self):
        basic_layout(self)

    def test(self):
        sdk = self.conf.get("tools.apple:sdk_path", check_type=str)
        if not sdk or not os.path.isdir(sdk):
            raise ConanException(f"a consumer must receive tools.apple:sdk_path from the package: got {sdk}")
        version = self.dependencies.build["iphoneos-sdk"].ref.version
        if os.path.basename(sdk) != f"iPhoneOS{version}.sdk":
            raise ConanException(f"the linker reads the SDK version from the folder name, and {sdk} does not carry it")
        developer = os.path.dirname(os.path.dirname(sdk))
        if os.path.basename(os.path.dirname(sdk)) != "SDKs" or not developer.endswith(
                os.path.join("iPhoneOS.platform", "Developer")):
            raise ConanException(f"{sdk} is not laid out as Xcode lays it out, and build systems that derive "
                                 "<platform>/Developer/SDKs/<sdk> from it would not find it")
        with open(os.path.join(sdk, "SDKSettings.plist"), "rb") as handle:
            if plistlib.load(handle).get("CanonicalName") != f"iphoneos{version}":
                raise ConanException(f"{sdk} is not iphoneos{version}")
        for needed in ("usr/lib/libSystem.tbd", "usr/include/stdio.h"):
            if not os.path.exists(os.path.join(sdk, needed)):
                raise ConanException(f"{sdk} has no {needed}")
