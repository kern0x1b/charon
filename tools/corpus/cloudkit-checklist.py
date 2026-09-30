#!/usr/bin/env python3
"""checklist.py - the 72 CloudKit names the sweep lists, and where each of them stands.

The list is read from `charon/.agent-work/runs/sweep/3d90-api-by-framework.tsv` - the sweep measured
that the old `tail-a-consts` branch carried 72 CloudKit class/type API names that main does not have -
and not from memory. The file's SELECTOR-FRAGMENTS rows are ignored, in the file's own words: "not API: a
bare selector tail with no class, which cannot be classified".

A name is CARRIED when a registry row in this repository names it AND a source file here defines it. A
name that is only one of those is a defect and the script exits non-zero. A name that is neither is owed,
and the six commits that owe it are transport, container/database, operations, sharing, sync engine and
record - each of which must end with the name either carried or listed as excluded with a reason.
"""
import csv
import json
import os
import re
import sys

# The sweep's file, found beside the repository rather than written down: a home path in a tracked file is
# refused by the commit hook, and rightly - the tool moves with the machine.
SWEEP = os.environ.get("SWEEP_TSV") or os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.dirname(os.path.abspath(__file__))))),
    "charon", ".agent-work", "runs", "sweep", "3d90-api-by-framework.tsv")
REG = "packages/a/apple-backports/registry/CloudKit"
SRC = "packages/a/apple-backports/CloudKit"

# which of the six owes a name, from the headers' own subject matter
OWED_BY = {
    "CKContainer": "container", "CKDatabaseNotification": "container", "CKDatabaseOperation": "container",
    "CKSyncEngine": "sync-engine",
}
GROUPS = ("value", "transport", "container", "operations", "sharing", "sync-engine", "record")


def checklist():
    rows = list(csv.DictReader(open(SWEEP, newline=""), delimiter="\t"))
    cloudkit = [r for r in rows if r["framework"] == "CloudKit"]
    if not cloudkit:
        raise SystemExit("checklist.py: the sweep file has no CloudKit row: %s" % SWEEP)
    names = [n.strip() for n in cloudkit[0]["sample"].split(";") if n.strip()]
    ignored = [r for r in rows if r["framework"] == "SELECTOR-FRAGMENTS"]
    return names, ignored


def carried():
    out = {}
    if not os.path.isdir(REG):
        return out
    for name in sorted(os.listdir(REG)):
        if not name.endswith(".json"):
            continue
        data = json.load(open(os.path.join(REG, name)))
        for row in (data["entries"] if isinstance(data, dict) else data):
            api = row["api"]
            base = api[2:].split(" ")[0] if api[:2] in ("+[", "-[") else api.split("(")[0].strip("+-[]")
            out.setdefault(base, name)
    return out


def defined():
    out = {}
    if not os.path.isdir(SRC):
        return out
    for name in sorted(os.listdir(SRC)):
        if not name.endswith((".m", ".h")):
            continue
        text = re.sub(r"//[^\n]*", "", open(os.path.join(SRC, name), encoding="utf-8", errors="replace").read())
        for cls in re.findall(r"@implementation\s+(\w+)", text) + re.findall(r"@interface\s+(\w+)", text):
            out.setdefault(cls, name)
    return out


def main():
    names, ignored = checklist()
    rows, code = carried(), defined()
    both = [n for n in names if n in rows and n in code]
    row_only = [n for n in names if n in rows and n not in code]
    code_only = [n for n in names if n in code and n not in rows]
    owed = [n for n in names if n not in rows and n not in code]
    print("the sweep lists %d CloudKit API names; %d SELECTOR-FRAGMENTS rows ignored (%s)"
          % (len(names), len(ignored), (ignored[0]["sample"][:46] + "...") if ignored else "none"))
    print("carried, a row and a definition here: %d %s" % (len(both), both))
    print("  a row with no definition here: %d %s" % (len(row_only), row_only))
    print("  a definition here with no row:  %d %s" % (len(code_only), code_only))
    print("  owed to the six commits: %d" % len(owed))
    by_group = {}
    for name in owed:
        by_group.setdefault(OWED_BY.get(name, _group_of(name)), []).append(name)
    for group in GROUPS:
        if by_group.get(group):
            print("     %-11s %2d  %s" % (group, len(by_group[group]), ", ".join(by_group[group][:3]) + " ..."))
    return 0 if not (row_only or code_only) else 1


def _group_of(name):
    if name.startswith("CKSyncEngine"):
        return "sync-engine"
    if name.endswith("Operation") or name in ("CKOperation", "CKOperationConfiguration", "CKOperationGroup"):
        return "operations"
    if name in ("CKContainer", "CKDatabaseNotification", "CKDatabaseOperation"):
        return "container"
    if "Subscription" in name or "Notification" in name or name.startswith("CKQuery"):
        return "value"
    return "record"


sys.exit(main())
