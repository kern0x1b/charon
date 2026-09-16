#!/usr/bin/env python3
"""Check what the recipe index check refuses and what it reports.

    tests/index_test.py

It builds small recipe indexes and asks the check about them through Conan's own
trim, so a change in how Conan exports a local index shows up here first.
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import declaration_test

HERE = Path(__file__).resolve().parent
CHECKER = HERE.parent / "config" / "extensions" / "charon" / "indexes.py"

CANONICAL = "sources:\n  1.0.0:\n    sha256: abc\n    url: https://example.invalid/one.tar.gz\n"
HAND_WRITTEN = 'sources:\n  "1.0.0":\n    url: "https://example.invalid/one.tar.gz"\n    sha256: "abc"\n'
BY_SOURCE_NAME = ("sources:\n  tdlib:\n    url: https://example.invalid/td.tar.gz\n"
                  "patches:\n  1.0.0:\n  - patch_file: patches/hook.patch\n")


def index(folder, recipes):
    for name, text in recipes.items():
        (folder / "recipes" / name / "all").mkdir(parents=True)
        (folder / "recipes" / name / "config.yml").write_text('versions:\n  "1.0.0":\n    folder: all\n')
        (folder / "recipes" / name / "all" / "conandata.yml").write_text(text)
    return folder


def checked(*arguments):
    return subprocess.run([sys.executable, str(CHECKER)] + [str(argument) for argument in arguments],
                          capture_output=True, text=True)


def failures():
    found = []
    with tempfile.TemporaryDirectory() as scratch:
        clean = index(Path(scratch) / "clean", {"canonical": CANONICAL})
        result = checked("--canonical", clean)
        if result.returncode or result.stdout.strip():
            found.append("a version-keyed conandata the trim leaves alone must pass silently: {} {}".format(
                result.stdout, result.stderr))

        written = index(Path(scratch) / "written", {"handwritten": HAND_WRITTEN})
        result = checked("--canonical", written)
        if result.returncode or "rewritten  recipes/handwritten/all/conandata.yml" not in result.stdout:
            found.append("a conandata the trim rewrites must be reported and not refused: {} {}".format(
                result.stdout, result.stderr))
        if checked(written).stdout.strip():
            found.append("without --canonical, a rewritten conandata must not be reported")

        named = index(Path(scratch) / "named", {"tdlib": BY_SOURCE_NAME})
        result = checked(named)
        if result.returncode != 1 or "tdlib 1.0.0: sources has no entry for 1.0.0" not in result.stdout:
            found.append("a table keyed by something other than the version must be refused, naming it: {} {}"
                         .format(result.stdout, result.stderr))
        if "patches" in result.stdout:
            found.append("a table keyed by version must not be named as dropped: {}".format(result.stdout))
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
        import conan  # noqa: F401
    except ImportError as missing:
        print("FAIL  this needs an interpreter that can import conan: {}".format(missing))
        return 1
    found = failures()
    for line in found:
        print("FAIL  {}".format(line))
    if found:
        print("{} checks failed".format(len(found)))
        return 1
    print("ok    a recipe index that would drop part of a conandata.yml is refused, and a rewritten one is named")
    return 0


if __name__ == "__main__":
    sys.exit(main())
