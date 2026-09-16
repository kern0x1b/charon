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
defines = ["-DEXAMPLE_PORT"]

[engine]
find-packages = ["LibXml2"]
project-name = "Example"
config-packages = ["LibXml2", "LibXslt"]

[[static-library]]
name = "compat"
sources = ["compat/a.c", "compat/b.m"]
standard = 23
include-system = ["compat/stubs", "${LIBCXX_DIR}/include/c++/v1"]
options = ["-O2", "-fno-objc-arc"]
definitions = ["$<$<COMPILE_LANGUAGE:OBJC>:EXTRAS>"]
source-include = { "compat/a.c" = "${PSL_INCLUDE_DIR}" }
cache = { LIBCXX_DIR = "{pkg:libcxx}", PSL_INCLUDE_DIR = "{include:libpsl}" }

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

[tests.host]
runs = ["tests/run.py:on_host"]
needs = []
packages = { icu = "74.2@revenant/stable" }

[tests.gate]
runs = ["tests/device.py:gate"]
needs = ["device"]
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
    if "${CHARON_PORT}/compat/a.c" not in static:
        found.append("a declared source must be written against the port, because a generated project is "
                     "configured from the build tree and not from the folder the sources live in")
    if "${CHARON_PORT}/${LIBCXX_DIR}" in static:
        found.append("a value that already starts at a cmake variable must be left exactly as declared")
    if generate.REQUIRES_PORT not in static:
        found.append("a generated project must refuse to configure when nothing told it where the port is")
    if "foreach (variable LIBCXX_DIR PSL_INCLUDE_DIR)" not in static:
        found.append("every cache variable a target names must be guarded, the way the hand-written "
                     "projects guarded them: got {}".format(static))
    if "target_compile_definitions(compat PRIVATE" not in static:
        found.append("declared definitions must reach the target")
    if ('set_source_files_properties(${CHARON_PORT}/compat/a.c PROPERTIES INCLUDE_DIRECTORIES '
            '"${PSL_INCLUDE_DIR}")') not in static:
        found.append("a per-source include must be set on that source and on no other")

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
    if "install(FILES ${CHARON_PORT}/app/cacert.pem DESTINATION .)" not in application:
        found.append("an application must install its declared resources")

    packages = written["tests/host/conanfile.py"]
    if "icu/74.2@revenant/stable" not in packages:
        found.append("a tier that names packages must get a recipe asking for them: got {}".format(packages))
    if "DependencyEnv" not in packages:
        found.append("a tier's recipe must write down where the packages landed, or the tier cannot find them")
    if "tests/gate/conanfile.py" in written:
        found.append("a tier that names no packages must get no recipe at all")

    cross = written[generate.CROSS_TOOLCHAIN]
    for expected in ("set(CMAKE_OSX_ARCHITECTURES armv7)",
                     "-target armv7-apple-ios${IOS6_DEPLOYMENT_TARGET} -isysroot ${SDK6}",
                     "set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)",
                     "set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)",
                     "-DEXAMPLE_PORT"):
        if expected not in cross:
            found.append("the cross toolchain must carry {}: got {}".format(expected, cross))
    if "CACHE PATH" not in cross or "IOS6_SDK" not in cross:
        found.append("the SDK must be remembered in the cache, because ninja re-runs cmake without the shell "
                     "that configured it")

    applied = written[generate.PROJECT_INCLUDE]
    for package in ("LibXml2", "LibXslt"):
        if "find_package({} REQUIRED CONFIG)".format(package) not in applied:
            found.append("a package declared under config-packages must be found by config, or the engine "
                         "falls back to whatever the SDK has: {} missing from {}".format(package, applied))
    if generate.GENERATED not in applied:
        found.append("the applied file must say it is generated")

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
