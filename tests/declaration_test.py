#!/usr/bin/env python3
"""Check what the base class reads out of a baked declaration, and what it refuses.

    tests/declaration_test.py

Run it with an interpreter that can import conan, because the recipe it loads is
a Conan recipe. It fakes the parts of a conanfile the reading half touches - the
options, the settings, the configuration and the folders - so the substitution
logic is checked here rather than discovered in a multi-hour build.
"""
import importlib.util
import os
import shutil
import sys
import tempfile
from pathlib import Path

CHOSEN = "DECLARATION_TEST_INTERPRETER"

HERE = Path(__file__).resolve().parent
BASE = HERE.parent / "recipes" / "ios6-base" / "all" / "conanfile.py"

DECLARATION = {
    "engine": {
        "stubs": "compat/stubs",
        "prefix-header": "plain.h",
        "exports": "{source}/Source/exports.exp",
        "options": {
            "PORT": "Cocoa",
            "ENABLE_WEBGL": "ON",
            "COMPAT_LIB": "{target:compat}",
            "EXPORTS": "{exports}",
            "FLAGS": "{cxx}",
        },
    },
    "flags": {
        "common": "-target {triple} {tuning} -isysroot {sdk}",
        "defines": "-DONE -DTWO",
        "cxx": "{common} -include {stubs}/{prefix-header} {defines}",
    },
    "variants": {
        "system": {},
        "prefixed": {
            "options": ["prefixed=True"],
            "prefix-header": "prefixed.h",
            "exports": "{build}/renamed.exp",
            "engine-options": {"ENABLE_WEBGL": "OFF"},
        },
    },
    "static-library": [{"name": "compat", "cmake": "compat", "produces": "libcompat.a"}],
    "tasks": {
        "audit": {"script": "steps/audit.py", "args": "--build {build}"},
        "bare": "steps/audit.py --build {build}",
        "greet": {"shell": "echo {build}"},
        "census": {"python": "import sys\nprint(sys.argv[1:])\n", "args": "{build}"},
        "silent": {"note": "declares nothing to run"},
        "torn": {"shell": "echo one", "python": "print('two')"},
    },
    "pipeline": {"system": ["task:audit", "build:compat", "build:engine", "check:exports", "stage:frameworks"]},
}


class Options:
    def __init__(self, values):
        self._values = values

    def get_safe(self, name):
        return self._values.get(name)


class OperatingSystem:
    version = "6.0"

    def __str__(self):
        return "iOS"


class Settings:
    arch = "armv7"
    os = OperatingSystem()


class Conf:
    def __init__(self, values):
        self._values = values

    def get(self, name, default=None, check_type=None):
        return self._values.get(name, default)


class Output:
    def title(self, line):
        pass

    def warning(self, line):
        pass


