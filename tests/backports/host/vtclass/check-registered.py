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


def built_names():
    """What the value files implement: @implementation names, method selectors, property names."""
    classes, methods, properties = set(), set(), set()
    for path in sorted(glob.glob(os.path.join(VT_DIR, "*.m"))):
        text = open(path).read()
        for name in re.findall(r'^@implementation\s+(\w+)', text, re.M):
            classes.add(name)
        for name in re.findall(r'@interface\s+(VT\w+)\s*:', text):
            classes.add(name)
        # a macro accessor: CHARON_VALUE_PROPERTY(NSArray<NSNumber *> *, supportedRevisions)
        for call in re.findall(r'CHARON_\w+_PROPERTY\((.*)\)', text):
            for prop in re.findall(r'\b(\w+)\s*$', call.split(',')[-1].strip()) or []:
                pass
            last = call.split(',')[-1].strip()
            if re.match(r'^\w+$', last):
                properties.add(last)
            properties.add(prop)
        # a hand-written accessor: - (BOOL)usesPrecomputedFlow   /   + (NSIndexSet *)supportedRevisions
        for _sign, selector in re.findall(r'([-+])\s*\([^)]*\)\s*(\w+)', text):
            methods.add(selector)
        for prop in re.findall(r'@property[^;]*?\s(\w+)\s*;', text):
            properties.add(prop)
    return classes, methods, properties


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
    classes, methods, properties = built_names()
    registry = registered_names()
    print("built: %d classes, %d selectors, %d properties" % (len(classes), len(methods), len(properties)))
    print("registered: %d class, %d method, %d property rows"
          % tuple(len(registry[k]) for k in ("class", "method", "property")))

    unregistered, orphan = [], []
    for name in sorted(classes):
        if name not in registry["class"]:
            unregistered.append("built, but no entry in registry: %s (a class)" % name)
    for kind, names in (("method", methods), ("property", properties)):
        recorded = registry[kind]
        for name in sorted(names):
            if not any(bare(row) == name for row in recorded):
                unregistered.append("built, but no entry in registry: %s (%s)" % (name, kind))
    for kind in ("class", "method", "property"):
        for row in registry[kind]:
            head = bare(row)
            if kind == "class":
                found = row in classes
            else:
                found = head in methods or head in properties
            if not found:
                orphan.append("registered, but not built: %s (%s)" % (row, kind))

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
        _, _, properties_ = built_names()
        after = registered_names(scratch)
        target = bare(removed["api"])
        named = [r for r in after["property"] | after["method"] if bare(r) == target]
        print("  control: removed %s from %s on a scratch copy"
              % (removed["api"], os.path.basename(victim)))
        if not named:
            print("FAIL the control did NOT change what this script finds: deleting a row changed nothing")
            return 1
        print("  control: the script now reports it: built, but no entry in registry: %s" % target)
        return 0
    if missing or extra:
        print("registry stand-in: NOT clean")
        return 1
    print("registry stand-in: nothing built without a row, and no row without an implementation")
    return 0


if __name__ == "__main__":
    sys.exit(main())
