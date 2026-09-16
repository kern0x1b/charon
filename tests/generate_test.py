#!/usr/bin/env python3
"""Check what Charon writes from a declaration, and what it refuses to write.

    tests/generate_test.py
"""
import json
import os
import subprocess
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

[platform]
use = "apple-ios"
arch = "armv7"
os-version = "6.0"

[target]
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
resources = ["app/cacert.pem", { from = "app/Localization/", as = "." }]

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
[platform]
use = "apple-ios"
arch = "armv7"
os-version = "6.0"
[[device-library]]
name = "tweak"
sources = ["a.c"]
""",
    "a source whose language Charon cannot name": """
[platform]
use = "apple-ios"
arch = "armv7"
os-version = "6.0"
[[static-library]]
name = "compat"
sources = ["a.rs"]
""",
    "a target with neither sources nor cmake": """
[platform]
use = "apple-ios"
arch = "armv7"
os-version = "6.0"
[[static-library]]
name = "compat"
""",
    "a resource that is neither a path nor a table with from and as": """
[platform]
use = "apple-ios"
arch = "armv7"
os-version = "6.0"
[application]
name = "Host"
sources = ["main.m"]
resources = [{ from = "images/" }]
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
    if "include(" in text:
        found.append("a platform writes the whole profile, so nothing is included: got {}".format(text))
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
    if "install(DIRECTORY ${CHARON_PORT}/app/Localization/ DESTINATION .)" not in application:
        found.append("an application must install a declared resource folder, not drop it: got {}".format(
            application))

    packages = written["tests/host/conanfile.py"]
    if "icu/74.2@revenant/stable" not in packages:
        found.append("a tier that names packages must get a recipe asking for them: got {}".format(packages))
    if "DependencyEnv" not in packages:
        found.append("a tier's recipe must write down where the packages landed, or the tier cannot find them")
    if "tests/gate/conanfile.py" in written:
        found.append("a tier that names no packages must get no recipe at all")

    cross = written[generate.CROSS_TOOLCHAIN]
    for expected in ("set(CMAKE_OSX_ARCHITECTURES ${CHARON_ARCHITECTURE})",
                     "-target ${CHARON_TRIPLE} -isysroot ${CHARON_SYSROOT}",
                     "set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)",
                     "set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)",
                     "-DEXAMPLE_PORT"):
        if expected not in cross:
            found.append("the cross toolchain must carry {}: got {}".format(expected, cross))
    if "CACHE PATH" not in cross or "CHARON_SDK" not in cross:
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


GLOBBED = """
[platform]
use = "apple-ios"
arch = "armv7"
os-version = "6.0"
[[static-library]]
name = "compat"
sources = ["compat/**/*.c", "compat/*.m"]
exclude = ["compat/skip/**"]
"""


def glob_failures(folder):
    found = []
    root = Path(folder) / "globbed"
    for relative in ("compat/a.c", "compat/deep/b.c", "compat/c.m", "compat/skip/d.c"):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("")
    static = generate.written(loaded(root, GLOBBED))["static-library/CMakeLists.txt"]
    for expected in ("compat/a.c", "compat/deep/b.c", "compat/c.m"):
        if "${CHARON_PORT}/" + expected not in static:
            found.append("a source matched by a pattern must be built: {} missing from {}".format(expected, static))
    if "compat/skip/d.c" in static:
        found.append("a source under an exclude pattern must not be built")
    if "project(port-static C OBJC)" not in static:
        found.append("languages must come from the files a pattern matched: got {}".format(static.splitlines()[2]))

    for description, sources, exclude, reason in (
            ("a pattern that matches no file, beside one that does", ["compat/**/*.c", "compat/**/*.swift"], [],
             "matches no file"),
            ("sources that exclude takes every one of", ["compat/**/*.c"], ["compat/**"], "takes every one")):
        text = GLOBBED.replace('sources = ["compat/**/*.c", "compat/*.m"]', "sources = {}".format(
            "[" + ", ".join('"{}"'.format(s) for s in sources) + "]")).replace(
            'exclude = ["compat/skip/**"]', "exclude = [" + ", ".join('"{}"'.format(e) for e in exclude) + "]")
        try:
            generate.written(loaded(root, text))
            found.append("{} must be refused".format(description))
        except generate.GenerationError as refused:
            if reason not in str(refused):
                found.append("{} must be refused for that reason, not another: got {}".format(description, refused))
    return found


SLICED = """
[port]
name = "example"
version = "1.0"
[platform]
use = "apple-ios"
arch = "armv7"
os-version = "6.0"
[variants.armv7]
[variants.arm64.platform]
arch = "armv8"
os-version = "7.0"
"""


