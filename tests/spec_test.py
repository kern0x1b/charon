#!/usr/bin/env python3
"""Check what a port declares and, above all, what Charon refuses to guess.

    tests/spec_test.py
"""
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "config" / "extensions" / "charon"))

import spec

MANIFEST = """
[port]
name = "example"
version = "1.0"

[paths]
tasks = "steps"

[use]
engine-toolchain = "cmake/mine.cmake"

[variants]
system = {}
prefixed = { options = ["prefixed=True"] }

[[static-library]]
name = "compat"
sources = ["compat/a.c"]

[[device-library]]
name = "tweak"
cmake = "platform"

[conf]
"user.example:thing" = "why this port needs it"

[tests]
transport = "tests/harness.py:bind"

[tests.scripts]
runs = ["tools/rule-test.py"]
needs = []

[tests.gate]
runs = ["tests/run.py:run_gate"]
needs = ["device"]

[tasks]
audit = "steps/audit.py --build {build}"

[pipeline]
system = ["task:audit", "build:engine"]
"""

KNOWN = {"build": "/port/build/system", "sdk": "/sdks/iPhoneOS13.7.sdk"}


def failures():
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        (root / "charon.toml").write_text(MANIFEST)
        declared = spec.load(root)
        found = []

        if spec.load(root / "nowhere") is not None:
            found.append("a folder with no charon.toml must read as no declaration at all")

        if declared.path("tasks") != root / "steps":
            found.append("a declared path must win over the default")
        if declared.path("build") != root / "build":
            found.append("an undeclared path must fall back to the convention")
        if declared.path("profiles") is not None:
            found.append("a path declared empty means Charon generates it, so it must read as absent")
        try:
            declared.path("nonsense")
            found.append("an unknown path name must be refused")
        except spec.SpecError:
            pass

        if declared.using("engine-toolchain") != root / "cmake" / "mine.cmake":
            found.append("an escape hatch must resolve against the port")
        if declared.using("recipe") is not None:
            found.append("an undeclared escape hatch must read as absent")

        resolved = spec.substitute("{sdk} and {build}", KNOWN)
        if resolved != "/sdks/iPhoneOS13.7.sdk and /port/build/system":
            found.append("known names must resolve: got {}".format(resolved))

        kept = spec.substitute("-I{include:libpsl} {lib:woff2:woff2dec}", KNOWN)
        if kept != "-I{include:libpsl} {lib:woff2:woff2dec}":
            found.append("graph names must survive for the recipe to resolve: got {}".format(kept))

        try:
            spec.substitute("-D{invented}", KNOWN)
            found.append("an unknown name must be refused rather than emptied")
        except spec.SpecError:
            pass

        try:
            spec.substitute("{include:libpsl}", KNOWN, keep_graph_names=False)
            found.append("a graph name must be refused where no graph exists")
        except spec.SpecError:
            pass

        if sorted(spec.placeholders("{a} {b:c} literal")) != ["a", "b:c"]:
            found.append("placeholders must be reported by name")

        if declared.variant("prefixed").get("options") != ["prefixed=True"]:
            found.append("a declared variant must come back as declared")
        try:
            declared.variant("nope")
            found.append("an undeclared variant must be refused")
        except spec.SpecError:
            pass

        if [target["name"] for target in declared.targets("static-library")] != ["compat"]:
            found.append("targets must be listed by kind")
        if not declared.generates(declared.target("static-library", "compat")):
            found.append("a target without cmake= must be generated")
        if declared.generates(declared.target("device-library", "tweak")):
            found.append("a target with cmake= must not be generated")
        try:
            declared.target("device-library", "absent")
            found.append("an undeclared target must be refused")
        except spec.SpecError:
            pass

        if declared.pipeline("system") != ["task:audit", "build:engine"]:
            found.append("a declared pipeline must come back as declared")
        try:
            declared.pipeline("prefixed")
            found.append("a variant with no pipeline must be refused rather than running nothing")
        except spec.SpecError:
            pass

        if sorted(declared.tiers()) != ["gate", "scripts"]:
            found.append("declared tiers must be listed, and the transport key must not read as one")
        if declared.tier("gate").get("needs") != ["device"]:
            found.append("a tier must come back with what it needs")
        if declared.transport_binder() != "tests/harness.py:bind":
            found.append("the transport binder must be readable on its own")
        try:
            declared.tier("nope")
            found.append("an undeclared tier must be refused")
        except spec.SpecError:
            pass

        if declared.conf_required() != {"user.example:thing": "why this port needs it"}:
            found.append("a declared configuration key must come back with the reason the port gave")

        if "{build}" not in declared.task("audit"):
            found.append("a task must come back with its placeholders intact")
        try:
            declared.task("missing")
            found.append("an undeclared task must be refused")
        except spec.SpecError:
            pass

        try:
            declared.require("port", "index")
            found.append("a required key that is absent must be refused")
        except spec.SpecError:
            pass

        return found


def main():
    if sys.version_info < (3, 11):
        running = ".".join(str(part) for part in sys.version_info[:3])
        print("FAIL  this needs Python 3.11 or newer for tomllib, and it is running under {}. "
              "Skipping would report success having checked nothing.".format(running))
        return 1
    found = failures()
    for line in found:
        print("FAIL  {}".format(line))
    if found:
        print("{} checks failed".format(len(found)))
        return 1
    print("ok    the declaration reader resolves what it knows and refuses the rest")
    return 0


if __name__ == "__main__":
    sys.exit(main())
