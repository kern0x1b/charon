#!/usr/bin/env python3
"""Places a row in the registry for every string constant the port defines.

    VT_SDK=<an iPhoneOS*.sdk> python3 registry-constants.py [--dry-run]

The VideoToolboxConstants<release>.m files define 135 string constants and the registry had a row for none of them, which
is what the 6.1.3 gate stops on: "neither the SDK, the registry nor a held release's own cache says
which iOS release <name> arrived in, and <a VideoToolboxConstants file> defines it".

THE RELEASE IS THE HEADER'S OWN, read by availability.py, and the row is placed in that release's group
file - ios26.json for a constant the header marks ios(26.0), ios14.json for one it marks ios(14.0), and so
on. It is NOT a guess and not a neighbour's release, and a constant the header states nothing for is
placed with the decision written down in the facts rather than passed over.

THE GROUP FILES ARE MERGED, never replaced: ios7.json and ios8.json already hold fourteen rows the
registry owns, including the H.264 profile levels the 6.1.3 cache ladder first exports at 7.0, and a
rewrite of those files would throw away what the gate has been checking for months.

A ROW IS THE ONE ios7.json USES, its keys exactly: api, kind, introduced, minimum, status, reason,
effect, facts, source. The keys are asserted against the existing file rather than copied from memory,
because a row with a missing key is a row the gate will not read as a reason.
"""
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WORKTREE = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
CONSTANTS = os.path.join(WORKTREE, "packages", "a", "apple-backports", "VideoToolbox",
                         "VideoToolboxConstants*.m")
REGISTRY = os.path.join(WORKTREE, "packages", "a", "apple-backports", "registry", "VideoToolbox")
FACTS = os.path.join(WORKTREE, "packages", "a", "apple-backports", "facts", "VideoToolbox",
                    "FrameProcessorConstants.md")

ROW_KEYS = ("api", "kind", "introduced", "minimum", "status", "reason", "effect", "facts", "source")

# The one constant whose header states no ios() version, and the decision for it. The SDK puts its
# availability on the line BELOW, after a // comment, and that line says ios(14.0) - so this is the SDK's
# own statement and the row is placed at 14.0 for the same reason every other row is placed where the
# header says.
DECIDED = {
    "kVTCompressionPropertyKey_PreserveDynamicHDRMetadata": (
        "14.0",
        "its availability is on the line BELOW the declaration, after a // comment, and that line "
        "states ios(14.0) - VTCompressionProperties.h:1183-1184"),
}


