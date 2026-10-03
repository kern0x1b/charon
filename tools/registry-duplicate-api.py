#!/usr/bin/env python3
"""Every `api` must appear once across a framework's registry files. The duplicate checker, written
because this tree had two.

A duplicate is invisible to `json.load`: an object keyed on `api` with two `api` lines keeps the last,
so a file can parse, parse as an object, and answer a question about a name whose status is written in
two places at once - which is what the gate's red line turned out to be.

    tools/registry-duplicate-api.py [registry-root]     the duplicates, one per line; exit 1 if any
"""
import collections
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from registry_rows import documents, rows as rows_of  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGISTRY = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "packages/a/apple-backports/registry")

seen = collections.defaultdict(list)
rows = 0
for path, document in documents(REGISTRY):
    for entry in rows_of(document):
        seen[entry.get("api")].append(os.path.basename(path))
        rows += 1
duplicates = {api: files for api, files in seen.items() if len(files) > 1}
for api, files in sorted(duplicates.items()):
    print("%-64s in %s" % (api, ", ".join(files)))
print("%d rows, %d distinct api, %d duplicated" % (rows, len(seen), len(duplicates)))
sys.exit(1 if duplicates else 0)
