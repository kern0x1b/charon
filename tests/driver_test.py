#!/usr/bin/env python3
"""Check which folder the driver takes for a built engine, and what it refuses.

    tests/driver_test.py

engine_build is the one name a port imports to find its build, so a port keeps no
definition of a build tree of its own. These cases pin that definition: a tree is
a direct child of build/ that cmake configured and that has frameworks laid out,
and nothing else under build/ qualifies however much it resembles one.
"""
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "config" / "extensions" / "charon"))

import charon


def tree(root, relative, staged=True, configured=True):
    folder = root / relative
    folder.mkdir(parents=True, exist_ok=True)
    if configured:
        (folder / "CMakeCache.txt").write_text("")
    if staged:
        framework = folder / "stage" / "usr" / "lib" / "rev-fw" / "WebKit.framework"
        framework.mkdir(parents=True, exist_ok=True)
        (framework / "WebKit").write_text("")
    return folder


def answer(root, variant=None):
    try:
        return charon.engine_build(root, variant)
    except LookupError as refused:
        return refused


def failures():
    found = []

    def check(description, build, expect):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            wanted = build(root)
            got = answer(root, getattr(build, "variant", None))
            if expect == "refuse":
                if not isinstance(got, LookupError):
                    found.append("{} must be refused: got {}".format(description, got))
            elif got != wanted:
                found.append("{}: expected {}, got {}".format(description, wanted, got))

    check("one configured tree with staged frameworks is the answer",
          lambda root: tree(root, "build/system"), "tree")

    check("no tree at all",
          lambda root: None, "refuse")

    def two(root):
        tree(root, "build/system")
        tree(root, "build/prefixed")
    check("two built trees with no variant named", two, "refuse")

    def named(root):
        tree(root, "build/system")
        return tree(root, "build/prefixed")
    named.variant = "prefixed"
    check("a named variant is taken without searching", named, "tree")

    def named_unbuilt(root):
        tree(root, "build/system")
        (root / "build" / "prefixed").mkdir(parents=True)
    named_unbuilt.variant = "prefixed"
    check("a named variant that exists as a folder but was never built", named_unbuilt, "refuse")

    def named_unstaged(root):
        tree(root, "build/system")
        tree(root, "build/prefixed", staged=False)
    named_unstaged.variant = "prefixed"
    check("a named variant that was configured but has nothing laid out", named_unstaged, "refuse")

    def tier_packages(root):
        env = root / "build" / "tier-packages" / "host" / "conan"
        env.mkdir(parents=True)
        (env / "charon-deps.env").write_text("CHARON_HOST_ICU=/nowhere\n")
    check("a tier's package environment shaped like a build marker", tier_packages, "refuse")

    def nested(root):
        tree(root, "build/engine/armv7-system")
    check("the retired build/engine/<arch>-<variant> layout, which is not a direct child", nested, "refuse")

    def unstaged(root):
        tree(root, "build/system", staged=False)
    check("a configured tree with nothing laid out", unstaged, "refuse")

    def contains_variant(root):
        tree(root, "build/system")
        tier = root / "build" / "system-imports" / "conan"
        tier.mkdir(parents=True)
        (tier / "charon-deps.env").write_text("")
        return root / "build" / "system"
    check("a folder whose name contains a variant but that nothing configured", contains_variant, "tree")

    return found


def undefined_names():
    import ast
    import builtins
    found = []
    folder = HERE.parent / "config" / "extensions" / "charon"
    for path in sorted(folder.glob("*.py")) + sorted((HERE.parent / "recipes").glob("*/all/conanfile.py")):
        tree = ast.parse(path.read_text())
        bound = set(dir(builtins)) | {"__file__", "__doc__", "__name__"}
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                bound.add(node.name)
            elif isinstance(node, ast.Name) and isinstance(node.ctx, (ast.Store, ast.Del)):
                bound.add(node.id)
            elif isinstance(node, ast.arg):
                bound.add(node.arg)
            elif isinstance(node, (ast.Import, ast.ImportFrom)):
                bound.update((alias.asname or alias.name).split(".")[0] for alias in node.names)
            elif isinstance(node, ast.ExceptHandler) and node.name:
                bound.add(node.name)
        for node in ast.walk(tree):
            if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load) and node.id not in bound:
                found.append("{}:{} uses {}, which nothing in that file defines; it fails only when that line "
                             "runs".format(path.name, node.lineno, node.id))
    return found


