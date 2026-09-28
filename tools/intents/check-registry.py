#!/usr/bin/env python3
"""Does a regeneration of the Intents registry move anything but a reason?

The five counts are what the series has held since the first group — ios10 948, ios11 288,
ios12 100, ios16 465, ios18 17 — and N3 is a change of *reasons only*. This regenerates the
registry into a scratch folder and compares it with the committed one entry by entry: the same
files, the same names, the same kinds, the same statuses, the same introduced versions, and the
same set of fields apart from `reason` and `effect`. Anything else is a regression, and it is
reported by name rather than as a count.

    Usage: tools/intents/check-registry.py [--work <scratch>] [--counts-only]

Exit status is non-zero on any difference beyond a reason, and the difference is printed.
"""

import argparse
import json
import os
import subprocess
import sys

# What the series has held, and what a move of any count means.
EXPECTED = {
    "ios10.json": 948,
    "ios11.json": 288,
    "ios12.json": 100,
    "ios16.json": 465,
    "ios18.json": 17,
}

# The fields a reason-only change may touch. `effect` is the same sentence in a place a reader
# looks for it, and it is written from the same cause.
REASON_FIELDS = ("reason", "effect")

# **No status may move.** A member that was registered as implemented and should not have been
# is fixed by implementing it, and not by teaching this guard to accept the move: a guard widened
# for one's own change is not a guard. The two causes that once read "no body is the right answer"
# here - a factory that answers an array, and a class property - turned out to be implementable,
# and the bodies are in the generator now.
WITHDRAWN = ()


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.abspath(os.path.join(here, "..", ".."))
    parser.add_argument("--work", default="/tmp/intents-registry-check")
    parser.add_argument("--counts-only", action="store_true",
                        help="compare the counts and stop")
    options = parser.parse_args()

    committed = os.path.join(root, "packages", "a", "apple-backports", "registry", "Intents")
    scratch = os.path.join(options.work, "registry", "Intents")
    import shutil
    if os.path.isdir(scratch):
        shutil.rmtree(scratch)
    os.makedirs(scratch)
    # The committed files, kept beside the regenerated ones so the two are compared entry by entry.
    for name in os.listdir(committed):
        if name.endswith(".json"):
            shutil.copy(os.path.join(committed, name), os.path.join(scratch, name + ".committed"))
    result = subprocess.run(
        ["sh", os.path.join(here, "generate.sh")],
        env=dict(os.environ, WORK=options.work, REGISTRY_OUT=scratch),
        capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stdout[-2000:])
        print(result.stderr[-2000:])
        print("FAIL: the regeneration did not complete")
        return 1

    failures = []
    for name, expected in sorted(EXPECTED.items()):
        fresh_path = os.path.join(scratch, name)
        if not os.path.isfile(fresh_path):
            failures.append("%s was not written" % name)
            continue
        fresh = json.load(open(fresh_path))["entries"]
        if len(fresh) != expected:
            failures.append("%s has %d entries, the series holds %d" % (name, len(fresh), expected))
        if options.counts_only:
            continue
        was = json.load(open(os.path.join(scratch, name + ".committed")))["entries"]
        was_by = {e["api"]: e for e in was}
        fresh_by = {e["api"]: e for e in fresh}
        for api in sorted(set(was_by) | set(fresh_by)):
            before, after = was_by.get(api), fresh_by.get(api)
            if before is None:
                failures.append("%s: %s is new" % (name, api))
                continue
            if after is None:
                failures.append("%s: %s is gone" % (name, api))
                continue
            for field in sorted(set(before) | set(after)):
                if before.get(field) == after.get(field):
                    continue
                if field in REASON_FIELDS:
                    continue
                failures.append("%s: %s moved its %s" % (name, api, field))
    for failure in failures:
        print("FAIL: " + failure)
    if not failures:
        print("check-registry: %s hold, and only a reason moved"
              % ", ".join("%s %d" % pair for pair in sorted(EXPECTED.items())))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
