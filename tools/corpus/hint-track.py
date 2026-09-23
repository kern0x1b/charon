#!/usr/bin/env python3
"""Ledger of how the decision hints compare with what the row owners later decided.

Run right after a regeneration, with the PREVIOUS list still saved as crash-demand-prev.tsv:
for each row that was UNDECIDED in the previous list, the outcome is
   carry   - the row left the list (the registry now implements it or carries it inert)
   absent  - the row is still listed and its registry status became absent
   pending - still undecided
Only decided outcomes are appended to corpus/hint-ledger.tsv (one line per API, never twice).
Then prints, per hint tag, how often the decision matched the hint.

A hint agrees with an outcome when: likely-carry -> carry, likely-absent -> absent.
The other tags (no-signal, class-undecided, protocol-owner, band-13+ unstarted) make no
prediction; their outcomes are recorded so the base rate is visible.

Run it on every batch: the previous list is overwritten by the next regeneration, and what
was decided in between cannot be reconstructed afterwards.
"""
import csv, os, re, sys, datetime
# corpus/ is DATA, in the durable location CHARON_CORPUS_ROOT addresses (default coordination/),
# independent of this script's own location. See tools/corpus/README.md.
CORPUS_ROOT = os.environ.get("CHARON_CORPUS_ROOT") or os.path.join(
    os.path.expanduser("~"), "Git", "projects", "ios", "coordination")
C = os.path.join(CORPUS_ROOT, "corpus")
if not os.path.isdir(C):
    sys.exit("hint-track.py: no corpus/ data directory found at %s. Set CHARON_CORPUS_ROOT to the "
              "directory that contains corpus/." % C)

def load(p):
    return {r[2]: r for r in list(csv.reader(open(p, encoding="utf-8"), delimiter="\t"))[1:]}

def tag_of(hint):
    return re.sub(r" \(.*\)$", "", hint or "").strip() or "(none)"

EXPORT = os.environ.get("CHARON_REGISTRY_TSV", "/private/tmp/charon-registry-export/carried-registry.tsv")

def load_registry(path):
    reg = {}
    if os.path.exists(path):
        for l in open(path):
            p = l.rstrip("\n").split("\t")
            if len(p) >= 3 and p[0] != "framework":
                reg[p[1]] = p[2]
    return reg

def keys_for(api):
    api = re.sub(r" \(\+\d+ owners\)$", "", api)
    ks = [api]
    m = re.match(r"^[-+]\[(\w+) ", api)
    owner = m.group(1) if m else (api.split(".", 1)[0] if "." in api else None)
    if "." in api and not api.startswith(("-", "+")):
        o, n = api.split(".", 1); up = n[0].upper() + n[1:]
        ks += ["-[%s %s]" % (o, n), "-[%s set%s:]" % (o, up), "-[%s is%s]" % (o, up),
               "+[%s %s]" % (o, n), "+[%s set%s:]" % (o, up)]
    if owner:
        ks.append(owner)
    # link-time names: the registry stores a constant without the linker's leading underscore, and a C
    # function as `name()`. Without these, a symbol's registry rows are never found and a decision is missed.
    if not api.startswith(("-", "+")) and "." not in api:
        if api.startswith("_"):
            ks.append(api[1:])
            ks.append(api[1:] + "()")
        ks.append(api + "()")
    return ks

def main(batch):
    # A row counts as decided by an owner only if the REGISTRY's status for it (its own rows or its
    # owner class) differs between the previous run's snapshot and now. A row can also leave the list
    # because my rule changed; that is not a decision and must not enter the ledger.
    last = load_registry(os.path.join(C, "registry-last.tsv"))
    now = load_registry(EXPORT)
    have_baseline = os.path.exists(os.path.join(C, "registry-last.tsv"))
    def registry_changed(api):
        ks = keys_for(api)
        return any(last.get(k) != now.get(k) for k in ks)
    prev = load(os.path.join(C, "crash-demand-prev.tsv"))
    new = load(os.path.join(C, "crash-demand-top.tsv"))
    ledger_p = os.path.join(C, "hint-ledger.tsv")
    seen = set()
    if os.path.exists(ledger_p):
        seen = {r[1] for r in list(csv.reader(open(ledger_p), delimiter="\t"))[1:]}
    new_rows = []
    for api, r in prev.items():
        if not r[11].startswith("undecided") or api in seen or r[3] != "selector":
            continue
        if not have_baseline or not registry_changed(api):
            continue
        if api not in new:
            outcome = "carry"
        elif new[api][11].split("(")[0] == "absent":
            outcome = "absent"
        else:
            continue
        new_rows.append((batch, api, tag_of(r[12]), outcome, r[9], r[8], r[5]))
    # ---- reversals: rows that were decided ABSENT in the previous list and have since left it
    # (implemented or inert). Not a hint outcome (absent rows carry no hint) but the measure of
    # how often an absent decision is later withdrawn.
    rev_p = os.path.join(C, "absent-reversals.tsv")
    rev_seen = set()
    if os.path.exists(rev_p):
        rev_seen = {r[1] for r in list(csv.reader(open(rev_p), delimiter="\t"))[1:]}
    reversed_now = [(batch, api, r[9], r[8], r[5], r[6]) for api, r in prev.items()
                    if r[11].split("(")[0] == "absent" and api not in new and api not in rev_seen
                    and have_baseline and registry_changed(api)]
    if reversed_now:
        head = not os.path.exists(rev_p)
        with open(rev_p, "a") as f:
            if head:
                f.write("batch\tapi\tunguarded_callers\tapps\tband\troute\n")
            for row in reversed_now:
                f.write("\t".join(row) + "\n")
    if not have_baseline:
        print("no registry baseline yet (registry-last.tsv): recording nothing this run")
    print(f"absent decisions reversed this batch: {len(reversed_now)}")
    write_header = not os.path.exists(ledger_p)
    with open(ledger_p, "a") as f:
        if write_header:
            f.write("batch\tapi\thint\toutcome\tunguarded_callers\tapps\tband\n")
        for row in new_rows:
            f.write("\t".join(row) + "\n")
    rows = list(csv.reader(open(ledger_p), delimiter="\t"))[1:]
    print(f"ledger: +{len(new_rows)} decided this batch, {len(rows)} in total")
    tally = {}
    for _b, _a, tag, out, *_ in rows:
        tally.setdefault(tag, {"carry": 0, "absent": 0})[out] += 1
    for tag, c in sorted(tally.items()):
        n = c["carry"] + c["absent"]
        pred = {"likely-carry": "carry", "likely-absent": "absent"}.get(tag)
        agree = f"  agreed {c[pred]}/{n}" if pred else "  (makes no prediction)"
        print(f"  {tag:24} decided {n:>3}  carry {c['carry']:>3}  absent {c['absent']:>3}{agree}")

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else datetime.date.today().isoformat())