def merge_failures():
    found = []
    base = '[variants.armv7]\n[variants.arm64]\n'
    cases = (
        ("one variant merges", base + '[variants.app]\nmerge = ["armv7", "arm64"]\n', "app", ["armv7", "arm64"]),
        ("two variants merge", base + '[variants.a]\nmerge = ["armv7", "arm64"]\n[variants.b]\n'
                               'merge = ["armv7", "arm64"]\n', None, None),
        ("a slice nobody declares", base + '[variants.app]\nmerge = ["armv7", "ghost"]\n', "app", None),
        ("a merge of one slice", base + '[variants.app]\nmerge = ["armv7"]\n', "app", None),
        ("a merge that names itself", base + '[variants.app]\nmerge = ["armv7", "app"]\n', "app", None),
        ("a slice that merges", '[variants.armv7]\nmerge = ["arm64", "x"]\n[variants.arm64]\n[variants.x]\n'
                                '[variants.app]\nmerge = ["armv7", "arm64"]\n', "app", None),
    )
    for description, text, variant, expected in cases:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "charon.toml").write_text(text)
            try:
                chosen = variant or charon.default_variant(root)
                if variant and description == "one variant merges" and charon.default_variant(root) != "app":
                    found.append("the only variant that merges must be the default")
                slices = charon.merged_slices(root, chosen)
                if expected is None:
                    found.append("{} must be refused".format(description))
                elif slices != expected:
                    found.append("{}: slices must be {} in declared order, got {}".format(
                        description, expected, slices))
            except charon.Failure:
                if expected is not None:
                    found.append("{} must be accepted".format(description))
    return found


def refusal_failures():
    found = []
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        (root / "main.m").write_text("")
        (root / "charon.toml").write_text(
            '[port]\nname = "p"\nversion = "1"\n[target]\narch = "armv7"\nos = "iOS"\nos-version = "6.0"\n'
            '[variants.system]\n[application]\nname = "Host"\nsources = ["main.m"]\ninclude = ["gone"]\n')
        try:
            charon.generated(root, "system")
            found.append("a declaration generation refuses must stop the driver")
        except charon.Failure as refused:
            if "gone" not in str(refused):
                found.append("the driver must pass generation's own reason on: got {}".format(refused))
        except Exception as escaped:
            found.append("a refusal from generation must reach the user as a charon: line, not as {}".format(
                type(escaped).__name__))
    return found


def index_failures():
    found = []
    original = charon.remotes
    with tempfile.TemporaryDirectory() as folder:
        index = Path(folder)
        (index / "recipes" / "tdlib" / "all").mkdir(parents=True)
        (index / "recipes" / "tdlib" / "config.yml").write_text('versions:\n  "1.0.0":\n    folder: all\n')
        (index / "recipes" / "tdlib" / "all" / "conandata.yml").write_text(
            "sources:\n  tdlib:\n    url: https://example.invalid/td.tar.gz\n")
        charon.remotes = lambda: [{"name": "port", "url": str(index), "enabled": True},
                                  {"name": "center", "url": "https://example.invalid", "enabled": True}]
        try:
            charon.verb_build(index, None)
            found.append("a build must stop before anything runs when an index would drop part of a recipe")
        except charon.Failure as refused:
            if "conandata" not in str(refused):
                found.append("a build must be refused for the index, not for something else: got {}".format(refused))
        except Exception as escaped:
            found.append("the index check must run before a build does anything else: {} {}".format(
                type(escaped).__name__, escaped))
        finally:
            charon.remotes = original
    return found


