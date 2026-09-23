#!/usr/bin/env python3
"""Aggregate Katabasis's per-app absent-sets (corpus-absent/<app>.absent.tsv) into
method-level demand, complementing the name-based class+constant demand (which nm
can't see below the class). Extension files (<app>-ext-<name>.absent.tsv) fold into
their parent app so frequency is per-app, not per-binary.

Categories in the TSV:
  class      -> ObjC system class (cross-checked against corpus demand elsewhere)
  sel        -> [-|+][Class selector]  ObjC selector without a bridge => METHOD-LEVEL
                backport demand (which methods of a class an app actually calls)
  cfunc      -> C function w/ no SDK declaration => Katabasis C-bridge domain
  runtime    -> compiler/objc-runtime symbol => Katabasis domain
  thirdparty -> bundled-framework class => excluded
"""
import os, re, sys
from collections import defaultdict

CORPUS_ROOT = os.environ.get("CHARON_CORPUS_ROOT") or os.path.join(
    os.path.expanduser("~"), "Git", "projects", "ios", "coordination")
DROP = os.path.join(CORPUS_ROOT, "corpus", "absent")

def load():
    per = defaultdict(lambda: defaultdict(set))  # cat -> value -> set(apps)
    if not os.path.isdir(DROP):
        return per
    for f in sorted(os.listdir(DROP)):
        if not f.endswith(".absent.tsv"):
            continue
        app = f[:-len(".absent.tsv")].split("-ext-")[0]   # fold extensions into parent
        for line in open(os.path.join(DROP, f)):
            p = line.rstrip("\n").split("\t")
            if len(p) < 2:
                continue
            cat, val = p[0], p[1]
            per[cat][val].add(app)
    return per

def parse_sel(val):
    # "[-Class selector]" / "[+Class selector]" -> (class, kind, selector)
    m = re.match(r"\[([-+])(\S+)\s+(.+)\]$", val)
    if m:
        return m.group(2), ("instance" if m.group(1) == "-" else "class"), m.group(3)
    return None, "?", val

def report():
    per = load()
    apps = set()
    for cat in per:
        for v in per[cat]:
            apps |= per[cat][v]
    print(f"# Katabasis method-level demand — {len(apps)} apps: {', '.join(sorted(apps))}")
    for cat in ("sel", "cfunc"):
        rows = sorted(per.get(cat, {}).items(), key=lambda kv: (-len(kv[1]), kv[0]))
        print(f"\n## {cat}  ({len(rows)} distinct)")
        if cat == "sel":
            # group selectors by class for backport routing
            byclass = defaultdict(list)
            for val, a in rows:
                cls, knd, selr = parse_sel(val)
                byclass[cls].append((len(a), knd, selr, sorted(a)))
            for cls in sorted(byclass, key=lambda c: -sum(x[0] for x in byclass[c])):
                print(f"  {cls}:")
                for n, knd, selr, al in sorted(byclass[cls], key=lambda x: -x[0]):
                    print(f"    {n:>3}  {knd:8} {selr}   [{','.join(al)}]")
        else:
            for val, a in rows[:60]:
                print(f"  {len(a):>3}  {val}   [{','.join(sorted(a))}]")

if __name__ == "__main__":
    report()
