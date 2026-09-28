#!/usr/bin/env python3
"""Check that every registry row leaves the bands at the release that has its API.

A row is carried from its `minimum` and drops out at its `maximum`: `in_range` in
modules/apple/backports.lua is `deployment >= minimum and deployment < maximum`. So the last band a row
belongs in is the one before `maximum`, and the band after that is the first in which the release has
the API -- which is `introduced`, the SDK's own availability. A `maximum` below `introduced` therefore
drops the row a band early, and the band it drops it in is the one band where the release does *not*
have the API and the port is the only source of it; and a `maximum` above `introduced` keeps it in a
band the release already answers for itself.

    tools/registry-maximum.py [registry-root]     exit 0 and a count, or exit 1 and the rows
"""
import collections
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGISTRY = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "packages/a/apple-backports/registry")


def version(text):
    return tuple(int(piece) for piece in text.split("."))


def main():
    rows = 0
    with_maximum = 0
    wrong = []
    for path in sorted(glob.glob(os.path.join(REGISTRY, "**", "*.json"), recursive=True)):
        document = json.load(open(path))
        entries = document["entries"] if isinstance(document, dict) else document
        for entry in entries:
            rows += 1
            maximum, introduced = entry.get("maximum"), entry.get("introduced")
            if not maximum or not introduced:
                continue
            with_maximum += 1
            if version(maximum) != version(introduced):
                wrong.append((entry.get("api"), maximum, introduced, os.path.basename(path)))
    for api, maximum, introduced, where in wrong:
        print("%-64s maximum %-8s introduced %-8s  %s" % (api, maximum, introduced, where))
    print("%d rows, %d with a maximum, %d not at the release that has the API"
          % (rows, with_maximum, len(wrong)))
    return 1 if wrong else 0


sys.exit(main())
