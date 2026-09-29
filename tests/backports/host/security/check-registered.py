#!/usr/bin/env python3
"""Every constant the port defines has a row, and every row of those names is defined — both ways.

    python3 check-registered.py [--control]

GENERATED FROM THE NAMES LIST, not from the registry and not from the objects, so the comparison cannot
be satisfied by a list that is itself wrong: the list is the one the case file asks about, and
gen-security-cases.py --check says the case file is what the list says. A check that read the objects
would agree with the objects.

THE CONTROL deletes one row on a scratch copy and requires this to go red NAMING that constant, after
the copy has been shown green — a control that fails on a copy that was already broken proves nothing.
"""
import glob
import json
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WORKTREE = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
OBJECTS = os.path.join(WORKTREE, "packages", "a", "apple-backports", "Security")
REGISTRY = os.path.join(WORKTREE, "packages", "a", "apple-backports", "registry", "Security")


def names():
    return sorted(l.strip() for l in open(os.path.join(HERE, "algorithms.txt")) if l.strip())


def defined(objects=OBJECTS):
    found = set()
    for path in sorted(glob.glob(os.path.join(objects, "SecurityConstants*.m"))):
        for name in re.findall(r"^const CFStringRef (\w+) = CFSTR", open(path).read(), re.M):
            found.add(name)
    return found


def rows(registry=REGISTRY):
    out = {}
    for path in sorted(glob.glob(os.path.join(registry, "*.json"))):
        data = json.load(open(path))
        for row in (data if isinstance(data, list) else data.get("entries", [])):
            if isinstance(row, dict) and row.get("kind") == "constant":
                out[row["api"]] = row
    return out


def check(objects=OBJECTS, registry=REGISTRY):
    wanted, built, recorded = set(names()), defined(objects), rows(registry)
    problems = []
    for name in sorted(wanted):
        if name not in built:
            problems.append("%s is in the list and no object defines it" % name)
        if name not in recorded:
            problems.append("%s is in the list and has no registry row" % name)
        elif recorded[name].get("status") != "implemented":
            problems.append("%s has a row whose status is %r, not implemented"
                            % (name, recorded[name].get("status")))
    for name in sorted(built & wanted):
        row = recorded.get(name, {})
        if not row.get("facts"):
            problems.append("%s has a row with no facts path" % name)
        if not row.get("source"):
            problems.append("%s has a row with no source" % name)
    print("%d in the list, %d defined, %d rows of kind constant" % (len(wanted), len(built), len(recorded)))
    return problems


def control():
    scratch = os.path.join(WORKTREE, ".agent-work", "runs", "security", "registered-control")
    shutil.rmtree(scratch, ignore_errors=True)
    os.makedirs(scratch)
    for path in sorted(glob.glob(os.path.join(REGISTRY, "*.json"))):
        shutil.copy(path, scratch)
    before = check(OBJECTS, scratch)
    if before:
        print("CONTROL cannot start: the copy is red before the removal: %s" % before[0])
        return 1
    victim = names()[0]
    for path in sorted(glob.glob(os.path.join(scratch, "*.json"))):
        data = json.load(open(path))
        entries = data if isinstance(data, list) else data.get("entries", [])
        kept = [r for r in entries if r.get("api") != victim]
        if len(kept) != len(entries):
            with open(path, "w") as handle:
                json.dump(data if isinstance(data, list) else {"framework": "Security", "entries": kept},
                          handle, indent=1)
                handle.write("\n")
            break
    after = check(OBJECTS, scratch)
    named = [p for p in after if p.startswith(victim + " ")]
    print("CONTROL removed the row for %s: %s" % (victim, named[0] if named else "NOT CAUGHT"))
    shutil.rmtree(scratch, ignore_errors=True)
    return 0 if named else 1


def main():
    status = 0
    for problem in check():
        print("FAIL " + problem)
        status = 1
    if "--control" in sys.argv:
        status = status or control()
    print("check-registered: %s" % ("RED" if status else "OK"))
    return status


if __name__ == "__main__":
    sys.exit(main())
