#!/usr/bin/env python3
"""Does a registry file's shape survive an edit? Two questions, one tool.

    tools/registry-shape.py [registry-root] [--against <git-ref>]

**1. Does any object carry the same key twice?** `json.load` does not say: it keeps the last of a
duplicate key, so a file that lost a brace between two entries parses cleanly and silently merges
them. That is not a shape a parse can see and a reader cannot - it has already been committed once
in this package, and the fix is a check rather than a habit. This reads every object with
`object_pairs_hook` and names any object that carries a key twice.

**2. Did an edit change the set of rows?** With `--against <ref>`, every registry file that differs
from that ref is read at both and the `api` lists are compared: a file may gain rows, lose rows or
gain duplicates, and a parse that succeeds is not a shape being right.

A run that reads no registry file at all is refused rather than reported as clean.
"""
import collections
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT = os.path.join(ROOT, "packages/a/apple-backports/registry")


def duplicates(path):
    """The objects in `path` that carry a key twice, with the key named."""
    found = []

    def hook(pairs):
        names = [k for k, _ in pairs]
        repeated = [k for k, n in collections.Counter(names).items() if n > 1]
        if repeated:
            found.append((repeated, dict(pairs)))
        return dict(pairs)

    with open(path) as handle:
        json.load(handle, object_pairs_hook=hook)
    return found


def entries_of(path):
    document = json.load(open(path))
    return document["entries"] if isinstance(document, dict) else document


def resolves(ref):
    """Does this ref name a commit in this repository? Asked before any comparison, so a typo cannot
    turn a comparison into a run that reports nothing and exits 0."""
    out = subprocess.run(["git", "rev-parse", "--verify", "--quiet", ref + "^{commit}"],
                         capture_output=True, text=True, cwd=ROOT)
    return out.returncode == 0


def apis_in(ref, relative):
    text = subprocess.run(["git", "show", "%s:%s" % (ref, relative)], capture_output=True, text=True)
    if text.returncode != 0:
        return None
    document = json.loads(text.stdout)
    return [r.get("api") for r in (document["entries"] if isinstance(document, dict) else document)]


def main():
    registry = DEFAULT
    against = None
    arguments = sys.argv[1:]
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        if argument == "--against" and index + 1 < len(arguments):
            against = arguments[index + 1]
            index += 2
            continue
        if not argument.startswith("--"):
            registry = argument
        index += 1
    files = sorted(
        os.path.join(base, name)
        for base, _, names in os.walk(registry)
        for name in names if name.endswith(".json")
    )
    if not files:
        print("no registry file under %s: nothing was checked, so nothing is claimed" % registry)
        return 1
    if against and not resolves(against):
        # A ref that does not resolve is not a comparison that found nothing: it is a comparison
        # that never happened, and the run has to say so and fail rather than report 0 problems.
        print("--against %s does not resolve in this repository: nothing was compared against it, so "
              "nothing is claimed" % against)
        return 1
    bad = 0
    compared = 0
    for path in files:
        for keys, object_ in duplicates(path):
            bad += 1
            print("DUPLICATE KEYS %s in %s: %s" % (",".join(keys), path, object_.get("api")))
    if against:
        for path in files:
            relative = os.path.relpath(path, registry)
            before = apis_in(against, "packages/a/apple-backports/registry/" + relative)
            if before is None:
                # the ref resolves but this file did not exist there: not a row list to compare
                continue
            compared += 1
            after = [r.get("api") for r in entries_of(path)]
            if before != after:
                bad += 1
                lost = [a for a in before if a not in after]
                gained = [a for a in after if a not in before]
                print("ROW LIST CHANGED %s: lost %s, gained %s" % (relative, lost or "none", gained or "none"))
    if against and compared == 0:
        print("--against %s resolved but no registry file of %s existed there: nothing was compared, so "
              "nothing is claimed" % (against, registry))
        return 1
    print("%d registry file(s) read under %s, %d problem(s)%s"
          % (len(files), registry, bad,
             (", %d row list(s) compared against %s" % (compared, against)) if against else ""))
    return 1 if bad else 0


sys.exit(main())
