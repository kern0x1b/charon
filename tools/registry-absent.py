#!/usr/bin/env python3
"""Count the registry's rows by status, per framework, and name the ones that are still absent.

    tools/registry-absent.py [registry-root]     a table, and the absent rows; exit 1 if no row

The count a report quotes has to come from a run somebody can repeat, and "131 absent Foundation
rows, 116 remain" does not: it was read off a corpus export of an older tip, and the export's
framework column is empty for every file whose JSON carries no `framework` key, so counting by
framework there silently drops rows. This counts the registry files themselves, by path, which is
where a framework's rows live.

A path with no registry under it prints nothing and says so, and exits 1: a count that examined
nothing is not a count.
"""
import collections
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGISTRY = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "packages/a/apple-backports/registry")


def framework_of(path):
    # registry/<Framework>.json and registry/<Framework>/<part>.json are the two shapes the
    # registry's own README gives; the key inside the file is not consulted, because five files
    # under registry/AVFoundation/ name AVFAudio and the path is what a reader counts.
    relative = os.path.relpath(path, REGISTRY)
    head = relative.split(os.sep)[0]
    return head[:-len(".json")] if head.endswith(".json") else head


def main():
    by_framework = collections.Counter()
    absent = collections.defaultdict(list)
    rows = 0
    for path in sorted(glob.glob(os.path.join(REGISTRY, "**", "*.json"), recursive=True)):
        document = json.load(open(path))
        entries = document["entries"] if isinstance(document, dict) else document
        framework = framework_of(path)
        for entry in entries:
            rows += 1
            by_framework[(framework, entry.get("status"))] += 1
            if entry.get("status") == "absent":
                absent[framework].append(entry.get("api"))
    if rows == 0:
        print("no registry row under %s: nothing was counted, so nothing is claimed" % REGISTRY)
        return 1
    frameworks = sorted({framework for framework, _ in by_framework})
    statuses = sorted({status for _, status in by_framework})
    print("%-26s %s %8s" % ("framework", " ".join("%-11s" % s for s in statuses), "absent"))
    for framework in frameworks:
        counts = [by_framework.get((framework, status), 0) for status in statuses]
        print("%-26s %s %8d" % (framework, " ".join("%-11d" % c for c in counts), len(absent[framework])))
    print("%d rows, %d absent, over %d frameworks"
          % (rows, sum(len(v) for v in absent.values()), len(frameworks)))
    return 0


sys.exit(main())
