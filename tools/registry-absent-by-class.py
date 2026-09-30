#!/usr/bin/env python3
"""The absent Foundation rows, counted by class - the family inventory, from the registry itself.

    tools/registry-absent-by-class.py [framework]      the counts; exit 1 if a class holds none

Every Foundation row that still says `absent`, grouped by the class or protocol that owns it. The
count is the one a slice is cut from, so it is computed here rather than written into a facts file by
hand, and the row each number rests on is named.
"""
import collections
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGISTRY = os.path.join(ROOT, "packages/a/apple-backports/registry")
FRAMEWORK = sys.argv[1] if len(sys.argv) > 1 else "Foundation"


def owner(api):
    method = re.match(r"^[-+]\[([A-Za-z0-9_]+) ", api)
    if method:
        return method.group(1)
    return api.split(".")[0] if "." in api else api


def main():
    groups = collections.defaultdict(list)
    for path in sorted(glob.glob(os.path.join(REGISTRY, FRAMEWORK, "*.json"))):
        document = json.load(open(path))
        entries = document["entries"] if isinstance(document, dict) else document
        for entry in entries:
            if entry.get("status") == "absent":
                groups[owner(entry["api"])].append((entry["api"], os.path.basename(path)))
    for name in sorted(groups, key=lambda k: (-len(groups[k]), k)):
        print("%3d  %-40s %s" % (len(groups[name]), name, groups[name][0][1]))
    print("%d absent %s row(s) over %d class group(s)"
          % (sum(len(v) for v in groups.values()), FRAMEWORK, len(groups)))
    return 1 if not groups else 0


sys.exit(main())
