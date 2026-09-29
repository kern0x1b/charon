#!/usr/bin/env python3
"""Each VideoToolbox string constant is defined in the object of the release its registry row names.

An object carries the API of one release (the gate refuses one that holds several), so the 135 constants are
split into VideoToolboxConstants<major>_<minor>.m, one file per release. This holds the split both ways:

  * every constant a file defines has a registry row (kind constant) whose `introduced` is the release in
    that file's name, and
  * every constant is defined exactly once. (The registry also holds constants no file of these defines,
    the ones the framework itself exports, so rows without a definition are not this check's.)

    python3 tests/backports/host/videotoolbox/check-constant-files.py            # the tree
    python3 tests/backports/host/videotoolbox/check-constant-files.py --control  # and the control below

The control works on a scratch copy under .agent-work/runs/vtclass/ (never on the tree): it moves one
constant's line into the file of another release and requires the check to go red NAMING that constant, and
it requires the copy to be green before the move, so a check that is red for another reason cannot pass it.
"""
import glob
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WORKTREE = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
PACKAGE = os.path.join(WORKTREE, "packages", "a", "apple-backports")


def registry_releases(registry):
    found = {}
    for path in sorted(glob.glob(os.path.join(registry, "*.json"))):
        for row in json.load(open(path)).get("entries", []):
            if row.get("kind") == "constant":
                found[row["api"]] = row["introduced"]
    return found


def file_release(path):
    match = re.match(r"VideoToolboxConstants(\d+)_(\d+)\.m$", os.path.basename(path))
    return "%s.%s" % match.groups() if match else None


def check(objects, registry):
    releases = registry_releases(registry)
    problems, defined = [], {}
    files = sorted(glob.glob(os.path.join(objects, "VideoToolboxConstants*.m")))
    for path in files:
        release = file_release(path)
        if release is None:
            problems.append("%s: a file of constants whose name does not say a release" % os.path.basename(path))
            continue
        for name in re.findall(r"^const CFStringRef (\w+) = CFSTR", open(path).read(), re.M):
            if name in defined:
                problems.append("%s is defined twice: %s and %s" % (name, defined[name], os.path.basename(path)))
            defined[name] = os.path.basename(path)
            if name not in releases:
                problems.append("%s (in %s) has no registry row" % (name, os.path.basename(path)))
            elif releases[name] != release:
                problems.append("%s is in %s but its row says %s" % (name, os.path.basename(path), releases[name]))
    print("%d constants defined by %d files, %d registry rows of kind constant" % (len(defined), len(files), len(releases)))
    return problems


def control(objects, registry):
    scratch = os.path.join(WORKTREE, ".agent-work", "runs", "vtclass", "constant-files-control")
    shutil.rmtree(scratch, ignore_errors=True)
    os.makedirs(scratch)
    for path in glob.glob(os.path.join(objects, "VideoToolboxConstants*.m")):
        shutil.copy(path, scratch)
    before = check(scratch, registry)
    if before:
        print("CONTROL cannot start: the copy is red before the move: %s" % before[0])
        return 1
    files = sorted(glob.glob(os.path.join(scratch, "VideoToolboxConstants*.m")))
    source, target = files[0], files[-1]
    lines = open(source).read().split("\n")
    index = next(i for i, l in enumerate(lines) if l.startswith("const CFStringRef "))
    moved = lines.pop(index)
    name = re.match(r"const CFStringRef (\w+)", moved).group(1)
    open(source, "w").write("\n".join(lines))
    open(target, "a").write(moved + "\n")
    after = check(scratch, registry)
    named = [p for p in after if p.startswith(name + " ")]
    print("CONTROL moved %s from %s into %s: %s" % (name, os.path.basename(source), os.path.basename(target),
                                                    named[0] if named else "NOT CAUGHT"))
    return 0 if named else 1


def main():
    objects = os.path.join(PACKAGE, "VideoToolbox")
    registry = os.path.join(PACKAGE, "registry", "VideoToolbox")
    problems = check(objects, registry)
    for problem in problems:
        print("FAIL " + problem)
    status = 1 if problems else 0
    if "--control" in sys.argv:
        status = status or control(objects, registry)
    print("check-constant-files: %s" % ("RED" if status else "OK"))
    return status


if __name__ == "__main__":
    sys.exit(main())
