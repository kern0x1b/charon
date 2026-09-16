#!/usr/bin/env python3
"""Check the Mach-O invariants against binaries real linkers produce.

    tests/macho_test.py

Run it after the ld64 and ldid packages are in the Conan cache. The same object
is linked by ld64, which keeps each function pointer's Thumb bit, and then
edited the ways a linker or a post-link tool gets it wrong, so every refusal is
proven against the defect it names rather than against a hand-written file.
The steps that produce a binary are then run with those files, to show the
invariants are applied there and before anything strips or signs.
"""
import json
import os
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

import declaration_test

MODES = """
__attribute__((target("arm"))) int in_arm(int x) { return x + 1; }
__attribute__((target("thumb"))) int in_thumb(int x) { return x + 2; }
int (*table[])(int) = { in_arm, in_thumb };
int start(void) { return table[0](1) + table[1](1); }
"""

SYSTEM_STUB = """--- !tapi-tbd
tbd-version: 4
targets: [ armv7-ios, arm64-ios ]
install-name: '/usr/lib/libSystem.B.dylib'
exports:
  - targets: [ armv7-ios, arm64-ios ]
    symbols: [ dyld_stub_binder ]
...
"""


class Refused(Exception):
    pass


def packaged(reference, tool):
    listed = subprocess.run(["conan", "list", reference + "#*:*", "--format=json"],
                            capture_output=True, text=True)
    cache = json.loads(listed.stdout or "{}").get("Local Cache") or {}
    for recipe, described in cache.items():
        for revision, packages in described.get("revisions", {}).items():
            for package in packages.get("packages", {}):
                folder = subprocess.run(["conan", "cache", "path", "{}#{}:{}".format(recipe, revision, package)],
                                        capture_output=True, text=True).stdout.strip()
                candidate = Path(folder) / "bin" / tool
                if candidate.is_file():
                    return candidate
    raise Refused("{} has no package with bin/{} in the Conan cache; build it before this test".format(reference, tool))


def run(*command, cwd):
    finished = subprocess.run([str(part) for part in command], cwd=cwd, capture_output=True, text=True)
    if finished.returncode != 0:
        raise Refused("{} failed: {}".format(" ".join(str(part) for part in command), finished.stderr.strip()))
    return finished.stdout


def link(folder, linker, output, target, *extra):
    run("xcrun", "clang", "-target", target, "-Wno-incompatible-sysroot", "-fuse-ld={}".format(linker),
        "-nostdlib", "-L.", "-lSystem", *extra, "-o", output, "modes.c" if "arm64" not in target else "entry.c",
        cwd=folder)
    return folder / output


def section_offset(folder, binary, segment, section):
    listing = run("xcrun", "otool", "-l", binary, cwd=folder).split("Section")
    for block in listing:
        words = block.split()
        if "sectname" in words and words[words.index("sectname") + 1] == section \
                and words[words.index("segname") + 1] == segment:
            return int(words[words.index("offset") + 1])
    raise Refused("{} has no {},{}".format(binary, segment, section))


def edited(source, destination, position, value):
    shutil.copy2(source, destination)
    with open(destination, "r+b") as handle:
        handle.seek(position)
        handle.write(struct.pack("<I", value))
    return destination


def slot(path, position):
    with open(path, "rb") as handle:
        handle.seek(position)
        return struct.unpack("<I", handle.read(4))[0]