def variant_failures(folder):
    found = []
    root = Path(folder) / "sliced"
    root.mkdir()
    declared = loaded(root, SLICED)
    for variant, arch, version, tool in (("armv7", "armv7", "6.0", "ld64/"), ("arm64", "armv8", "7.0", None)):
        written = generate.written(declared.for_variant(variant))
        text = written["profile"]
        if (tool not in text) if tool else ("ld64/" in text):
            found.append("the {} variant's profile must require exactly its architecture's tools: {}".format(
                variant, text))
        for expected in ("arch={}".format(arch), "os.version={}".format(version)):
            if expected not in text:
                found.append("the {} variant's profile must say {}: got {}".format(variant, expected, text))
        if arch in written[generate.CROSS_TOOLCHAIN]:
            found.append("the {} variant's cross toolchain must take its architecture from the build, not "
                         "spell the declared {}".format(variant, arch))
    return found


LAYERED = """
[platform]
use = "apple-ios"
arch = "armv7"
os-version = "6.0"
[application]
name = "Host"
sources = ["src/**/*.m", "src/**/*.mm"]
exclude = ["src/Resources/**"]
include = ["src/**/"]
include-exclude = ["src/Resources/**"]
options = ["-O2"]
[application.options-for]
objc = ["-fobjc-arc"]
objcxx = ["-fobjc-arc", "-isystem /sdk/usr/include/c++/v1"]
[application.definitions-for]
objcxx = ["TGVOIP_NO_DSP"]
[application.include-system-for]
objcxx = ["${CXX_STDLIB}"]
"""


def language_failures(folder):
    found = []
    root = Path(folder) / "layered"
    for relative in ("src/App/main.m", "src/Screens/Chat/Cells/cell.m", "src/Calls/call.mm", "src/Resources/x.m"):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("")
    application = generate.written(loaded(root, LAYERED))["application/CMakeLists.txt"]
    for folder_name in ("src", "src/App", "src/Screens", "src/Screens/Chat", "src/Screens/Chat/Cells", "src/Calls"):
        if "${CHARON_PORT}/" + folder_name + "\n" not in application and \
                "${CHARON_PORT}/" + folder_name + ")" not in application:
            found.append("an include pattern must reach {}: got {}".format(folder_name, application))
    if "src/Resources" in application:
        found.append("a folder under include-exclude, and its sources, must not be used")
    for expected in ('"$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>"',
                     '"$<$<COMPILE_LANGUAGE:OBJCXX>:SHELL:-isystem /sdk/usr/include/c++/v1>"',
                     '"$<$<COMPILE_LANGUAGE:OBJCXX>:TGVOIP_NO_DSP>"',
                     '"$<$<COMPILE_LANGUAGE:OBJCXX>:${CXX_STDLIB}>"'):
        if expected not in application:
            found.append("a per-language value must be written as {}: got {}".format(expected, application))

    refusals_by_reason = (
        ("an include pattern that matches no folder", 'include = ["src/**/"]', 'include = ["lib/**/"]',
         "matches no folder"),
        ("an include folder that is not there", 'include = ["src/**/"]', 'include = ["src/App", "app"]',
         "no such folder"),
        ("options for a language nobody named", "[application.options-for]\nobjc", "[application.options-for]\nswift",
         "not one of"),
        ("options for a language no source is in", "[application.options-for]\nobjc", "[application.options-for]\nc",
         "would apply to nothing"),
    )
    for description, old, new, reason in refusals_by_reason:
        try:
            generate.written(loaded(root, LAYERED.replace(old, new)))
            found.append("{} must be refused".format(description))
        except generate.GenerationError as refused:
            if reason not in str(refused):
                found.append("{} must be refused for that reason, not another: got {}".format(description, refused))
    return found


ORDERED = """
[platform]
use = "apple-ios"
arch = "armv7"
os-version = "6.0"
[[static-library]]
name = "objcfirst"
sources = ["first.m", "first.mm"]
[[static-library]]
name = "clater"
sources = ["later.c"]
"""


def determinism_failures(folder):
    found = []
    first, second = Path(folder) / "one" / "checkout", Path(folder) / "elsewhere" / "entirely"
    texts = []
    for root in (first, second):
        root.mkdir(parents=True)
        texts.append(generate.recipe(loaded(root, SLICED).for_variant("arm64")))
    if texts[0] != texts[1]:
        found.append("the same declaration in two folders must give the same recipe, or moving a repository "
                     "changes every revision and rebuilds every package")
    for root in (first, second):
        if str(root) in texts[0] or str(root) in texts[1]:
            found.append("a generated recipe must not name the folder it was written in: {} appears".format(root))
    return found


