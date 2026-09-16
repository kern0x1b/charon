#!/usr/bin/env python3
"""Check what the base class reads out of a baked declaration, and what it refuses.

    tests/declaration_test.py

Run it with an interpreter that can import conan, because the recipe it loads is
a Conan recipe. It fakes the parts of a conanfile the reading half touches - the
options, the settings, the configuration and the folders - so the substitution
logic is checked here rather than discovered in a multi-hour build.
"""
import importlib.util
import sys
from pathlib import Path

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

    return Port()


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


def main():
    try:
        module = loaded_base()
    except ImportError as missing:
        print("FAIL  this needs an interpreter that can import conan: {}".format(missing))
        return 1
    found = failures(module)
    for line in found:
        print("FAIL  {}".format(line))
    if found:
        print("{} checks failed".format(len(found)))
        return 1
    print("ok    the base class reads a declaration, resolves what the build knows and refuses the rest")
    return 0


if __name__ == "__main__":
    sys.exit(main())
