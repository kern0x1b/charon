#!/usr/bin/env python3
"""Count the registry rows a facts file answers for: rows whose `facts` is that file.

    tools/registry-facts-rows.py [registry-root] [facts-path] [[lo-hi]]

`NSURLResourceKeyStrings.md` says how many constants it covers, and a number in a facts file that
nobody can recompute is a number that goes stale. The walk is here so the sentence can name it: the rows
whose `facts` is that path, optionally restricted to an `introduced` window. It also settles what the
sentence may claim - that file's count reads 44 on `6fcdc631b` and 45 from `568b5f846` on, because a
row the earlier `foundation-absent-2` answered joined the set, so a count that was right when it was
written is not wrong now.

A path with no registry under it is refused **before anything is printed**, the way
`tools/registry-absent.py` does it: a count of zero next to the refusal is the number the reader keeps.
"""
import collections
import glob
import json
import os
import sys

REG = sys.argv[1] if len(sys.argv) > 1 else "packages/a/apple-backports/registry"
WANT = sys.argv[2] if len(sys.argv) > 2 else "facts/Foundation/NSURLResourceKeyStrings.md"
WINDOW = sys.argv[3] if len(sys.argv) > 3 else None


def parts(version):
    return tuple(int(piece) for piece in version.split("."))


def main():
    files = sorted(glob.glob(os.path.join(REG, "**", "*.json"), recursive=True))
    if not files:
        # first, and printing nothing: the refusal is the whole output
        print("no registry under %s: nothing was counted, so nothing is claimed" % REG, file=sys.stderr)
        return 1
    low = high = None
    if WINDOW:
        low, high = WINDOW.split("-")
    rows = []
    for path in files:
        document = json.load(open(path))
        entries = document["entries"] if isinstance(document, dict) else document
        for entry in entries:
            if entry.get("facts") != WANT:
                continue
            introduced = entry.get("introduced") or ""
            if low and not (parts(low) <= parts(introduced) < parts(high)):
                continue
            rows.append((entry.get("api"), introduced, entry.get("status")))
    print("%d rows point at %s%s" % (len(rows), WANT, (" with introduced in [%s, %s)" % (low, high)) if low else ""))
    for status, n in sorted(collections.Counter(s for _, _, s in rows).items()):
        print("   %s: %d" % (status, n))
    return 0


sys.exit(main())