def fixtures(folder, ld64):
    (folder / "modes.c").write_text(MODES)
    (folder / "entry.c").write_text("int start(void) { return 0; }\n")
    (folder / "libSystem.tbd").write_text(SYSTEM_STUB)
    made = {
        "library": link(folder, ld64, "libmodes.dylib", "armv7-apple-ios6.0", "-dynamiclib"),
        "classic": link(folder, ld64, "libclassic.dylib", "armv7-apple-ios3.0", "-dynamiclib"),
        "executable": link(folder, ld64, "modes", "armv7-apple-ios6.0", "-Wl,-e,_start"),
        "arm64": link(folder, "ld", "wide", "arm64-apple-ios7.0", "-Wl,-e,_start"),
        "arm64-small-pagezero": link(folder, "ld", "narrow", "arm64-apple-ios7.0", "-Wl,-e,_start",
                                     "-Wl,-pagezero_size,0x1000"),
    }
    table = section_offset(folder, "libmodes.dylib", "__DATA", "__data")
    arm, thumb = slot(made["library"], table), slot(made["library"], table + 4)
    made["arm-with-thumb-bit"] = edited(made["library"], folder / "libarmbit.dylib", table, arm | 1)
    made["thumb-without-bit"] = edited(made["library"], folder / "libnobit.dylib", table + 4, thumb & ~1)
    classic = section_offset(folder, "libclassic.dylib", "__DATA", "__data")
    made["classic-thumb-without-bit"] = edited(made["classic"], folder / "libclassicnobit.dylib", classic + 4,
                                               slot(made["classic"], classic + 4) & ~1)
    data = made["executable"].read_bytes()
    zero = data.index(b"__PAGEZERO\0")
    made["armv7-pagezero-gap"] = edited(made["executable"], folder / "gapped", zero + 20, 0x1000)
    made["fat-with-thumb-without-bit"] = folder / "fat.dylib"
    wide_library = link(folder, "ld", "libwide.dylib", "arm64-apple-ios7.0", "-dynamiclib")
    run("xcrun", "lipo", "-create", made["thumb-without-bit"], wide_library, "-output", "fat.dylib", cwd=folder)
    made["fat-arm64-small-pagezero"] = folder / "fat-narrow"
    run("xcrun", "lipo", "-create", made["executable"], made["arm64-small-pagezero"], "-output", "fat-narrow",
        cwd=folder)
    return made, (arm, thumb)


def invariant_failures(module, made, pointers):
    found = []
    arm, thumb = pointers
    if arm & 1 or not thumb & 1:
        return ["ld64 must link the ARM pointer without bit 0 and the Thumb pointer with it, or nothing below "
                "means anything: got {:#x} and {:#x}".format(arm, thumb)]
    expectations = (
        ("library", [], 2),
        ("classic", [], 2),
        ("executable", [], 2),
        ("arm-with-thumb-bit", ["ARM function _in_arm has bit 0 set"], 2),
        ("thumb-without-bit", ["Thumb function _in_thumb lacks bit 0"], 2),
        ("classic-thumb-without-bit", ["Thumb function _in_thumb lacks bit 0"], 2),
        ("fat-with-thumb-without-bit", ["Thumb function _in_thumb lacks bit 0"], 2),
    )
    for name, reasons, checked in expectations:
        problems, counted = module.MachO.interworking_problems(str(made[name]))
        if counted != checked:
            found.append("{}: {} pointers must be compared with their functions, got {}".format(name, checked, counted))
        if len(problems) != len(reasons) or any(reason not in problem for reason, problem in zip(reasons, problems)):
            found.append("{}: expected {}, got {}".format(name, reasons or "nothing", problems))
    for name, reason in (("executable", None), ("arm64", None), ("library", None),
                         ("arm64-small-pagezero", "arm64 __PAGEZERO is 0x4000"),
                         ("fat-arm64-small-pagezero", "arm64 __PAGEZERO is 0x4000"),
                         ("armv7-pagezero-gap", "__PAGEZERO ends at 0x1000 and __TEXT starts at 0x4000")):
        problems = module.MachO.pagezero_problems(str(made[name]))
        if (reason is None and problems) or (reason and (len(problems) != 1 or reason not in problems[0])):
            found.append("{}: pagezero expected {}, got {}".format(name, reason or "nothing", problems))
    return found


class Output:
    def __init__(self):
        self.lines = []

    def title(self, line):
        pass

    def info(self, line):
        self.lines.append(line)

    def warning(self, line):
        self.lines.append(line)


def running_port(module, folder, declaration, ldid):
    instance = declaration_test.port(module, {"prefixed": "False"})
    kind = type(instance)
    kind.declaration = declaration
    kind.port = str(folder)
    instance.build_folder = str(folder / "build")
    instance.output = Output()
    instance.steps = []

    def execute(self, command, cwd=None, stdout=None, ignore_errors=False):
        command = command.replace("ldid ", '"{}" '.format(ldid), 1) if command.startswith("ldid ") else command
        finished = subprocess.run(command, shell=True, cwd=cwd, capture_output=True, text=True)
        if finished.returncode != 0 and not ignore_errors:
            raise RuntimeError("{} failed: {}".format(command, finished.stderr))
        if stdout is not None:
            stdout.write(finished.stdout)
        return finished.returncode

    kind.run = execute
    return instance


