#!/usr/bin/env python3
"""cloudkit-owed.py - what the ledger still owes, by class, under one stated counting rule.

The rule, in one line, because a table in a facts file that cannot be recomputed is not evidence:

    THE COUNT FOR A CLASS IS THE NUMBER OF DISTINCT `api` SPELLINGS THE LEDGER ATTRIBUTES TO IT.
    A class is attributed its own rows; a member (`-[CKRecordID recordID]`) and a property
    (`CKRecord.recordID`) are attributed to the class that owns them; everything else - a constant,
    an enum, a protocol, a struct, a typealias, a function - is attributed to ITSELF, because the
    ledger's `api` for one of those is its own name and not a spelling under a class. A class named
    by no ledger row counts zero.

The ledger is the input and the only place the owed list comes from:
`coordination/corpus/ledger/CloudKit.tsv`, read with the csv module. Nothing here writes it.

    cloudkit-owed.py [--ledger PATH] [--registry PATH] [--top N] [--class NAME]

Exits 0. It is a count, and a count that cannot be recomputed is the defect this exists to remove.
"""
import argparse
import collections
import csv
import json
import os
import sys

LEDGER = os.environ.get("CHARON_LEDGER",
                        os.path.expanduser("~/Git/projects/ios/coordination/corpus/ledger/CloudKit.tsv"))
REGISTRY = "packages/a/apple-backports/registry/CloudKit/values.json"


def owner_of(api):
    """the class a ledger row is attributed to, or None when it is attributed to itself"""
    if api[:2] in ("+[", "-["):                       # a method
        return api[2:].split(" ")[0].split(":")[0]
    if "." in api:                                    # a property: CKRecord.recordID
        head = api.split(".")[0]
        return head if head[:1].isupper() else None
    if "(" in api or api.endswith("()"):             # a C function spelling
        return None
    return None                                       # a class, constant, enum, protocol, struct


def read_ledger(path):
    with open(path, newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    if not rows or "api" not in rows[0]:
        raise SystemExit("cloudkit-owed.py: %s has no api column" % path)
    return rows


def registry_apis(path):
    """the api spellings this tree already carries a row for"""
    held = json.load(open(path))
    return {e["api"] for e in (held.get("entries") if isinstance(held, dict) else held)}


def owed_by_class(rows, carried):
    """{class: (owed, total)} over DISTINCT api spellings attributed to that class"""
    per = collections.defaultdict(set)
    for row in rows:
        api = row["api"].strip()
        if not api or api in carried:
            continue
        cls = owner_of(api) or api
        per[cls].add(api)
    return {cls: (len(apis), len(apis)) for cls, apis in per.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ledger", default=LEDGER)
    parser.add_argument("--registry", default=REGISTRY)
    parser.add_argument("--top", type=int, default=15)
    parser.add_argument("--class", dest="only")
    args = parser.parse_args()

    rows = read_ledger(args.ledger)
    carried = registry_apis(args.registry)
    per = owed_by_class(rows, carried)
    owed_rows = [r for r in rows if r["api"].strip() and r["api"].strip() not in carried]

    if args.only:
        print("%-34s %d owed of %d distinct"
              % (args.only, per.get(args.only, (0, 0))[0], per.get(args.only, (0, 0))[1]))
        return 0

    print("ledger rows: %d   carried by %s: %d   owed: %d"
          % (len(rows), os.path.basename(args.registry), len(carried), len(owed_rows)))
    print("owed by kind: %s"
          % dict(sorted(collections.Counter(r["kind"] for r in owed_rows).items())))
    print("distinct api spellings owed, by the class they are attributed to (rule: the one above):")
    for cls, (owed, _total) in sorted(per.items(), key=lambda kv: (-kv[1][0], kv[0]))[:args.top]:
        if owed > 1 or cls in carried:
            print("  %-34s %4d" % (cls, owed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