def loaded_base():
    spec = importlib.util.spec_from_file_location("ios6_base_under_test", BASE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def port(module, options):
    class Port(module.Ios6Port):
        declaration = DECLARATION
        port = "/port"
        name = "example"
        version = "1.0"

        def __init__(self):
            self.options = Options(options)
            self.settings = Settings()
            self.conf = Conf({"tools.apple:sdk_path": "/sdks/iPhoneOS13.7.sdk",
                              "tools.build:cxxflags": ["-mcpu=cortex-a9"]})
            self.source_folder = "/port/engine"
            self.build_folder = "/port/build/system"
            self.output = Output()
            self.ran = []
            self.commands = []

        def run(self, command):
            self.commands.append(command)

        def _run_task(self, name):
            self.ran.append("task:" + name)

        def _build_target(self, name):
            self.ran.append("build:" + name)

        def _run_check(self, name):
            self.ran.append("check:" + name)

        def _run_stage(self, name):
            self.ran.append("stage:" + name)

        def _sign_target(self, name):
            self.ran.append("sign:" + name)

    return Port()


def merge_failures(module):
    import plistlib
    found = []
    baked = port(module, {"prefixed": "True"})
    type(baked).declaration = dict(DECLARATION, **{"for-variant": "system"})
    if baked.declared_variant() != "system":
        found.append("a recipe written for a variant must be that variant, whatever its options say")

    def slice_bundle(root, name, arch_magic, plist, extra=None):
        bundle = root / name / "Host.app"
        (bundle / "Frameworks").mkdir(parents=True)
        (bundle / "Host").write_bytes(arch_magic + b"\0" * 60)
        (bundle / "Frameworks" / "libx.dylib").write_bytes(arch_magic + b"\0" * 60)
        (bundle / "start.html").write_text("same everywhere")
        with open(bundle / "Info.plist", "wb") as handle:
            plistlib.dump(plist, handle)
        for relative, content in (extra or {}).items():
            (bundle / relative).parent.mkdir(parents=True, exist_ok=True)
            (bundle / relative).write_bytes(content)
        return str(bundle)

    thin, wide = b"\xce\xfa\xed\xfe", b"\xcf\xfa\xed\xfe"
    cases = (
        ("slices that agree", {}, {}, {}, ["Frameworks/libx.dylib", "Host"], []),
        ("a file only one slice has", {}, {}, {"extra.txt": b"x"}, None, ["present in only some slices"]),
        ("Info.plist keys that disagree", {"MinimumOSVersion": "6.0"}, {"MinimumOSVersion": "7.0"}, {}, None,
         ["Info.plist differs"]),
        ("a binary in one slice and data in the other", {}, {}, {"Frameworks/liby.dylib": wide + b"\0" * 8},
         None, None),
    )
    for description, first_plist, second_plist, second_extra, binaries, reasons in cases:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            extra_first = {"Frameworks/liby.dylib": b"plain data"} if description.startswith("a binary") else {}
            bundles = [slice_bundle(root, "armv7", thin, dict({"CFBundleExecutable": "Host"}, **first_plist),
                                    extra_first),
                       slice_bundle(root, "arm64", wide, dict({"CFBundleExecutable": "Host"}, **second_plist),
                                    second_extra)]
            planned, problems = module.MachO.merge_plan(bundles)
            if binaries is not None:
                if problems or planned != binaries:
                    found.append("{}: must merge {} with no problem, got {} and {}".format(
                        description, binaries, planned, problems))
                continue
            if not problems:
                found.append("{} must be refused".format(description))
            for reason in reasons or ["Mach-O in some slices and not in others"]:
                if not any(reason in problem for problem in problems):
                    found.append("{} must be refused because {}: got {}".format(description, reason, problems))
    return found


def plist_failures(module):
    import plistlib
    found = []
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        with open(root / "Info.plist", "wb") as handle:
            plistlib.dump({"CFBundleExecutable": "Host", "CFBundleVersion": "1.16.48", "MinimumOSVersion": "6.0",
                           "CFBundleIdentifier": "from.file", "UIRequiredDeviceCapabilities": ["armv7"]}, handle)
        with open(root / "Wrong.plist", "wb") as handle:
            plistlib.dump({"CFBundleExecutable": "Other"}, handle)
        instance = port(module, {"prefixed": "False"})
        type(instance).port = str(root)

        info = instance._application_plist("Host", {"plist-file": "Info.plist",
                                                    "plist": {"CFBundleIdentifier": "from.table"}})
        for key, expected, why in (
                ("CFBundleVersion", "1.16.48", "a key the file sets must win over the derived one"),
                ("CFBundleIdentifier", "from.table", "the declared table must win over the file"),
                ("UIRequiredDeviceCapabilities", ["armv7"], "a key only the file has must be kept"),
                ("CFBundleName", "Host", "a key neither sets must be derived")):
            if info.get(key) != expected:
                found.append("{}: {} is {!r}".format(why, key, info.get(key)))

        plain = instance._application_plist("Host", {"plist": {"CFBundleIdentifier": "x"}})
        if plain.get("CFBundleVersion") != "1.0" or plain.get("MinimumOSVersion") != "6.0":
            found.append("with no file, the version and minimum OS must still be derived: got {}".format(plain))

        for declared, why in (({"plist-file": "Wrong.plist"}, "a file naming another executable"),
                              ({"plist-file": "Absent.plist"}, "a plist-file that is not there")):
            try:
                instance._application_plist("Host", declared)
                found.append("{} must be refused".format(why))
            except Exception:
                pass
    return found


def bundle_failures(module):
    found = []
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        packages = root / "build" / "packages"
        packages.mkdir(parents=True)
        (packages / "libthin.dylib").write_bytes(b"\xce\xfa\xed\xfe" + b"\0" * 60)
        (packages / "libwide.dylib").write_bytes(b"\xcf\xfa\xed\xfe" + b"\0" * 60)
        (packages / "notes.txt").write_text("not a binary")
        bundle = root / "Host.app"
        bundle.mkdir()
        instance = port(module, {"prefixed": "False"})
        instance.build_folder = str(root / "build")

        carried = instance._declared_bundle(str(bundle), {"name": "Host", "bundle": [
            {"from": "{build}/packages/libthin.dylib"},
            {"from": "{build}/packages/libwide.dylib"},
            {"from": "{build}/packages/notes.txt", "into": "Resources"}]})
        expected = {str(bundle / "Frameworks" / "libthin.dylib"): "@executable_path/Frameworks/libthin.dylib",
                    str(bundle / "Frameworks" / "libwide.dylib"): "@executable_path/Frameworks/libwide.dylib"}
        if carried != expected:
            found.append("bundled binaries, 32-bit and 64-bit alike, must get an identity inside the bundle, and "
                         "nothing else must: got {}".format(carried))
        if not (bundle / "Resources" / "notes.txt").is_file():
            found.append("a bundled file must land where into says")

        for entries, why, reason in (
                ([{"from": "{build}/packages/absent.dylib"}], "bundling a file that is not there", "no such file"),
                ([{"into": "Frameworks"}], "a bundle entry with no from", "table with from")):
            try:
                instance._declared_bundle(str(bundle), {"name": "Host", "bundle": entries})
                found.append("{} must be refused".format(why))
            except Exception as refused:
                if reason not in str(refused):
                    found.append("{} must be refused for that reason, not another: got {}".format(why, refused))
    return found


def sign_failures(module):
    found = []
    merged = {"system": {}, "universal": {"merge": ["system"]}}
    cases = (
        ("an application built and never signed", {"system": {}}, ["build:application"], True),
        ("an application signed after a task that may change it", {"system": {}},
         ["build:application", "task:audit", "sign:application"], False),
        ("a bundle rebuilt after it was signed", {"system": {}},
         ["build:application", "sign:application", "build:application"], True),
        ("a slice another variant merges, left unsigned", merged, ["build:application", "task:audit"], False),
        ("a slice another variant merges, signed on its own", merged,
         ["build:application", "sign:application"], True),
    )
    for description, variants, steps, refuse in cases:
        instance = port(module, {"prefixed": "False"})
        type(instance).declaration = dict(DECLARATION, variants=variants, pipeline={"system": steps})
        try:
            instance.declared_pipeline()
            if refuse:
                found.append("{} must be refused".format(description))
        except Exception as refused:
            if not refuse:
                found.append("{} must be accepted: got {}".format(description, refused))
    return found


def dispatch_failures(module):
    found = []
    recorder = port(module, {"prefixed": "False"})
    recorder.declared_build()
    if recorder.ran != DECLARATION["pipeline"]["system"]:
        found.append("the steps must run in the order declared: got {}".format(recorder.ran))

    chosen = port(module, {"prefixed": "False"})
    chosen.conf = Conf(dict(chosen.conf._values,
                            **{"user.charon:steps": ["task:greet", "check:exports", "sign:application"]}))
    chosen.declared_build()
    if chosen.ran != ["task:greet", "check:exports", "sign:application"]:
        found.append("steps named on the command line must run instead of the pipeline, and only them: "
                     "got {}".format(chosen.ran))

    try:
        recorder._run_step("nonsense", "x")
        found.append("an unknown kind of step must be refused")
    except Exception:
        pass

    prefixed = port(module, {"prefixed": "True"})
    try:
        prefixed.declared_pipeline()
        found.append("a variant with no declared pipeline must be refused, not run as nothing")
    except Exception:
        pass

    real = port(module, {"prefixed": "False"})
    for method, argument, what in ((module.Ios6Port._run_task, "absent", "an undeclared task"),
                                   (module.Ios6Port._run_check, "absent", "an unknown check"),
                                   (module.Ios6Port._run_stage, "absent", "an unknown staging step")):
        try:
            method(real, argument)
            found.append("{} must be refused".format(what))
        except Exception:
            pass
    return found


def failures(module):
    found = []
    plain, prefixed = port(module, {"prefixed": "False"}), port(module, {"prefixed": "True"})

    if plain.declared_variant() != "system":
        found.append("a build with no options set must be the variant that declares none")
    if prefixed.declared_variant() != "prefixed":
        found.append("a build whose options match a variant must be that variant")

    if plain.declared_setting("engine", "prefix-header") != "plain.h":
        found.append("a setting not overridden must come from the section")
    if prefixed.declared_setting("engine", "prefix-header") != "prefixed.h":
        found.append("a variant must override the section")

    flags = plain.declared_flags("cxx")
    for expected in ("-target armv7-apple-ios6.0", "-mcpu=cortex-a9", "-isysroot /sdks/iPhoneOS13.7.sdk",
                     "-include /port/compat/stubs/plain.h", "-DONE -DTWO"):
        if expected not in flags:
            found.append("the flags must carry {}: got {}".format(expected, flags))
    if "{" in flags:
        found.append("no placeholder may survive in flags: {}".format(flags))

    options = plain.declared_options()
    if options.get("COMPAT_LIB") != "/port/build/system/compat/libcompat.a":
        found.append("a target reference must resolve to what that target produces: got {}".format(
            options.get("COMPAT_LIB")))
    if options.get("EXPORTS") != "/port/engine/Source/exports.exp":
        found.append("exports must resolve through the section: got {}".format(options.get("EXPORTS")))
    if options.get("ENABLE_WEBGL") != "ON":
        found.append("an option not overridden must keep the declared value")
    if prefixed.declared_options().get("ENABLE_WEBGL") != "OFF":
        found.append("a variant must override an engine option")
    if prefixed.declared_options().get("EXPORTS") != "/port/build/system/renamed.exp":
        found.append("a variant must override where the exports come from: got {}".format(
            prefixed.declared_options().get("EXPORTS")))

    try:
        plain._target_product("absent")
        found.append("an unknown target must be refused")
    except Exception:
        pass

    try:
        plain.declared_flags("nonexistent")
        found.append("flags that were never declared must be refused")
    except Exception:
        pass

    bare = port(module, {"prefixed": "False"})
    type(bare).declaration = {}
    try:
        bare.declared
        found.append("a recipe with no declaration must be refused")
    except Exception:
        pass
    type(bare).declaration = DECLARATION

    return found


def task_failures(module):
    found = []
    real = module.Ios6Port._run_task

    shell = port(module, {"prefixed": "False"})
    real(shell, "greet")
    if shell.commands != ["echo /port/build/system"]:
        found.append("a task declared as shell must run what it says, with the placeholders filled: "
                     "got {}".format(shell.commands))

    inline = port(module, {"prefixed": "False"})
    inline.build_folder = tempfile.mkdtemp()
    try:
        real(inline, "census")
        body = Path(inline.build_folder) / "charon-tasks" / "census.py"
        if not body.is_file():
            found.append("a task whose body is declared inline must be written down to be run: "
                         "{} is absent".format(body))
        elif "print(sys.argv[1:])" not in body.read_text():
            found.append("an inline body must be written as declared: got {}".format(body.read_text()))
        if not inline.commands or str(body) not in inline.commands[0]:
            found.append("an inline task must run the file it just wrote: got {}".format(inline.commands))
        elif inline.build_folder not in inline.commands[0].rsplit('"', 2)[-1]:
            found.append("an inline task must receive its declared arguments, expanded: "
                         "got {}".format(inline.commands[0]))
    finally:
        shutil.rmtree(inline.build_folder, ignore_errors=True)

    for name, why, reason in (("silent", "a task that names neither script, shell nor python", "exactly one"),
                              ("torn", "a task that says two things to run", "exactly one"),
                              ("bare", "a task written as a bare command line instead of a table", "is a table"),
                              ("audit", "a task naming a script that is not there", "does not exist")):
        instance = port(module, {"prefixed": "False"})
        try:
            real(instance, name)
            found.append("{} must be refused".format(why))
        except Exception as refused:
            if reason not in str(refused):
                found.append("{} must be refused for that reason, not for another: got {}".format(why, refused))
    return found


def conan_interpreter():
    launcher = shutil.which("conan")
    if not launcher:
        return None
    try:
        with open(launcher) as handle:
            first = handle.readline()
    except OSError:
        return None
    if not first.startswith("#!"):
        return None
    words = first[2:].strip().split()
    if not words:
        return None
    candidate = words[-1] if os.path.basename(words[0]) == "env" else words[0]
    return candidate if os.path.isabs(candidate) else shutil.which(candidate)


def reexec_where_conan_lives():
    if os.environ.get(CHOSEN):
        return
    try:
        import conan  # noqa: F401
        return
    except ImportError:
        pass
    interpreter = conan_interpreter()
    if interpreter and os.path.abspath(interpreter) != os.path.abspath(sys.executable):
        os.execve(interpreter, [interpreter, os.path.abspath(__file__)] + sys.argv[1:],
                  dict(os.environ, **{CHOSEN: interpreter}))


def main():
    reexec_where_conan_lives()
    try:
        module = loaded_base()
    except ImportError as missing:
        print("FAIL  this needs an interpreter that can import conan: {}".format(missing))
        return 1
    found = (failures(module) + dispatch_failures(module) + task_failures(module) + sign_failures(module) +
             plist_failures(module) + bundle_failures(module) + merge_failures(module))
    for line in found:
        print("FAIL  {}".format(line))
    if found:
        print("{} checks failed".format(len(found)))
        return 1
    print("ok    the base class reads a declaration, resolves what the build knows and refuses the rest")
    return 0


if __name__ == "__main__":
    sys.exit(main())
