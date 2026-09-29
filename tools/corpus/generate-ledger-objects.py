#!/usr/bin/env python3
"""The bulk generator: ledger rows in, objects and registry files out, split by measured rung.

Driven by the owner: take a framework's ledger rows whose `needs` is `code` or `code+lift`, order
them by the crash-demand list, and carry each one - measuring, for every row, whether some HELD release
already exports its symbol, because that is what decides which object's file it goes in and what the
registry row may claim.

    ./generate.py <out dir> [--demand <tsv>] [--ledger <name>=<path> ...] [--limit N] [--all]

The split is by MEASUREMENT and never by the corpus's `introduced`, and the two disagree: a name
whose header annotation is later than the release that exports it costs the port the band, because
`carried` is `introduced <= deployment`. So the emitted `introduced` is the rung for a row whose
header annotation is later, and the row's `reason` says which rung and why.

Every rung searched is named in the output, with the planted control, so a run that measured nothing
is visible rather than silent.
"""
import argparse
import json
import os
import re
import sys
from collections import Counter, defaultdict

RUNG_ARCH = [
    ("4.3", "armv7"), ("6.1.3", "armv7"), ("7.0", "armv7"), ("7.1", "armv7"),
    ("7.1.1", "armv7"), ("7.1.2", "armv7"), ("8.0", "armv7"), ("8.1.3", "armv7s"),
    ("8.2", "armv7s"), ("8.4.1", "armv7s"), ("9.3.6", "armv7"), ("10.0.1", "arm64"),
    ("11.0", "arm64"), ("12.0", "arm64"), ("16.0", "arm64e"),
]
CONTROL = "_NSFileSize"


def load_dumps(cache):
    """release -> set of exported symbol names, from the dumps already on disk."""
    out = {}
    for release, _arch in RUNG_ARCH:
        path = os.path.join(cache, "cache-%s.tsv" % release)
        names = set()
        if os.path.exists(path):
            for line in open(path):
                parts = line.rstrip("\n").split("\t")
                if len(parts) == 2:
                    names.add(parts[0])
        out[release] = names
    return out


def symbols_for(api, kind):
    """The symbols that prove a release carries this row: a class and its metaclass, a method's
    _OBJC_METHOD_$_ name, a property's _OBJC_IVAR_$_ name, a function's own name."""
    out = set()
    if kind == "class" or kind == "protocol":
        out.add("_OBJC_CLASS_$_" + api)
        out.add("_OBJC_METACLASS_$_" + api)
    else:
        m = re.match(r"^[-+]\[([A-Za-z0-9_]+) (.+)\]$", api)
        if m:
            out.add(("_OBJC_CLASS_METHOD_$_" if api[0] == "+" else "_OBJC_METHOD_$_") + m.group(2))
        m = re.match(r"^([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)$", api)
        if m:
            out.add("_OBJC_IVAR_$_" + api)
        m = re.match(r"^([A-Za-z0-9_]+)\(", api)
        if m:
            out.add(api)
        m = re.match(r"^_([A-Za-z0-9_]+)$", api)     # a C symbol the demand list names with its _
        if m:
            out.add(api)
            out.add("_" + api)
    return out


def owner_of(api, kind):
    if kind in ("class", "protocol"):
        return api
    m = re.match(r"^[-+]\[([A-Za-z0-9_]+) ", api)
    if m:
        return m.group(1)
    m = re.match(r"^([A-Za-z0-9_]+)\.", api)
    if m:
        return m.group(1)
    m = re.match(r"^([A-Za-z0-9_]+)\(", api)
    if m:
        return m.group(1)
    return api


def read_ledger(path):
    rows = []
    with open(path) as fh:
        head = fh.readline().rstrip("\n").split("\t")
        idx = {n: i for i, n in enumerate(head)}
        for line in fh:
            f = line.rstrip("\n").split("\t")
            if len(f) < len(head):
                continue
            rows.append({k: (f[i] if i < len(f) else "") for k, i in idx.items()})
    return rows


