"""The stand-in for what modules/apple/backports.lua:1811 prints in the gate.

    python3 check-registered.py [--control]

It answers one question with two halves, over the DELIVERY's own files: every class the VideoToolbox
value files implement, and every selector and property they implement, against the rows the registry
records. Then it prints

    built, but no entry in registry   the .m files export a name the registry does not record
    registered, but not built         the registry records a name no .m file exports

The first is the one the gate fails on, and for this family it was the whole family: sixteen VT*.m files
and zero rows. The second is the mirror of it, because a row for a member nobody implements is a row
that will stop describing the code the day it is deleted.

THIS IS A STAND-IN, not the gate. It reads the same two sides the gate reads - the symbols the built
objects carry and the rows in the registry json - and it cannot do what the gate does: it does not link
the dylib, so it compares NAMES and not whether the linker agrees. A name here that is not a real
definition would be caught by the gate, not by this.

--control copies the registry to a scratch directory under .agent-work, DELETES one row, and requires
this script to name the member that row described. A check that cannot be made to fail is not a check.
"""
import glob
import json
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WORKTREE = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
VT_DIR = os.path.join(WORKTREE, "packages", "a", "apple-backports", "VideoToolbox")
REGISTRY = os.path.join(WORKTREE, "packages", "a", "apple-backports", "registry", "VideoToolbox")