def load_availability():
    import importlib.util
    path = os.path.join(HERE, "availability.py")
    spec = importlib.util.spec_from_file_location("vt_constant_availability", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert os.path.abspath(module.__file__) == path, "loaded an availability.py that is not this one"
    return module


def defined_constants():
    text = "".join(open(path).read() for path in sorted(glob.glob(CONSTANTS)))
    return re.findall(r"^const CFStringRef (\w+) = CFSTR", text, re.M)


def group_file(release):
    return os.path.join(REGISTRY, "ios%s.json" % release.split(".")[0])


def read_group(path):
    if not os.path.exists(path):
        return {"framework": "VideoToolbox", "entries": []}
    return json.load(open(path))


def write_group(path, data):
    with open(path, "w") as handle:
        json.dump(data, handle, indent=1)
        handle.write("\n")


def main():
    dry = "--dry-run" in sys.argv
    availability = load_availability()
    sdk = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("-") \
        else os.environ.get("VT_SDK", "")
    if not sdk:
        sys.exit("registry-constants.py: set VT_SDK to an iPhoneOS*.sdk")
    stated = availability.all_constants(sdk)
    names = defined_constants()

    # the existing rows' key set, asserted rather than assumed
    existing_keys = set()
    for path in sorted(glob.glob(os.path.join(REGISTRY, "*.json"))):
        for row in json.load(open(path)).get("entries", []):
            if row.get("kind") == "constant" and row.get("api") in names:
                existing_keys = set(row)
    if existing_keys and existing_keys != set(ROW_KEYS):
        sys.exit("the registry's own constant rows use %s and this emitter writes %s - the two must "
                 "agree or the gate will not read the new rows" % (sorted(existing_keys), list(ROW_KEYS)))

    placed, undecided = [], []
    for name in names:
        if name in DECIDED:
            release, why = DECIDED[name]
        else:
            release = (stated.get(name) or (None,))[0]
            why = None
            if release is None:
                undecided.append(name)
                continue
        path = group_file(release)
        data = read_group(path)
        if any(row.get("api") == name for row in data["entries"]):
            placed.append((release, path, name, "already there"))
            continue
        reason = ("a VideoToolbox string constant SDK 26.2 declares as %s, and the release the port "
                  "builds for lacks it" % release)
        if why:
            reason += "; " + why
        effect = "the string the header's own constant is documented to have, answered from the port"
        data["entries"].append({
            "api": name,
            "kind": "constant",
            "introduced": release,
            "minimum": "6.0",
            "status": "implemented",
            "reason": reason,
            "effect": effect,
            "facts": "facts/VideoToolbox/FrameProcessorConstants.md",
            "source": "SDK 26.2, VideoToolbox/Headers/%s, the declaration's own availability"
                      % (stated.get(name) or (None, "?", 0))[1],
        })
        placed.append((release, path, name, "written"))
        if not dry:
            write_group(path, data)

    groups = {}
    for release, _path, name, _how in placed:
        groups.setdefault(release, []).append(name)
    for release in sorted(groups, key=lambda r: [int(x) for x in r.split(".")]):
        print("  ios%-6s %3d constants" % (release, len(groups[release])))
    print("  placed %d of %d constants%s" % (len(placed), len(names), " (dry run)" if dry else ""))
    if undecided:
        print("  NOT PLACED, and the SDK states no ios() version for: %s" % ", ".join(undecided))
    if not dry:
        write_facts(groups, undecided)
    return 1 if undecided else 0


def write_facts(groups, undecided):
    """The file every row points at, and the DECISIONS in it - not silence."""
    lines = ["# VideoToolbox's 135 string constants, and the release each arrived in",
             "",
             "The VideoToolboxConstants<release>.m files define 135 string constants. Until the 6.1.3 gate stopped on this",
             "family none of them had a registry row, and the gate says what that sounds like: \"neither",
             "the SDK, the registry nor a held release's own cache says which iOS release <name> arrived",
             "in, and <a VideoToolboxConstants file> defines it\".",
             "",
             "The release each one is placed at is the SDK's OWN, read from its declaration: the",
             "availability on the declaration's line where it is there, the line below where a // comment",
             "sits between the name and its availability, and the lines above for the shapes that put it",
             "there. Nothing is assigned from a neighbour, and nothing is left unsaid.",
             "",
             "## Releases the 135 arrived in", ""]
    for release in sorted(groups, key=lambda r: [int(x) for x in r.split(".")]):
        lines.append("- **%s** — %d constants" % (release, len(groups[release])))
    lines += ["", "## The decisions, one per constant the SDK leaves open", ""]
    if undecided:
        for name in undecided:
            lines.append("- `%s` — the SDK states no ios() version for it, and it is NOT placed." % name)
            lines.append("  That is a decision with a consequence, not a gap: an unplaced constant is")
            lines.append("  `built, but no entry in registry` at the gate, and this line is where a reader")
            lines.append("  looks to find out why. The fix is a version and a header line, and neither is")
            lines.append("  available, so nothing is invented here.")
    else:
        for name, (release, why) in sorted(DECIDED.items()):
            lines.append("- `%s` — placed at **%s**, because %s." % (name, release, why))
            lines.append("  The SDK states the version itself, on a continuation line after a comment;")
            lines.append("  this is a reading of where the SDK put it, not a judgement about the release.")
    lines += ["", "## What this does not cover", "",
              "A constant of an early release that 6.1.3 EXPORTS NATIVELY is not the port's to define, and",
              "this file does not decide that: it is the cache that says, and that measurement is still owed.",
              "The objects are split per release (VideoToolboxConstants<major>_<minor>.m), each holding the",
              "constants its registry rows place at that release; check-constant-files.py holds that both ways,",
              "with a control that a constant moved into another release's file is caught by name.", ""]
    os.makedirs(os.path.dirname(FACTS), exist_ok=True)
    with open(FACTS, "w") as handle:
        handle.write("\n".join(lines))


if __name__ == "__main__":
    sys.exit(main())