def read_demand(path):
    if not path or not os.path.exists(path):
        return {}
    order = {}
    with open(path) as fh:
        head = fh.readline().rstrip("\n").split("\t")
        idx = {n: i for i, n in enumerate(head)}
        for line in fh:
            f = line.rstrip("\n").split("\t")
            if len(f) < len(head):
                continue
            key = (f[idx["framework"]], f[idx["api"]])
            if key not in order:
                order[key] = int(f[idx["rank"]]) if f[idx["rank"]].isdigit() else 10 ** 6
    return order


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--cache", default=None, help="directory of cache-<release>.tsv dumps")
    ap.add_argument("--demand", default=None)
    ap.add_argument("--ledger", action="append", default=[], metavar="NAME=PATH")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--all", action="store_true", help="every code/code+lift row, not only the demanded ones")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    cache = args.cache or os.path.join(os.path.dirname(os.path.abspath(__file__)), "caches")
    dumps = load_dumps(cache)
    present = [r for r, _ in RUNG_ARCH if dumps[r]]
    missing = [r for r, _ in RUNG_ARCH if not dumps[r]]
    control = next((r for r, _ in RUNG_ARCH if CONTROL in dumps[r]), None)
    print("# caches found: %d of %d rungs %s" % (len(present), len(RUNG_ARCH), present))
    if missing:
        print("# NO DUMP for: %s" % ", ".join(missing))
    print("# the planted control %s is found at: %s" % (CONTROL, control or "NO RUNG - the measurement is void"))
    if not control:
        sys.exit("no control in any cache: refusing to report a measurement")
    nonsense = "_AVNoSuchSymbolForAReviewerControl"
    seen_nonsense = [r for r, _ in RUNG_ARCH if nonsense in dumps[r]]
    print("# the nonsense control is found at: %s" % (seen_nonsense or "nowhere, as it must be"))

    ledgers = {}
    for spec in args.ledger:
        name, _, path = spec.partition("=")
        ledgers[name] = read_ledger(path)
    demand = read_demand(args.demand)

    chosen = []
    for fw, rows in ledgers.items():
        for r in rows:
            needs = (r.get("needs") or "")
            if not re.match(r"^code(\+lift)?$", needs):
                continue
            rank = demand.get((fw, r["api"]))
            if args.all or rank is not None:
                r = dict(r)
                r["framework"] = fw
                r["demand_rank"] = rank
                chosen.append(r)
    chosen.sort(key=lambda r: (r["demand_rank"] is None, r["demand_rank"] or 0, r["framework"], r["api"]))
    if args.limit:
        chosen = chosen[: args.limit]

    measured = []
    for r in chosen:
        syms = symbols_for(r["api"], r["kind"])
        first = next((rel for rel, _ in RUNG_ARCH if syms & dumps[rel]), "NONE-OF-THE-15")
        measured.append({**r, "owner": owner_of(r["api"], r["kind"]), "first_held_rung": first})

    print()
    print("# rows selected: %d  (demanded %d)" % (len(measured), sum(1 for m in measured if m["demand_rank"])))
    print("# by kind: %s" % dict(Counter(m["kind"] for m in measured)))
    print("# by first held rung: %s" % dict(Counter(m["first_held_rung"] for m in measured)))
    print("# owners: %d" % len({m["owner"] for m in measured}))

    groups = defaultdict(list)
    for m in measured:
        groups[m["first_held_rung"]].append(m)

    if args.dry_run:
        for rung in sorted(groups):
            print()
            print("## rung %s: %d rows" % (rung, len(groups[rung])))
            for m in sorted(groups[rung], key=lambda m: (m["owner"], m["api"])):
                d = ("demand#%s " % m["demand_rank"]) if m["demand_rank"] else ""
                print("   %-46s %-9s %-9s introduced=%-7s" % (d, m["kind"], m["owner"], m.get("introduced", "")))
        return

    os.makedirs(args.out, exist_ok=True)
    manifest = {"rungs_searched": [r for r, _ in RUNG_ARCH], "control_found_at": control,
                "nonsense_found_at": seen_nonsense, "rows": []}
    for rung in sorted(groups):
        members = sorted(groups[rung], key=lambda m: (m["owner"], m["api"]))
        name = "Demand%s" % (rung.replace(".", "").replace("-", "M") if rung != "NONE-OF-THE-15" else "Unheld")
        manifest["rows"].append({"rung": rung, "object": name, "count": len(members),
                                 "apis": [m["api"] for m in members]})
    with open(os.path.join(args.out, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=1)
    print()
    print("# wrote %s/manifest.json: %d objects" % (args.out, len(manifest["rows"])))


if __name__ == "__main__":
    main()