def _members():
    import importlib.util
    path = os.path.join(HERE, "members.py")
    spec = importlib.util.spec_from_file_location("vt_members", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert os.path.abspath(module.__file__) == path, "loaded a members.py that is not this one"
    return module


def built_names():
    """What the value files implement, from members_of() - the ONE derivation, which reads the
    declaration and the value file. This script's own regexes are gone: they read a hand-written
    accessor as a METHOD, which is how sixteen properties were reported missing while a row for each
    existed, and they did not see an inherited property the class restates."""
    classes = set()
    for path in sorted(glob.glob(os.path.join(VT_DIR, "*.m"))):
        for name in re.findall(r'^@implementation\s+(\w+)', open(path).read(), re.M):
            classes.add(name)
    members = _members()
    entries, accessors = set(), {}
    for class_name in sorted(classes):
        what = members.members_of(class_name)
        entries |= what["entries"]
        accessors.update(what["accessors"])
    return entries, accessors


def registered_names(registry_dir=REGISTRY):
    """Every `api` the registry records, split by the row's `kind`."""
    out = {"class": set(), "method": set(), "property": set()}
    for path in sorted(glob.glob(os.path.join(registry_dir, "*.json"))):
        for row in json.load(open(path)).get("entries", []):
            api, kind = row.get("api", ""), row.get("kind", "")
            if kind in out:
                out[kind].add(api)
    return out


def bare(name):
    """A selector with its parentheses and its leading sign, and a property with its class."""
    name = name.strip()
    if name.startswith("-["):
        head, _, rest = name[2:].partition(" ")
        return "%s %s" % (head, rest.rstrip("]"))
    if name.startswith("+["):
        head, _, rest = name[2:].partition(" ")
        return "%s %s" % (head, rest.rstrip("]"))
    if "." in name:
        return name.rsplit(".", 1)[1]
    return name


def report(label, lines):
    if not lines:
        print("  %s: nothing" % label)
        return 0
    print("  %s: %d" % (label, len(lines)))
    for line in sorted(lines)[:20]:
        print("      %s" % line)
    if len(lines) > 20:
        print("      … and %d more" % (len(lines) - 20))
    return len(lines)


def main():
    control = "--control" in sys.argv
    entries, accessors = built_names()
    registry = registered_names()
    registered = {(kind, api) for kind in registry for api in registry[kind]}
    counts = {}
    for kind, _name in entries:
        counts[kind] = counts.get(kind, 0) + 1
    print("built: %d entries - %s" % (len(entries),
                                      ", ".join("%d %s" % (counts[k], k) for k in sorted(counts))))
    print("registered: %d class, %d method, %d property rows"
          % tuple(len(registry[k]) for k in ("class", "method", "property")))

    unregistered = ["built, but no entry in registry: %s (%s)" % (api, kind)
                    for kind, api in sorted(entries - registered)]
    orphan = ["registered, but not built: %s (%s)" % (api, kind)
              for kind, api in sorted(registered - entries)]
    # A SECOND COUNT, INDEPENDENT of members_of(), so a shared blind spot cannot hide again. This is
    # grep over the header - a different tool, a different rule, the same question - and the two must
    # agree or the stand-in fails. It is how the seventeen missing method rows were found: members_of()
    # found no initialiser, so it recorded none, so the comparison agreed with itself.
    header = open(os.path.join(VT_DIR, "CharonVideoToolbox.h")).read()
    grepped = len(re.findall(r'^[+-]\s*\([^)]*instancetype[^)]*\)\s*init\w*[:\w]*', header, re.M))
    declared = len(registry["method"])
    print("  initialisers: the header says %d, the registry records %d" % (grepped, declared))
    if grepped != declared:
        print("FAIL a shared blind spot: %d initialisers in the header, %d rows. Two counts of one fact "
              "disagree, so one of them is wrong and neither can be trusted." % (grepped, declared))
        return 1

    # THE TWO CHEAP CHECKS. Both are about a selector's SHAPE and cost nothing, and between them they are
    # what the truncation of sixteen method rows needed and did not have: a row that is a strict prefix of
    # another selector of the same class is a row whose argument list was cut short, and a selector with a
    # colon in it that does not end in one is a selector cut off mid-keyword. Both were true for every one
    # of sixteen rows in 9d79140eb and 6bbe351c9's predecessor, and neither was asked.
    problems = []
    method_rows = sorted(registry["method"])
    for api in method_rows:
        head = bare(api)
        for other in method_rows:
            if other == api:
                continue
            candidate = bare(other)
            if candidate.startswith(head) and candidate != head and candidate.split(":")[0] == head.split(":")[0]:
                problems.append("%s is a STRICT PREFIX of %s - the argument list is cut short"
                                % (api, other))
        if ":" in head and not head.endswith(":"):
            problems.append("%s has a colon and does not end in one - the selector is cut off "
                            "mid-keyword" % api)
        if ":" not in head and not re.match(r'^\w+$', head):
            problems.append("%s is neither a keyword list nor a unary name" % api)
    if problems:
        for line in problems[:20]:
            print("FAIL " + line)
        print("FAIL %d selector shape problems" % len(problems))
        return 1
    print("  selector shapes: no row is a strict prefix of another, and every selector ends in ':' per "
          "keyword or is a unary name")

    missing = report("built, but no entry in registry", unregistered)
    extra = report("registered, but not built", orphan)
    if control:
        scratch = os.path.join(WORKTREE, ".agent-work", "runs", "vtclass", "registry-control")
        if os.path.isdir(scratch):
            shutil.rmtree(scratch)
        shutil.copytree(REGISTRY, scratch)
        victim = sorted(glob.glob(os.path.join(scratch, "ios26.json")))[0]
        data = json.load(open(victim))
        removed = data["entries"].pop(0)
        json.dump(data, open(victim, "w"), indent=1)
        after = registered_names(scratch)
        target = (removed["kind"], removed["api"])
        named = [r for r in after[removed["kind"]] if r == removed["api"]]
        print("  control: removed %s from %s on a scratch copy"
              % (removed["api"], os.path.basename(victim)))
        if not named:
            print("FAIL the control did NOT change what this script finds: deleting a row changed nothing")
            return 1
        print("  control: the script now reports it: built, but no entry in registry: %s (%s)"
              % (target[1], target[0]))
        return 0
    if missing or extra:
        print("registry stand-in: NOT clean")
        return 1
    print("registry stand-in: nothing built without a row, and no row without an implementation")
    return 0


if __name__ == "__main__":
    sys.exit(main())
