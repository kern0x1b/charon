#!/usr/bin/env python3
"""Does the package's own code read through every registry row that says it calls out?

A row whose `effect` says the call leaves the package -- a protocol member an application's own
class implements, which the port names at a call site -- is a claim about the tree, and a claim about
the tree is checkable: the selector has to appear in the package's own sources, at the place the row
names. This walks the registry, finds every row whose `effect` names a call site (a file and a line,
`Some/Class.m:123`), reads that line, and reports the rows whose line does not name the row's own
member. A row the tree has never heard of, or whose line has moved, is reported rather than assumed.

    tools/registry-called-through.py [registry-root] [package-root]     a count; exit 1 if any row is uncalled
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGISTRY = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "packages/a/apple-backports/registry")
PACKAGE = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "packages/a/apple-backports")

CALL_SITE = re.compile(r"([A-Za-z0-9_+./-]+\.[mc]):(\d+)")


def members_of(api, kind):
    """The spellings a source file can use for a row's member.

    A call site writes the whole selector, and a definition writes it with the parameter names in
    place of the colons (- (NSProgress *)loadDataWithTypeIdentifier:(NSString *)typeIdentifier ...),
    so the first component is the spelling both have.
    """
    if kind == "method":
        match = re.match(r"^[-+]\[([A-Za-z0-9_]+) (.+)\]$", api)
        if not match:
            return []
        selector = match.group(2)
        return [selector, selector.split(":", 1)[0]]
    if kind == "property":
        return [api.split(".", 1)[1]] if "." in api else []
    return [api]


def main():
    rows = 0
    called = 0
    uncalled = []
    for path in sorted(glob.glob(os.path.join(REGISTRY, "**", "*.json"), recursive=True)):
        document = json.load(open(path))
        entries = document["entries"] if isinstance(document, dict) else document
        for entry in entries:
            effect = entry.get("effect") or ""
            site = CALL_SITE.search(effect)
            if not site:
                continue
            rows += 1
            named = site.group(1)
            source = os.path.join(PACKAGE, named)
            if not os.path.isfile(source) and os.sep not in named:
                # an effect that names a bare file name, as AuthenticationServices' does: the package
                # holds it in a per-framework folder, and a name that is in two of them is not a check
                found = glob.glob(os.path.join(PACKAGE, "*", named))
                if len(found) == 1:
                    source = found[0]
            names = members_of(entry.get("api", ""), entry.get("kind", ""))
            if not os.path.isfile(source):
                uncalled.append((entry.get("api"), site.group(0), "the file the effect names is not there"))
                continue
            lines = open(source).read().splitlines()
            number = int(site.group(2))
            if number > len(lines):
                uncalled.append((entry.get("api"), site.group(0), "the line the effect names is past the end"))
                continue
            window = "\n".join(lines[max(0, number - 4):number + 3])
            if any(name in window for name in names):
                called += 1
            else:
                uncalled.append((entry.get("api"), site.group(0), "the line does not name the member"))
    for api, site, why in uncalled:
        print("UNCALLED %-64s %s  %s" % (api, site, why))
    if rows == 0:
        print("no row under %s names a call site in its effect: nothing was checked" % REGISTRY)
        return 1
    print("%d rows name a call site, %d read through it, %d do not" % (rows, called, len(uncalled)))
    return 1 if uncalled else 0


sys.exit(main())
