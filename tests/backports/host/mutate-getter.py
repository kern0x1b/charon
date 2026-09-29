#!/usr/bin/env python3
"""Remove ONE hand-written property getter, for the mutant protocol-conformance.sh runs.

    python3 mutate-getter.py FILE.m

This is the mutant the OLD criterion could not catch. -Wprotocol does not look at property accessors,
and -Wobjc-protocol-property-synthesis cannot tell a hand-written getter from a missing one, so a class
whose getter was deleted still reported exactly the same warnings as one that never had it. The AST
criterion is the only thing that notices, which is what this mutant proves.
"""
import re
import sys


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    source = open(path).read()
    # a getter with a body, and NO @synthesize above it in the same implementation, so the getter is
    # the only thing that defines it
    for match in re.finditer(r"^(- \([^)]*\)\s*(\w+)\n\{)", source, re.M):
        getter = match.group(2)
        if getter.startswith("init") or getter.startswith("new"):
            continue
        start = match.start()
        end = source.index("\n@end", start)
        implementation = source[start:end]
        if "@synthesize" in implementation and getter in implementation:
            continue
        open(path, "w").write(source[:start] + source[end + 1:])
        return 0
    print("mutate-getter: no hand-written getter to remove in %s" % path)
    return 1


if __name__ == "__main__":
    sys.exit(main())