CONFIGURED = """
[platform]
use = "apple-ios"
arch = "armv7"
os-version = "7.0"

[target]
cpu = "cortex-a9"

[conf]
"user.charon-test:needed" = "a sentence saying why, set elsewhere"
"user.charon-test:headers" = { value = "{port}/sdk/include", why = "the headers come from the port" }
"user.charon-test:flags" = { value = ["-a", "-b"], why = "a list stays a list" }
"user.charon-test:strict" = { value = true, why = "a boolean stays a boolean" }

[variants.arm64.platform]
arch = "armv8"

[variants.arm64.conf]
"user.charon-test:strict" = { value = false, why = "one slice relaxes it" }
"""

CONF_REFUSED = {
    "a value without a reason": '"user.x:y" = { value = "z" }',
    "a reason without a value": '"user.x:y" = { why = "z" }',
    "an empty reason": '"user.x:y" = { value = "z", why = " " }',
    "a key beside value and why": '"user.x:y" = { value = "z", why = "w", when = "armv7" }',
    "a placeholder a profile cannot answer": '"user.x:y" = { value = "{include:libcxx}", why = "w" }',
    "a value colliding with the tuning Charon writes": '"tools.build:cxxflags" = { value = ["-O2"], why = "w" }',
}


def conf_failures(folder):
    found = []
    root = Path(folder) / "configured"
    root.mkdir()
    declared = loaded(root, CONFIGURED)
    text = generate.written(declared)["profile"]
    if "user.charon-test:needed" in text:
        found.append("a [conf] sentence names a value the port does not set, and must not be written: {}".format(text))
    if str(root) in text:
        found.append("a profile must find the port from where it lies, not carry the checkout path: {}".format(text))
    written = root / "build" / "system" / "charon" / "profile"
    written.parent.mkdir(parents=True)
    written.write_text(text)
    home = Path(folder) / "conan-home"
    home.mkdir(exist_ok=True)
    shown = subprocess.run(["conan", "profile", "show", "-pr:h", str(written), "-pr:b", str(written),
                            "--format=json"], capture_output=True, text=True,
                           env=dict(os.environ, CONAN_HOME=str(home)))
    if shown.returncode != 0:
        return found + ["conan must read the profile Charon writes: {}".format(shown.stderr.strip()[-400:])]
    conf = json.loads(shown.stdout)["host"]["conf"]
    expected = {"user.charon-test:headers": str(root / "sdk" / "include"),
                "user.charon-test:flags": ["-a", "-b"], "user.charon-test:strict": True,
                "tools.build:cxxflags": ["-mcpu=cortex-a9", "-mtune=cortex-a9"]}
    for key, value in expected.items():
        if conf.get(key) != value:
            found.append("the profile must give {} = {!r}: conan read {!r}".format(key, value, conf.get(key)))
    if "[buildenv]\nIPHONEOS_DEPLOYMENT_TARGET=7.0" not in text:
        found.append("the profile must export IPHONEOS_DEPLOYMENT_TARGET from os-version, so a tool invoked "
                     "without a version flag stamps the target's minimum and not its own default: {}".format(text))
    environment = subprocess.run(["conan", "profile", "show", "-pr:h", str(written), "-pr:b", str(written)],
                                 capture_output=True, text=True, env=dict(os.environ, CONAN_HOME=str(home)))
    if "IPHONEOS_DEPLOYMENT_TARGET=7.0" not in environment.stdout:
        found.append("conan must read IPHONEOS_DEPLOYMENT_TARGET=7.0 in the host build environment: {}".format(
            environment.stdout[-600:]))
    sliced = generate.written(declared.for_variant("arm64"))["profile"]
    if "user.charon-test:strict=False" not in sliced or "user.charon-test:headers=" not in sliced:
        found.append("a variant's [conf] must replace the keys it names and keep the rest: {}".format(sliced))
    for description, entry in CONF_REFUSED.items():
        refused = Path(folder) / "refused-conf"
        refused.mkdir(exist_ok=True)
        broken = loaded(refused, '[platform]\nuse = "apple-ios"\narch = "armv7"\nos-version = "6.0"\n'
                                 '[target]\ncpu = "cortex-a9"\n[conf]\n{}\n'.format(entry))
        try:
            generate.written(broken)
            found.append("{} in [conf] must be refused".format(description))
        except generate.GenerationError:
            pass
    return found


PLATFORMED = """
[platform]
use = "apple-ios"
arch = "armv7"
os-version = "6.0"

[target]
cppstd = 23
cpu = "cortex-a9"

[conf]
"user.charon-test:value" = { value = "set", why = "a declared value sits beside the platform's" }

[variants.arm64.platform]
arch = "armv8"
os-version = "7.0"
"""


