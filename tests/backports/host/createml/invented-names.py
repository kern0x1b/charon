#!/usr/bin/env python3
"""The public types in this package that have no name in Apple's own interfaces.

    $ python3 tests/backports/host/createml/invented-names.py

Walks `packages/c/createml/files/**/*.swift` for public type declarations and the four macOS SDK
interfaces (TabularData, CreateMLComponents, CreateML, CoreML) for theirs, and prints the difference.
The table in `packages/a/apple-backports/facts/CreateML/InventedNames.md` is derived from this, so the
count can be re-derived rather than taken on report.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
SDK = pathlib.Path("/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks")
FRAMEWORKS = ("TabularData", "CreateMLComponents", "CreateML", "CoreML")
DECL = re.compile(r'^public (struct|final class|class|enum|protocol)\s+([A-Za-z_]\w*)', re.M)
SDKNAME = re.compile(r'^(?:@[\w()., ]+\s*)*(?:public |package )?'
                     r'(?:final class|class|struct|enum|protocol)\s+([A-Za-z_]\w*)', re.M)


def port_types():
    found = {}
    for f in sorted((ROOT / "packages/c/createml/files").glob("**/*.swift")):
        for m in DECL.finditer(f.read_text()):
            found.setdefault(m.group(2), f.relative_to(ROOT).as_posix())
    return found


def sdk_types():
    found = {}
    for fw in FRAMEWORKS:
        d = SDK / ("%s.framework/Modules/%s.swiftmodule" % (fw, fw))
        if not d.is_dir():
            print("no SDK module for %s - its names are NOT in the comparison" % fw, file=sys.stderr)
            continue
        for itf in d.glob("*.swiftinterface"):
            for m in SDKNAME.finditer(itf.read_text()):
                found.setdefault(m.group(1), fw)
    return found


if __name__ == "__main__":
    mine, theirs = port_types(), sdk_types()
    extra = sorted(t for t in mine if t not in theirs)
    print("port public types: %d   SDK names: %d   no SDK name: %d" % (len(mine), len(theirs), len(extra)))
    for t in extra:
        print("  %-40s %s" % (t, mine[t]))