def recording_macho(module, instance):
    class Recording(module.MachO):
        def tool(self, name):
            return subprocess.run(["xcrun", "-f", name], capture_output=True, text=True).stdout.strip()

        def strip(self, binary, arguments="-x"):
            instance.steps.append(("strip", binary))

        def sign(self, binary, entitlements=None):
            instance.steps.append(("sign", binary))

        def retarget(self, identities):
            pass

        def repoint(self, binary, identities):
            pass

        def references(self, binary):
            return []

        def require_compatibility_version(self, binary, expected):
            pass

    return Recording


def refused_before(instance, action, reason, step, folder, module):
    try:
        action()
    except module.ConanException as refused:
        if reason not in str(refused):
            return ["{} must be refused for {}: got {}".format(step, reason, refused)]
        touched = [done for done, _ in instance.steps]
        if touched:
            return ["{} must refuse before anything strips or signs: {} ran first".format(step, touched)]
        return []
    return ["{} must refuse a binary that breaks an invariant".format(step)]


def wiring_failures(module, made, ldid):
    found = []
    original = module.MachO
    try:
        with tempfile.TemporaryDirectory() as scratch:
            folder = Path(scratch)
            (folder / "build").mkdir()
            broken = made["thumb-without-bit"]

            instance = running_port(module, folder, {"stage": {}}, ldid)
            module.MachO = recording_macho(module, instance)
            installed = folder / "build" / "installed"
            installed.mkdir()
            shutil.copy2(broken, installed / "libbroken.dylib")
            (installed / "install_manifest.txt").write_text(str(installed / "libbroken.dylib") + "\n")
            found += refused_before(instance, lambda: instance._sign_installed(str(installed)),
                                    "_in_thumb lacks bit 0", "installing a target into the stage", folder, module)

            instance = running_port(module, folder, {"stage": {"frameworks": {
                "Broken": {"as": "Broken", "replaces": "/System/Library/Frameworks/Broken.framework/Broken"}}}},
                ldid)
            module.MachO = recording_macho(module, instance)
            framework = folder / "build" / "Broken.framework"
            framework.mkdir()
            shutil.copy2(broken, framework / "Broken")
            found += refused_before(instance, instance._stage_frameworks, "_in_thumb lacks bit 0",
                                    "staging a framework", folder, module)

            instance = running_port(module, folder, {"application": {"name": "Host", "strip": "-S -x"},
                                                     "variants": {"system": {}}}, ldid)
            module.MachO = recording_macho(module, instance)
            instance._cmake_project = lambda source, into, definitions: None
            instance._project_source = lambda kind, target: str(folder)
            instance._write_application_plist = lambda bundle, name, declared: None
            installing = type(instance).run

            def install(self, command, cwd=None, stdout=None, ignore_errors=False):
                if command.startswith("cmake --install"):
                    shutil.copy2(made["armv7-pagezero-gap"], folder / "build" / "Host.app" / "Host")
                    return 0
                return installing(self, command, cwd, stdout, ignore_errors)

            type(instance).run = install
            found += refused_before(instance, instance._build_application, "__PAGEZERO ends at 0x1000",
                                    "linking the application", folder, module)

            instance = running_port(module, folder, {"application": {"name": "Host"},
                                                     "variants": {"armv7": {}, "arm64": {},
                                                                  "universal": {"merge": ["armv7", "arm64"]}}},
                                    ldid)
            module.MachO = recording_macho(module, instance)
            instance.declared_variant = lambda: "universal"
            for slice_name, binary in (("armv7", broken), ("arm64", made["arm64"])):
                bundle = folder / "build" / slice_name / "Host.app"
                bundle.mkdir(parents=True)
                shutil.copy2(binary, bundle / "Host")
            found += refused_before(instance, lambda: instance._merge_target("application"),
                                    "_in_thumb lacks bit 0", "merging the application", folder, module)
    finally:
        module.MachO = original
    with tempfile.TemporaryDirectory() as scratch:
        try:
            found += entitlement_failures(module, Path(scratch), made, ldid)
        finally:
            module.MachO = original
    return found


