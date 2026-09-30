#!/usr/bin/env python3
"""Every `api` must appear once across a framework's registry files. The duplicate checker, written
because this tree had two.

A duplicate is invisible to `json.load`: an object keyed on `api` with two `api` lines keeps the last,
so a file can parse, parse as an object, and answer a question about a name whose status is written in
two places at once - which is what the gate's red line turned out to be.

    tools/registry-duplicate-api.py [registry-root]     the duplicates, one per line; exit 1 if any
"""
import collections
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGISTRY = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "packages/a/apple-backports/registry")

seen = collections.defaultdict(list)
rows = 0
for path in sorted(glob.glob(os.path.join(REGISTRY, "*.json")) + glob.glob(os.path.join(REGISTRY, "*", "*.json"))):
    document = json.load(open(path))
    entries = (document["entries"] if isinstance(document, dict) and isinstance(document.get("entries"), list)
                  else (document if isinstance(document, list) else None))
    for entry in entries:
        seen[entry.get("api")].append(os.path.basename(path))
        rows += 1
duplicates = {api: files for api, files in seen.items() if len(files) > 1}
for api, files in sorted(duplicates.items()):
    print("%-64s in %s" % (api, ", ".join(files)))
print("%d rows, %d distinct api, %d duplicated" % (rows, len(seen), len(duplicates)))
sys.exit(1 if duplicates else 0)
