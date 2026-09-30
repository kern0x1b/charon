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

# The sweep's file, found beside the repository rather than written down: a home path in a tracked file
# is refused by the commit hook, and rightly - the tool moves with the machine.
# The sweep's file, found by WALKING UP rather than by counting: this script is
# <repo>/tools/corpus/cloudkit-checklist.py, and <repo> is either the shared checkout (where the sweep's
# file is at .agent-work/runs/sweep/) or a worktree of it under .agent-work/worktrees/<name> (where the
# shared checkout is three levels up). Counting produced a path one level short of both, and the first two
# commits of this tool said otherwise; this walks until it finds the file, and fails by name if it cannot.
def _find_sweep():
    here = os.path.abspath(__file__)
    while True:
        candidate = os.path.join(os.path.dirname(here), ".agent-work", "runs", "sweep",
                                 "3d90-api-by-framework.tsv")
        if os.path.exists(candidate):
            return candidate
        parent = os.path.dirname(here)
        if parent == here:
            break
        here = parent
    raise SystemExit("cloudkit-checklist.py: no 3d90-api-by-framework.tsv above this file; set SWEEP_TSV")


SWEEP = os.environ.get("SWEEP_TSV") or _find_sweep()
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
            # Keyed by (kind, api), not by the name alone: `+[CKRecordID new]` is a member of
            # CKRecordID, not a row for CKRecordID, and keying both on the bare name let a member
            # row stand in for a class row that was not there. A sweep name counts as carried only
            # through a class row of its own.
            api = row["api"]
            if row["kind"] != "class":
                continue
            out.setdefault(api, name)
    return out


def defined():
    out = {}
    if not os.path.isdir(SRC):
        return out
    for name in sorted(os.listdir(SRC)):
        if not name.endswith((".m", ".h")):
            continue
        text = re.sub(r"//[^\n]*", "", open(os.path.join(SRC, name), encoding="utf-8", errors="replace").read())
        # @implementation, and NOT @interface: a declaration is not a definition, which is the mirror's
        # rule and the gate's - `built, but no entry in registry/` and its mirror, `a row with no
        # definition`, are both about code that is actually there. Counting an @interface let
        # CKSyncEnginePendingZoneDelete pass as carried twice, and the two checks then disagreed.
        for cls in re.findall(r"@implementation\s+(\w+)", text):
            out.setdefault(cls, name)
    return out


def main():
    names, ignored = checklist()
    rows, code = carried(), defined()
    both = [n for n in names if n in rows and n in code]
    row_only = [n for n in names if n in rows and n not in code]
    code_only = [n for n in names if n in code and n not in rows]
    owed = [n for n in names if n not in rows and n not in code]
    # The same contradiction the mirror reports as its fourth direction, read here over the sweep's
    # own names: a member row carried while its class row is absent or missing.
    carried_members = []
    if os.path.isdir(REG):
        for name in sorted(os.listdir(REG)):
            if not name.endswith(".json"):
                continue
            data = json.load(open(os.path.join(REG, name)))
            for row in (data["entries"] if isinstance(data, dict) else data):
                if row.get("kind") != "method" or row.get("status") != "implemented":
                    continue
                api = row["api"]
                cls = api[2:].split(" ")[0] if api[:2] in ("+[", "-[") else api.split("(")[0].strip("+-[]")
                row_ = [r for r in (data["entries"] if isinstance(data, dict) else data)
                        if r["kind"] == "class" and r["api"] == cls]
                if not row_ or row_[0].get("status") == "absent":
                    carried_members.append(api)
    print("the sweep lists %d CloudKit API names; %d SELECTOR-FRAGMENTS rows ignored (%s)"
          % (len(names), len(ignored), (ignored[0]["sample"][:46] + "...") if ignored else "none"))
    print("carried, a row and a definition here: %d %s" % (len(both), both))
    print("  a row with no definition here: %d %s" % (len(row_only), row_only))
    print("  a definition here with no row:  %d %s" % (len(code_only), code_only))
    print("  member carried without its class: %d %s" % (len(carried_members), carried_members))
    print("  owed to the six commits: %d" % len(owed))
    by_group = {}
    for name in owed:
        by_group.setdefault(OWED_BY.get(name, _group_of(name)), []).append(name)
    for group in GROUPS:
        if by_group.get(group):
            print("     %-11s %2d  %s" % (group, len(by_group[group]), ", ".join(by_group[group][:3]) + " ..."))
    return 0 if not (row_only or code_only or carried_members) else 1


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
