#!/usr/bin/env python3
"""swiftregistry.py — every row of packages/s/swift-runtime/registry/ that says `implemented` has a
declaration in packages/s/swift-runtime/files/.

Why this test exists: on 2026-09-28 the family review found `EnvironmentResource` used in five
places in `ARView.swift` and declared nowhere, with a registry row calling it
`kind: class, status: implemented` — a row with no code behind it, in a module that did not
compile. Nothing caught it: the light guard, both band gates and a 300-check host differential all
passed, because a Swift module exports no symbol a dylib inventory sees, so `check_registry` cannot
read these rows (registry/README.md says so) and no other check reads them at all.

This is that check. It is a declaration-level check, not a behavioural one: a type row must have a
`class`/`struct`/`enum`/`protocol`/`actor`/`typealias` declaration by that name in the two overlay
source trees. Member rows are not checked here — a member of a declared type is the host
differential's job — and a row that is not `implemented` is not checked, because an absent row is
supposed to have no declaration.

Exit 0 when every implemented row has a declaration, 1 with the list of the ones that do not.
"""

import json
import os
import re
import sys

KINDS = ("class", "struct", "enum", "protocol", "actor", "typealias")
TYPE_STATUSES = ("implemented",)
MEMBER_KINDS = ("method", "property", "init", "subscript", "var", "func", "case", "initializer")


def sources(root):
    """Every Swift file of the two overlay modules, as one text."""
    text = []
    for module in ("RealityFoundation", "RealityKit"):
        folder = os.path.join(root, "files", module)
        if not os.path.isdir(folder):
            sys.exit(f"no {module} overlay sources at {folder}")
        for name in sorted(os.listdir(folder)):
            if name.endswith(".swift"):
                with open(os.path.join(folder, name), encoding="utf-8") as handle:
                    text.append(handle.read())
    return "\n".join(text)


def rows(registry):
    with open(registry, encoding="utf-8") as handle:
        document = json.load(handle)
    return document.get("entries", [])


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.environ.get("SWIFTREGISTRY_PACKAGE", os.path.join(here, "..", "..", "..", "..", "packages", "s", "swift-runtime"))
    root = os.path.abspath(root)
    tree = sources(root)
    failures = []
    checked = 0
    for name in ("RealityFoundation.json", "RealityKit.json"):
        registry = os.path.join(root, "registry", name)
        if not os.path.isfile(registry):
            failures.append(f"{name}: no such registry")
            continue
        for row in rows(registry):
            if row.get("status") not in TYPE_STATUSES:
                continue
            if row.get("kind") not in KINDS:
                continue
            checked += 1
            # The row's name is qualified when the type is nested - `ARView.RenderOptions` - and a
            # declaration is spelled by the type's own name, so the last piece is the one to look
            # for.
            qualified = row["api"]
            declared = qualified.rsplit(".", 1)[-1]
            if not re.search(r"\b(%s)\s+%s\b" % ("|".join(KINDS), re.escape(declared)), tree):
                failures.append(f"{name}: {qualified} ({row['kind']}, {row['status']}) has no declaration in files/")
                continue
            # A qualified name is a path, and every step of it has to be a type this tree declares:
            # `ARView.Environment.Background` is only that name if `ARView.Environment` and
            # `Background` are both declared. A nested spelling and a file-scope type re-exported
            # under its owner's name are both legitimate, and this does not care which - it checks
            # that the names exist, not the mechanism that binds them.
            for step in qualified.split(".")[:-1]:
                if not re.search(r"\b(%s)\s+%s\b" % ("|".join(KINDS), re.escape(step)), tree):
                    failures.append(f"{name}: {qualified} names {step}, which files/ does not declare, so the path "
                                    f"cannot be written")
                    break
    if failures:
        for failure in failures:
            print(f"FAIL {failure}")
        print(f"swiftregistry: {len(failures)} implemented row(s) with no declaration, of {checked} checked")
        return 1
    print(f"ok   every implemented type row has a declaration ({checked} rows)")
    print(f"ok   swiftregistry: {checked} implemented type rows, {len(failures)} without a declaration")
    return 0


if __name__ == "__main__":
    sys.exit(main())
