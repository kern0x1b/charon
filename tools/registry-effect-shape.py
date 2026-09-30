#!/usr/bin/env python3
"""Rows whose `status` and whose `effect` contradict each other: implemented, but the effect answers
that the name is not there.

The effect is prose, so the words alone do not decide: eleven of the thirteen the sweep found are
honest - "the network is not there", "NSNotFound for a section that is not there" - and two answer
only for a band the row does not cover. This prints every row whose status and effect disagree, with
its file, so the list is the evidence rather than a claim.

    tools/registry-effect-shape.py [registry-root]     the rows; exit 1 if any
"""
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGISTRY = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "packages/a/apple-backports/registry")
PHRASES = ("is not there", "unchecked call raises", "answers honestly")

rows = []
for path in sorted(glob.glob(os.path.join(REGISTRY, "**", "*.json"), recursive=True)):
    document = json.load(open(path))
    entries = document["entries"] if isinstance(document, dict) else document
    for entry in entries:
        if entry.get("status") != "implemented":
            continue
        effect = entry.get("effect") or ""
        if any(phrase in effect for phrase in PHRASES):
            rows.append((entry["api"], os.path.basename(path), effect))
for api, where, effect in rows:
    print("%-58s %-20s %s" % (api[:58], where, effect[:72]))
print("%d implemented row(s) whose effect contains %s" % (len(rows), ", ".join(PHRASES)))
sys.exit(1 if rows else 0)