def platform_failures(folder):
    found = []
    root = Path(folder) / "platformed"
    root.mkdir()
    declared = loaded(root, PLATFORMED)
    home = Path(folder) / "platform-home"
    home.mkdir()
    environment = dict(os.environ, CONAN_HOME=str(home))
    installed = subprocess.run(["conan", "config", "install", str(Path(generate.__file__).resolve().parents[2])],
                               capture_output=True, text=True, env=environment)
    if installed.returncode:
        return ["the toolchain configuration must install into a fresh Conan home: {}".format(installed.stderr)]
    for variant, arch, version, tools in (("armv7", "armv7", "6.0", {"ld64", "iphoneos-sdk"}),
                                          ("arm64", "armv8", "7.0", {"iphoneos-sdk"})):
        text = generate.written(declared if variant == "armv7" else declared.for_variant(variant))["profile"]
        if "include(" in text:
            found.append("a platform writes the whole profile, so nothing is included: {}".format(text))
        written = root / "build" / variant / "charon" / "profile"
        written.parent.mkdir(parents=True, exist_ok=True)
        written.write_text(text)
        shown = subprocess.run(["conan", "profile", "show", "-pr:h", str(written), "-pr:b", "default", "--format=json"],
                               capture_output=True, text=True, env=environment)
        if shown.returncode:
            subprocess.run(["conan", "profile", "detect"], capture_output=True, env=environment)
            shown = subprocess.run(["conan", "profile", "show", "-pr:h", str(written), "-pr:b", "default",
                                    "--format=json"], capture_output=True, text=True, env=environment)
        if shown.returncode:
            found.append("conan must read the {} profile the platform wrote: {}".format(variant, shown.stderr[-400:]))
            continue
        host = json.loads(shown.stdout)["host"]
        settings = host["settings"]
        for key, value in (("os", "iOS"), ("os.version", version), ("arch", arch), ("os.sdk", "iphoneos"),
                           ("compiler.libcxx", "libc++"), ("compiler.cppstd", "23")):
            if settings.get(key) != value:
                found.append("the {} profile must set {}={}: got {}".format(variant, key, value, settings.get(key)))
        if not settings.get("compiler") or not settings.get("compiler.version"):
            found.append("the {} profile must detect the compiler: got {}".format(variant, settings))
        required = {reference.split("/")[0] for references in (host.get("tool_requires") or {}).values()
                    for reference in references}
        if required != tools:
            found.append("the {} profile must require {} for its builds: got {}".format(variant, sorted(tools),
                                                                                      sorted(required)))
        conf = host.get("conf") or {}
        for key, value in (("tools.cmake.cmaketoolchain:generator", "Ninja"), ("user.charon-test:value", "set"),
                           ("tools.build:cxxflags", ["-mcpu=cortex-a9", "-mtune=cortex-a9"])):
            if conf.get(key) != value:
                found.append("the {} profile must carry {}={!r}: got {!r}".format(variant, key, value, conf.get(key)))
        if "IPHONEOS_DEPLOYMENT_TARGET={}".format(version) not in text:
            found.append("the {} profile must export the platform's deployment variable: {}".format(variant, text))
    return found


def architecture_failures(folder):
    root = Path(folder) / "wide"
    root.mkdir()
    text = generate.cross_toolchain(loaded(root, '[platform]\nuse = "apple-ios"\narch = "armv8"\nos-version = "7.0"\n'))
    found = []
    for expected in ("set(CMAKE_OSX_ARCHITECTURES ${CHARON_ARCHITECTURE})", "-target ${CHARON_TRIPLE}",
                     "NOT CHARON_ARCHITECTURE OR NOT CHARON_TRIPLE"):
        if expected not in text:
            found.append("the cross toolchain must take the architecture and target from the build and refuse "
                         "to configure without them: {} is missing".format(expected))
    if "armv8" in text:
        found.append("the cross toolchain must not spell the Conan architecture name clang does not know")
    return found


def order_failures(folder):
    root = Path(folder) / "ordered"
    root.mkdir()
    static = generate.written(loaded(root, ORDERED))["static-library/CMakeLists.txt"]
    if "project(port-static C OBJC OBJCXX)" not in static:
        return ["project() must enable C before OBJC whatever order the sources and targets come in, or a second "
                "configure hands .m to the C compiler: got {}".format(static.splitlines()[2])]
    return []


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
        (Path(folder) / "compat" / "stubs").mkdir(parents=True)
        found += checks(loaded(folder, MANIFEST))
        found += language_failures(folder)
        found += refusals(folder)
        found += glob_failures(folder)
        found += variant_failures(folder)
        found += order_failures(folder)
        found += determinism_failures(folder)
        found += conf_failures(folder)
        found += architecture_failures(folder)
        found += platform_failures(folder)
    for line in found:
        print("FAIL  {}".format(line))
    if found:
        print("{} checks failed".format(len(found)))
        return 1
    print("ok    what a declaration produces is what it declared, and the rest is refused")
    return 0


if __name__ == "__main__":
    sys.exit(main())
