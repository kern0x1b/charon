#!/usr/bin/env python3
"""Write tests/backports/host/intents-init/init-classes.inc, the population that harness measures.

Two derivations, and the file's own header says which is which because the claim under test is the
registry's:

  the class list, from the registry - every status `implemented` row that names `-[<class> init]`.
  A row the registry carries and this file does not is a claim no run of the harness can reach,
  and it is the one failure the harness's own guard cannot see: run.sh compares this file against
  expected.txt, and both are written from here, so a class missing from both agrees with itself.
  INListCarsIntent was exactly that - a row added when its body moved into the generator's
  EXTRA_METHODS, and neither file was regenerated, so 110 of the 111 implemented -init rows were
  being measured.  That is why the count is printed against the REGISTRY's and not only this file's.

  the properties, from the port's own objects - the `@synthesize NAME = _NAME;` lines inside each
  class's @implementation.  Read from the port and not from the runtime, because those are the ones
  the row claims stay nil: asking the runtime instead yields NSObject's hash/description/
  debugDescription/superclass repeated four times over plus the framework's private accessors -
  measured, 48 properties for INActivateCarSignalIntentResponse - which is neither the population the
  claim is about nor safe to call.

Usage:
    python3 tools/intents/gen-init-classes.py            # print the file to stdout
    python3 tools/intents/gen-init-classes.py -o PATH    # write it there
"""
import argparse
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
REGISTRY = os.path.join(ROOT, "packages", "a", "apple-backports", "registry", "Intents")
CLASSES = os.path.join(ROOT, "packages", "a", "apple-backports", "Intents")
OUT = os.path.join(ROOT, "tests", "backports", "host", "intents-init", "init-classes.inc")

# The object files the properties are read out of. IN*.m is the generated per-group body, and the
# two Charon* files are the hand-written base classes of the 10.0 and 11.0 slices.
SOURCES = sorted(glob.glob(os.path.join(CLASSES, "IN*.m")) +
                 [os.path.join(CLASSES, "CharonIntents100.m"),
                  os.path.join(CLASSES, "CharonIntents110.m")])

INIT_ROW = re.compile(r"^-\[(\w+) init\]$")
IMPLEMENTATION = re.compile(r"^@implementation\s+(\w+)\s*$")
SYNTHESIZE = re.compile(r"^\s*@synthesize\s+(\w+)\s*=\s*_(\w+)\s*;")

HEADER = """\
// init-classes.inc - the class population this harness keeps honest, with the properties the port
// synthesizes for each. Generated; the two derivations are:
//
//   the class list, from the registry - every status `implemented` row that names `-[<class> init]`:
//
//     python3 - <<'EOF'
//     import re, glob, json
//     for f in sorted(glob.glob('packages/a/apple-backports/registry/Intents/ios*.json')):
//         for x in json.load(open(f))['entries']:
//             m = re.match(r'^-\\[(\\w+) init\\]$', x['api'])
//             if m and x['status'] == 'implemented':
//                 print(m.group(1))
//     EOF
//     | sort -u
//
//   the properties, from the port's own objects - the `@synthesize NAME = _NAME;` lines inside
//   each class's @implementation in packages/a/apple-backports/Intents/IN*.m, CharonIntents100.m
//   and CharonIntents110.m:
//
//     python3 tools/intents/gen-init-classes.py     <- writes this file
//
// The class list is read from the registry and not from the SDK headers, because the claim under
// test is the registry's: the header says which classes mark -init NS_UNAVAILABLE, the registry
// says which rows claim the port answers one, and this harness measures the second.
//
// The properties are read from the port and not from the runtime, because those are the ones the
// row claims stay nil. Asking the runtime instead yields NSObject's hash/description/debugDescription/
// superclass repeated four times over plus the framework's private accessors - measured, 48
// properties for INActivateCarSignalIntentResponse - which is neither the population the claim is
// about nor safe to call. A class that synthesizes nothing is listed with an empty set and its
// -init is measured on the IMP and the call alone.
//
// A class added to the registry and not here is invisible to the harness. run.sh prints the
// registry's own count of these rows beside this file's, and fails when the two disagree, which is
// what keeps this file honest: both this file and expected.txt are written from here, so comparing
// them with each other would only show that they agree.
"""


def registry_classes():
    names = set()
    for path in sorted(glob.glob(os.path.join(REGISTRY, "ios*.json"))):
        document = json.load(open(path, encoding="utf-8"))
        for entry in document["entries"] if isinstance(document, dict) else document:
            if entry.get("status") != "implemented":
                continue
            match = INIT_ROW.match(entry["api"])
            if match:
                names.add(match.group(1))
    return names


def synthesised():
    """The properties the port's own objects declare, by class."""
    properties = {}
    owner = None
    for path in SOURCES:
        if not os.path.isfile(path):
            continue
        for line in open(path, encoding="utf-8"):
            implementation = IMPLEMENTATION.match(line)
            if implementation:
                owner = implementation.group(1)
                continue
            synthesize = SYNTHESIZE.match(line)
            if synthesize and owner:
                properties.setdefault(owner, set()).add(synthesize.group(1))
    return properties


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-o", "--out", default="-")
    options = parser.parse_args()
    names = registry_classes()
    properties = synthesised()
    empty = sorted(name for name in names if not properties.get(name))
    lines = [HEADER.rstrip("\n")]
    lines.append("//")
    lines.append("// %d classes, %d of which synthesize no property: %s"
                 % (len(names), len(empty), ", ".join(empty)))
    lines.append("")
    for name in sorted(names):
        held = sorted(properties.get(name, ()))
        lines.append('    { "%s", { %sNULL } },'
                     % (name, "".join('"%s", ' % one for one in held)))
    text = "\n".join(lines) + "\n"
    if options.out == "-":
        sys.stdout.write(text)
        return
    with open(options.out, "w", encoding="utf-8") as handle:
        handle.write(text)
    print("init-classes.inc: %d classes, %d with no property" % (len(names), len(empty)))


main()