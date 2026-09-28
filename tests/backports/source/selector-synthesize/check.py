#!/usr/bin/env python3
"""A @synthesize and a hand-written accessor for the same property, in the same @implementation.

One implementation carrying both is two definitions of one method, and the compiler keeps one of them
without saying which. The cost is silent: the getter that survives can be the wrong one, and nothing
in the build, the link or the gate reports it. A category redefining a selector that the primary
implementation synthesised is ordinary and is NOT this - so the file is split into @implementation
blocks and a collision is only counted inside one of them.

The check proves itself before it reports anything, against two files kept beside it: one that has the
shape and one that does not. A check that cannot fail is not a check, and a detector that has not been
shown to find a known case is not evidence either.

    ./run.sh            the whole package, plus the two proofs
    ./check.py <file|dir>   one file, or every .m under one directory
"""
import os
import re
import sys

IMPLEMENTATION = re.compile(r"@implementation\s+(\w+)\s*(\([^)]*\))?(.*?)\n@end", re.S)
IMPL_FLAGS = re.S
SYNTHESIZE = re.compile(r"@synthesize\s+([A-Za-z_][A-Za-z0-9_]*)\s*=")


def find(path):
    """The collisions in one file: (class, category-or-primary, property, synthesize line, accessor line)."""
    with open(path) as handle:
        text = handle.read()
    hits = []
    for match in IMPLEMENTATION.finditer(text):
        name = match.group(1)
        category = (match.group(2) or "").strip() or "primary"
        body = match.group(3)
        body_at = match.start(3)
        flat = re.sub(r"\n\s*", " ", body)
        for synth in SYNTHESIZE.findall(flat):
            accessor = None
            for kind in ("-", "+"):
                hit = re.search(re.escape(kind) + r"\s*\([^)]*\)\s*" + re.escape(synth) + r"\s*\{", flat)
                if hit:
                    accessor = (text[:body_at + hit.start()].count("\n") + 1, kind)
                    break
            if accessor is None:
                continue
            at = flat.find("@synthesize %s" % synth)
            hits.append((name, category, synth,
                         text[:body_at + at].count("\n") + 1, accessor[0]))
    return hits


def expand(argument):
    """The source files named by one argument, which may be a file or a directory.

    A directory is walked rather than opened, so `run.sh some/dir` answers the question about that
    directory instead of raising IsADirectoryError out of open() - which is what it did, and a
    documented path that cannot be taken is not a documented path.
    """
    if os.path.isdir(argument):
        found = []
        for base, _, names in os.walk(argument):
            for name in sorted(names):
                if name.endswith(".m"):
                    found.append(os.path.join(base, name))
        return found
    return [argument] if os.path.exists(argument) else []


def here(*parts):
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), *parts)


def prove():
    """The two proofs. If these do not hold the check is not reporting anything, so it says so."""
    trapped = find(here("proofs", "trapped-PHASEEngine.m"))
    clean = find(here("proofs", "clean-PHASEEngine.m"))
    problems = []
    if [h[2] for h in trapped] != ["rootObject"]:
        problems.append("the known trapped file no longer reports rootObject, so the check cannot find "
                        "the shape it exists to find")
    if clean:
        problems.append("the known clean file reports %s, so the check reports shapes that are not there"
                        % [h[2] for h in clean])
    for problem in problems:
        sys.stderr.write("FAIL the check does not prove itself: %s\n" % problem)
    if not problems:
        print("ok   the check proves itself: it finds rootObject in the trapped proof and nothing in "
              "the clean one")
    return not problems


def main():
    if not prove():
        return 1
    if len(sys.argv) > 1:
        reported = 0
        for argument in sys.argv[1:]:
            for path in expand(argument):
                for name, category, synth, synth_line, accessor_line in find(path):
                    reported += 1
                    print("%s  %s %s  %s  @synthesize:%d  accessor:%d"
                          % (path, name, category, synth, synth_line, accessor_line))
        if reported == 0:
            print("no collision in %s" % " ".join(sys.argv[1:]))
        return 0
    # four levels up: selector-synthesize -> source -> backports -> tests -> the repository root
    root = here("..", "..", "..", "..")
    checked = hits = 0
    for folder in ("packages", "modules"):
        for base, _, names in os.walk(os.path.join(root, folder)):
            for name in names:
                if not name.endswith(".m"):
                    continue
                path = os.path.join(base, name)
                checked += 1
                found = find(path)
                hits += len(found)
                for owner, category, synth, synth_line, accessor_line in found:
                    print("%s  %s %s  %s  @synthesize:%d  accessor:%d"
                          % (os.path.relpath(path, root), owner, category, synth, synth_line, accessor_line))
    print("checked %d source files, %d collision(s)" % (checked, hits))
    return 0


if __name__ == "__main__":
    sys.exit(main())