def where_failures():
    import json as encoded
    import types
    found = []
    graph = {"graph": {"nodes": {
        "0": {"name": None, "context": "host", "binary": None},
        "1": {"name": "tdlib", "context": "host", "ref": "tdlib/1.8.67@itglegacy/stable#aaa", "package_id": "p1",
              "binary": "Cache"},
        "2": {"name": "ld64", "context": "build", "ref": "ld64/956.6@charon/stable#bbb", "package_id": "p2",
              "binary": "Cache"},
        "3": {"name": "ld64", "context": "build", "ref": "ld64/956.6@charon/stable#bbb", "package_id": "p2",
              "binary": "Skip"},
        "4": {"name": "absent", "context": "host", "ref": "absent/1@x/y#ccc", "package_id": "p3", "binary": "Missing"},
    }}}
    calls = []

    def fake_conan(*arguments, **options):
        calls.append(arguments)
        if arguments[0] == "graph":
            return types.SimpleNamespace(returncode=0, stdout=encoded.dumps(graph))
        if arguments[:2] == ("cache", "path"):
            known = {"tdlib/1.8.67@itglegacy/stable#aaa:p1": "/cache/tdlib", "ld64/956.6@charon/stable#bbb:p2": "/cache/ld64"}
            answer = known.get(arguments[2], "")
            return types.SimpleNamespace(returncode=0 if answer else 1, stdout=answer)
        raise AssertionError(arguments)

    saved = charon.conan, charon.generated, charon.variant_profile, charon.variant_options
    charon.conan = fake_conan
    charon.generated = lambda root, variant, report=None: root
    charon.variant_profile = lambda root, parsed, variant: Path("/profile")
    charon.variant_options = lambda root, variant: []
    parsed = types.SimpleNamespace(variant="armv7", profile=None)
    try:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for wanted, answer in (("pkg:tdlib", "/cache/tdlib"), ("tool:ld64", "/cache/ld64")):
                got = charon.package_folder(root, parsed, wanted)
                if got != answer:
                    found.append("charon where {} must print {}: got {}".format(wanted, answer, got))
            if any("--build=missing" in call for call in calls):
                found.append("asking where a package is must never build anything")
            for wanted, reason in (("pkg:ld64", "has no package ld64"), ("tool:tdlib", "has no tool tdlib"),
                                   ("tdlib", "answers pkg:NAME"), ("pkg:absent", "not in the cache yet")):
                try:
                    charon.package_folder(root, parsed, wanted)
                    found.append("charon where {} must be refused".format(wanted))
                except charon.Failure as refused:
                    if reason not in str(refused):
                        found.append("charon where {} must be refused for that reason: {}".format(wanted, refused))
    finally:
        charon.conan, charon.generated, charon.variant_profile, charon.variant_options = saved
    return found


def tier_failures():
    found = []
    tiers = {"scripts": {"needs": []}, "flags": {"needs": ["build"]}, "gate": {"needs": ["device"]},
             "batteries": {"needs": ["device", "build"]}}
    if charon.tiers_by_phone(tiers, False) != ["scripts", "flags"]:
        found.append("integrate must run every tier that needs no phone before deploying, in declared order")
    if charon.tiers_by_phone(tiers, True) != ["gate", "batteries"]:
        found.append("integrate must run every tier that needs the phone after deploying, in declared order")
    return found


def task_failures():
    found = []
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        (root / "charon.toml").write_text('[tasks.audit]\nscript = "a.py"\n\n[tasks.greet]\nshell = "echo hi"\n')
        if charon.task_steps(root, ["greet", "audit"]) != ["task:greet", "task:audit"]:
            found.append("named tasks must become task steps in the order they were named")
        for names, why in (([], "charon task with no names"), (["greet", "absent"], "a task nobody declared")):
            try:
                charon.task_steps(root, names)
                found.append("{} must be refused before anything is built".format(why))
            except charon.Failure:
                pass
    return found


def main():
    if sys.version_info < (3, 11):
        print("FAIL  this needs Python 3.11 or newer for tomllib, and it is running under {}. Skipping would "
              "report success having checked nothing.".format(".".join(str(p) for p in sys.version_info[:3])))
        return 1
    found = failures() + task_failures() + tier_failures() + merge_failures() + refusal_failures() + index_failures() + where_failures() + undefined_names()
    for line in found:
        print("FAIL  {}".format(line))
    if found:
        print("{} checks failed".format(len(found)))
        return 1
    print("ok    the driver takes a configured, laid-out direct child of build/ and nothing that only resembles one")
    return 0


if __name__ == "__main__":
    sys.exit(main())
