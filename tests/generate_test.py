#!/usr/bin/env python3
"""Check what Charon writes from a declaration, and what it refuses to write.

    tests/generate_test.py
"""
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "config" / "extensions" / "charon"))

import generate
import spec

MANIFEST = """
[port]
name = "example"
version = "1.0"

[target]
include-profiles = ["shared-target"]
arch = "armv7"
os = "iOS"
os-version = "6.0"
sdk = "iphoneos"
cppstd = 23
cpu = "cortex-a9"
fpu = "neon"

[engine]
find-packages = ["LibXml2"]

[[static-library]]
name = "compat"
sources = ["compat/a.c", "compat/b.m"]
standard = 23
include-system = ["compat/stubs"]
options = ["-O2", "-fno-objc-arc"]

[[device-library]]
name = "tweak"
sources = ["platform/tweak.c"]
install = "/Library/MobileSubstrate/DynamicLibraries"
packages = ["openssl"]
frameworks = ["CoreFoundation"]
libraries = ["objc"]
resources = [{ from = "platform/tweak.plist", as = "Tweak.plist" }]

[[device-library]]
name = "prefs"
cmake = "platform/prefs"

[application]
name = "Host"
sources = ["app/main.m"]
frameworks = ["UIKit"]
resources = ["app/cacert.pem"]
"""

BROKEN = {
    "a device library with no install path": """
[target]
arch = "armv7"
os = "iOS"
os-version = "6.0"
[[device-library]]
name = "tweak"
sources = ["a.c"]
""",
    "a source whose language Charon cannot name": """
[target]
arch = "armv7"
os = "iOS"
os-version = "6.0"
[[static-library]]
name = "compat"
sources = ["a.rs"]
""",
    "a target with neither sources nor cmake": """
[target]
arch = "armv7"
os = "iOS"
os-version = "6.0"
[[static-library]]
name = "compat"
""",
    "a target that says nothing about what it builds for": """
[[static-library]]
name = "compat"
sources = ["a.c"]
""",
}


def loaded(folder, text):
    root = Path(folder)
    (root / "charon.toml").write_text(text)
    return spec.load(root)


def checks(declared):
    found = []
    written = generate.written(declared)

    text = written["profile"]
    if not text.startswith("include(shared-target)"):
        found.append("a declared profile include must come first, because the shared profile is where the "
                     "linker and the SDK come from: got {}".format(text.splitlines()[:1]))
    for expected in ("arch=armv7", "os.version=6.0", "os.sdk=iphoneos", "compiler.cppstd=23",
                     "build_type=Release", "-mcpu=cortex-a9", "-mfpu=neon"):
        if expected not in text:
            found.append("the profile must carry {}".format(expected))

    static = written["static-library/CMakeLists.txt"]
    if "add_library(compat STATIC" not in static:
        found.append("a static library must be generated as STATIC")
    if "project(port-static C OBJC)" not in static:
        found.append("languages must come from the sources: got {}".format(static.splitlines()[2]))
    if "find_package" in static:
        found.append("a target that declares no package must get no find_package, and the engine list "
                     "must not leak into a port project")
    if "CXX_STANDARD 23" not in static:
        found.append("a declared standard must be set on the target")
    if "install(" in static:
        found.append("a static library is consumed by the build, so it must not be installed")

    device = written["device-library/CMakeLists.txt"]
    if "add_library(tweak SHARED" not in device:
        found.append("a device library must be SHARED, because a MODULE bypasses the linker we require")
    if "INSTALL_NAME_DIR /Library/MobileSubstrate/DynamicLibraries" not in device:
        found.append("a device library must record the path it is deployed to")
    if '"-framework CoreFoundation"' not in device or "objc" not in device:
        found.append("frameworks and libraries must both reach target_link_libraries")
    if "find_package(openssl REQUIRED CONFIG)" not in device:
        found.append("a package declared on a target must reach that project")
    if "RENAME Tweak.plist" not in device:
        found.append("a renamed resource must keep its new name")
    if "prefs" in device:
        found.append("a target with cmake= must not be generated at all")

    application = written["application/CMakeLists.txt"]
    if "add_executable(Host" not in application:
        found.append("an application must be an executable")
    if "install(TARGETS Host RUNTIME DESTINATION .)" not in application:
        found.append("an application must install its binary")
    if "install(FILES app/cacert.pem DESTINATION .)" not in application:
        found.append("an application must install its declared resources")

    for line in (generate.GENERATED,):
        if line not in static or line not in device:
            found.append("a generated file must say it is generated")
    return found


def refusals(folder):
    found = []
    for description, text in BROKEN.items():
        declared = loaded(folder, text)
        try:
            generate.written(declared)
            found.append("{} must be refused".format(description))
        except (generate.GenerationError, spec.SpecError):
            pass
    return found


def main():
    if sys.version_info < (3, 11):
        running = ".".join(str(part) for part in sys.version_info[:3])
        print("FAIL  this needs Python 3.11 or newer for tomllib, and it is running under {}. "
              "Skipping would report success having checked nothing.".format(running))
        return 1
    found = []
    with tempfile.TemporaryDirectory() as folder:
        found += checks(loaded(folder, MANIFEST))
        found += refusals(folder)
    for line in found:
        print("FAIL  {}".format(line))
    if found:
        print("{} checks failed".format(len(found)))
        return 1
    print("ok    what a declaration produces is what it declared, and the rest is refused")
    return 0


if __name__ == "__main__":
    sys.exit(main())