def entitlement_failures(module, folder, made, ldid):
    found = []
    declared = {"get-task-allow": True, "keychain-access-groups": ["example.shared"]}
    with open(folder / "declared.plist", "wb") as handle:
        plistlib.dump(declared, handle)
    for description, waive, signs_with_them, reason in (
            ("signed with what it declares", {}, True, None),
            ("signed without them", {}, False, "get-task-allow is declared and the signature does not carry it"),
            ("signed without them, waived", {"entitlements": "a reason"}, False, None)):
        instance = running_port(module, folder, {"application": {"name": "Host", "entitlements": "declared.plist"},
                                                 "waive": waive}, ldid)
        executable = folder / "signed"
        shutil.copy2(made["executable"], executable)
        instance._declared_context = lambda: {"executable": str(executable)}

        class Signing(module.MachO):
            def sign(self, binary, entitlements=None):
                super().sign(binary, entitlements if signs_with_them else None)

        module.MachO = Signing
        try:
            module.Ios6Port._sign_target(instance, "application")
            if reason:
                found.append("an application {} must be refused".format(description))
        except module.ConanException as refused:
            if not reason or reason not in str(refused):
                found.append("an application {}: expected {}, got {}".format(description, reason or "success",
                                                                              refused))
    return found


def waiver_failures(module, made):
    found = []
    instance = declaration_test.port(module, {"prefixed": "False"})
    instance.output = Output()
    for waive, reason in (({"pagezero": ""}, "gives no reason"), ({"thumb": "why"}, "not something this toolchain"),
                          ({"pagezero": True}, "gives no reason")):
        type(instance).declaration = {"waive": waive}
        try:
            instance.declared_waivers()
            found.append("[waive] {} must be refused".format(waive))
        except module.ConanException as refused:
            if reason not in str(refused):
                found.append("[waive] {} must be refused for {}: got {}".format(waive, reason, refused))
    type(instance).declaration = {"waive": {"pagezero": "the gap is the point of this binary"}}
    try:
        instance._verify(str(made["armv7-pagezero-gap"]))
    except module.ConanException as refused:
        found.append("a waived invariant must not refuse: {}".format(refused))
    if not any("pagezero not checked: the gap is the point" in line for line in instance.output.lines):
        found.append("a waived invariant must say it was not checked and why: {}".format(instance.output.lines))
    return found


def reexec_where_conan_lives():
    if os.environ.get(declaration_test.CHOSEN):
        return
    try:
        import conan  # noqa: F401
        return
    except ImportError:
        pass
    interpreter = declaration_test.conan_interpreter()
    if interpreter and os.path.abspath(interpreter) != os.path.abspath(sys.executable):
        os.execve(interpreter, [interpreter, os.path.abspath(__file__)] + sys.argv[1:],
                  dict(os.environ, **{declaration_test.CHOSEN: interpreter}))


def main():
    reexec_where_conan_lives()
    try:
        module = declaration_test.loaded_base()
        module.ConanException = sys.modules["conan.errors"].ConanException
    except ImportError as missing:
        print("FAIL  this needs an interpreter that can import conan: {}".format(missing))
        return 1
    found = []
    try:
        ld64 = packaged("ld64/956.6@ios6/stable", "ld")
        ldid = packaged("ldid/2.1.5@ios6/stable", "ldid")
        with tempfile.TemporaryDirectory() as scratch:
            made, pointers = fixtures(Path(scratch), ld64)
            found += invariant_failures(module, made, pointers)
            found += waiver_failures(module, made)
            found += wiring_failures(module, made, ldid)
    except Refused as missing:
        found.append(str(missing))
    for line in found:
        print("FAIL  {}".format(line))
    if found:
        print("{} checks failed".format(len(found)))
        return 1
    print("ok    a binary that breaks a platform invariant is refused where it is produced, before it is stripped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
