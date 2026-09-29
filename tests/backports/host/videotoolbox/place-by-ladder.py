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

For each constant the target release is the earliest release the ladder gives it (the ladder
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


def ladder_table(path=None):
    """The committed table as {name: release}, read rather than restated: a count written into this file
    stops meaning anything the moment a real one changes, and it has - the ruling added twelve the port
    owed and was true the day before."""
    found = {}
    for path in [path or TABLE]:
        for line in open(path):
            if line.startswith("#") or not line.strip():
                continue
            name, _, release = line.rstrip("\n").partition("\t")
            if name:
                found[name] = release.strip()
    return found


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


TABLE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ladder.tsv")


def measured_from_table(path=TABLE):
    """The COMMITTED ladder table, so the placement is reproducible without a gate run and without
    xmake. constant<TAB>release, the smallest held-cache rung that EXPORTS it.

    A CONSTANT NO HELD CACHE EXPORTS IS OMITTED, not recorded with an empty release. Those 41 are placed
    from the registry's own release, and that happens through ladder.get(name, rows[name]["introduced"])
    - which falls back only when the key is ABSENT. An empty value is present, so it did not: the
    release became "", key("") raised, and the object-removal loop had already run by then.
    """
    found = {}
    for line in open(path):
        if line.startswith("#") or not line.strip():
            continue
        name, _, release = line.rstrip("\n").partition("\t")
        if name and release.strip() not in ("", "-"):
            found[name] = release.strip()
    return found


def check_against(split):
    """The committed table against a FRESH split file, so a re-measurement that says something
    different is a difference somebody can see rather than a placement that changes silently."""
    fresh = measured(split)
    committed = measured_from_table()
    added = sorted(set(fresh) - set(committed))
    gone = sorted(set(committed) - set(fresh))
    moved = sorted(n for n in set(fresh) & set(committed) if fresh[n] != committed[n])
    for name in gone:
        print("  GONE from the split: %s" % name)
    for name in added:
        print("  NEW in the split: %s -> %s" % (name, fresh[name] or "(no held cache exports it)"))
    for name in moved:
        print("  MOVED: %s %s -> %s" % (name, committed[name] or "(none)", fresh[name] or "(none)"))
    if not (added or gone or moved):
        print("  the committed table equals the split file, %d constants" % len(fresh))
        return 0
    print("FAIL the split and the committed table disagree: %d new, %d gone, %d moved"
          % (len(added), len(gone), len(moved)))
    return 1


def main():
    if "--check" in sys.argv:
        split = sys.argv[sys.argv.index("--check") + 1]
        sys.exit(check_against(split))
    if len(sys.argv) > 1:
        ladder = measured(sys.argv[1])
    else:
        ladder = measured_from_table()
    place(ladder, OBJECTS, REGISTRY)


def place(ladder, objects, registry):
    """Place the constants: read them and the comment from `objects`, write the objects and the
    registry rows for them.

    THE DIRECTORIES ARE PARAMETERS so a check can drive this function over a scratch tree. This is the
    only writer of the constant rows and of the objects, and a check that re-implemented it would be
    checking itself - which is how the header-based placer came to disagree with the ladder at all.

    ONE PASS, AND THE WHOLE LAYOUT IS BUILT AND VALIDATED BEFORE ANYTHING IS WRITTEN OR REMOVED. The
    order used to be: remove all eight objects, then build the new ones, so a release that was not a
    release raised key("") halfway through and left the package with no constants in it. Every release
    is now checked against the shape of a release first, and nothing moves until every write is ready.
    """
    global OBJECTS, REGISTRY
    OBJECTS, REGISTRY = objects, registry
    lines, comment = {}, None
    for path in sorted(glob.glob(os.path.join(objects, "VideoToolboxConstants*.m"))):
        text = open(path).read()
        if "// The string constants" in text:
            comment = text[text.index("// The string constants"):text.index("\nconst CFStringRef")].rstrip("\n")
            comment = comment[:comment.index("\n\n// This file holds")] if "\n\n// This file holds" in comment else comment
        for line in text.split("\n"):
            match = re.match(r"const CFStringRef (\w+) =", line)
            if match:
                lines[match.group(1)] = line
    table_all = set(ladder_table())
    assert set(lines) == table_all, (
        "the objects define %d constants and the table measures %d; the difference is %s"
        % (len(lines), len(table_all), sorted(set(lines) ^ table_all)[:5]))
    assert comment, "the objects carry no comment to put in the earliest one"

    rows = {}
    for path in sorted(glob.glob(os.path.join(registry, "*.json"))):
        for row in json.load(open(path)).get("entries", []):
            if row.get("kind") == "constant" and row["api"] in lines:
                rows[row["api"]] = row
    assert set(rows) == set(lines), "a defined constant has no row: %s" % sorted(set(lines) - set(rows))

    # THE LAYOUT, first and whole: every constant to a release, each release VALIDATED, and the
    # registry's rows updated in memory. Nothing on disk has moved yet, and nothing will until every
    # write below is ready.
    groups, first, moved = {}, None, 0
    for name in sorted(lines):
        release = ladder.get(name) or rows[name]["introduced"]
        assert re.fullmatch(r"\d+(\.\d+)*", release), (
            "%s would be placed at %r, which is not a release: the ladder says %r and the registry row "
            "says %r" % (name, release, ladder.get(name), rows[name]["introduced"]))
        row = rows[name]
        if row["introduced"] != release:
            moved += 1
            header = row["introduced"]
            row["introduced"] = release
            row["source"] = ("the armv7 cache ladder (tools/release-split.lua), which first exports it at %s; "
                             "SDK 26.2, VideoToolbox/Headers, states %s" % (release, header))
        groups.setdefault(release, []).append(name)
        first = release if first is None or key(release) < key(first) else first
    # derived again: the layout must place every constant the table measures, and no others
    assert sum(len(v) for v in groups.values()) == len(table_all), (
        "the layout places %d constants and the table measures %d"
        % (sum(len(v) for v in groups.values()), len(table_all)))

    # THE REGISTRY, built in memory
    files = {}
    for path in glob.glob(os.path.join(registry, "*.json")):
        data = json.load(open(path))
        data["entries"] = [r for r in data["entries"] if not (r.get("kind") == "constant" and r["api"] in lines)]
        files[path] = data
    for name in rows:
        path = os.path.join(registry, "ios%s.json" % rows[name]["introduced"].split(".")[0])
        files.setdefault(path, {"framework": "VideoToolbox", "entries": []})["entries"].append(rows[name])

    # THE OBJECTS, built in memory. The comment text is the one the committed objects carry, verbatim:
    # a placer that rewrites the prose as well as the layout is a placer that cannot be run for its
    # check without changing the tree it is checking.
    bodies = {}
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
        bodies[object_name(release)] = body + "\n".join(lines[n] for n in sorted(groups[release])) + "\n"

    # AND ONLY NOW does anything move
    for path in glob.glob(os.path.join(objects, "VideoToolboxConstants*.m")):
        if os.path.basename(path) not in bodies:
            os.remove(path)
    for path, data in files.items():
        if not data["entries"]:
            os.remove(path)
            continue
        with open(path, "w") as handle:
            json.dump(data, handle, indent=1)
            handle.write("\n")
    for name, body in bodies.items():
        open(os.path.join(objects, name), "w").write(body)
    print("placed %d constants in %d objects, %d rows moved to the ladder's release" % (len(lines), len(groups), moved))
    for release in sorted(groups, key=key):
        print("  %-7s %3d" % (release, len(groups[release])))


if __name__ == "__main__":
    main()
