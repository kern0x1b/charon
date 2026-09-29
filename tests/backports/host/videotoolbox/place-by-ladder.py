#!/usr/bin/env python3
"""Place VideoToolbox's string constants by the release the cache ladder measures, one object per release.

The gate decides which release an object's API arrived in from the held caches' own exports first (the way
tools/release-split.lua does), the registry second and the SDK last. The header's availability is the
release Apple wrote down; the ladder is the first held release that EXPORTS the symbol, which is what a band
of this port is cut by, and the two differ (a constant the header says arrived in 13.0 is first seen in the
16.0 cache because nothing is held between 12.0 and 16.0). So an object holding the header's 13.0 constants
was refused as holding API of 7.0, 8.0, 12.0 and 16.0.

    xmake l tools/release-split.lua <OBJECTSDIR of the built VideoToolbox objects> > split.txt
    python3 tests/backports/host/videotoolbox/place-by-ladder.py split.txt

For each of the 135 constants the target release is the earliest release the ladder gives it (the ladder
prints one per architecture: the smallest is taken, which is what the gate names); a constant no held cache
exports keeps the release its registry row already has. The registry row moves with it - `introduced`,
`source`, and the group file by major release - and each VideoToolboxConstants<release>.m holds exactly the
constants of its release. check-constant-files.py holds the result both ways.
"""
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WORKTREE = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
PACKAGE = os.path.join(WORKTREE, "packages", "a", "apple-backports")
OBJECTS = os.path.join(PACKAGE, "VideoToolbox")
REGISTRY = os.path.join(PACKAGE, "registry", "VideoToolbox")

IMPORTS = "#import <Foundation/Foundation.h>\n#import <CoreMedia/CoreMedia.h>\n#import <VideoToolbox/VideoToolbox.h>\n"


def key(release):
    return tuple(int(part) for part in release.split("."))


def measured(path):
    found = {}
    for line in open(path):
        parts = line.rstrip("\n").split("\t")
        if len(parts) != 3 or not parts[0].startswith("VideoToolboxConstants") or not parts[1].startswith("_kVT"):
            continue
        rungs = [r for r in parts[2].split(",") if r and r != "none"]
        if rungs:
            found[parts[1][1:]] = min(rungs, key=key)
    return found


def object_name(release):
    return "VideoToolboxConstants%s.m" % release.replace(".", "_")


def group_file(release):
    return os.path.join(REGISTRY, "ios%s.json" % release.split(".")[0])


def main():
    ladder = measured(sys.argv[1])
    lines, comment = {}, None
    for path in sorted(glob.glob(os.path.join(OBJECTS, "VideoToolboxConstants*.m"))):
        text = open(path).read()
        if "// The 135 string constants" in text:
            comment = text[text.index("// The 135 string constants"):text.index("\nconst CFStringRef")].rstrip("\n")
            comment = comment[:comment.index("\n\n// This file holds")] if "\n\n// This file holds" in comment else comment
        for line in text.split("\n"):
            match = re.match(r"const CFStringRef (\w+) =", line)
            if match:
                lines[match.group(1)] = line
    assert len(lines) == 135 and comment, "the split files do not hold the 135 constants and the comment"

    rows, where = {}, {}
    for path in sorted(glob.glob(os.path.join(REGISTRY, "*.json"))):
        for row in json.load(open(path)).get("entries", []):
            if row.get("kind") == "constant" and row["api"] in lines:
                rows[row["api"]] = row
                where[row["api"]] = path
    assert set(rows) == set(lines), "a defined constant has no row: %s" % sorted(set(lines) - set(rows))

    target = {name: ladder.get(name, rows[name]["introduced"]) for name in lines}
    moved = 0
    groups = {}
    for name, release in target.items():
        row = rows[name]
        if row["introduced"] != release:
            moved += 1
            header = row["introduced"]
            row["introduced"] = release
            row["source"] = ("the armv7 cache ladder (tools/release-split.lua), which first exports it at %s; "
                             "SDK 26.2, VideoToolbox/Headers, states %s" % (release, header))
        groups.setdefault(release, []).append(name)

    # the registry: every group file loses the rows it no longer holds and gains the ones it now does
    files = {}
    for path in glob.glob(os.path.join(REGISTRY, "*.json")):
        data = json.load(open(path))
        data["entries"] = [r for r in data["entries"] if not (r.get("kind") == "constant" and r["api"] in lines)]
        files[path] = data
    for name, row in rows.items():
        path = group_file(row["introduced"])
        files.setdefault(path, {"framework": "VideoToolbox", "entries": []})["entries"].append(row)
    for path, data in files.items():
        if not data["entries"]:
            os.remove(path)
            continue
        with open(path, "w") as handle:
            json.dump(data, handle, indent=1)
            handle.write("\n")

    # the objects: one per release, the comment in the earliest
    for path in glob.glob(os.path.join(OBJECTS, "VideoToolboxConstants*.m")):
        os.remove(path)
    first = min(groups, key=key)
    for release in sorted(groups, key=key):
        body = IMPORTS + "\n"
        if release == first:
            body += comment + "\n\n"
            body += ("// This file holds the constants of iOS %s; every other release's are in\n"
                     "// VideoToolboxConstants<release>.m, because an object carries the API of one release: the\n"
                     "// release the cache ladder measures for the symbol (place-by-ladder.py), and the registry's\n"
                     "// where no held cache exports it.\n\n" % release)
        else:
            body += ("// The string constants VideoToolbox's first held export of which is iOS %s. Where the values\n"
                     "// come from, and why a value is not the constant's own name: the head of\n"
                     "// %s. An object carries the API of one release.\n\n" % (release, object_name(first)))
        body += "\n".join(lines[n] for n in sorted(groups[release])) + "\n"
        open(os.path.join(OBJECTS, object_name(release)), "w").write(body)
    print("placed %d constants in %d objects, %d rows moved to the ladder's release" % (len(lines), len(groups), moved))
    for release in sorted(groups, key=key):
        print("  %-7s %3d" % (release, len(groups[release])))


if __name__ == "__main__":
    main()
