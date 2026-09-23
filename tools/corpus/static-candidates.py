#!/usr/bin/env python3
"""Join surface-diff's static candidate list (undecided API, from Backports 7-10) with corpus demand.

Input: the file `surface-diff.py --release 6.0 --list` writes, path given as argv[1]. Its lines are
`<version|?> <kind> <api>` under per-framework headers ("UIKit:", "Foundation:"). A version means the
SDK gives the member's availability; `?` means it has none recorded (the cfee153 additions).

For every listed method/property, count the corpus apps that SEND its selector (bundle carries the
string and does not define it) and, from the app deployment targets, how many can call it without a
guard. Output corpus/static-candidates-demand.tsv (or argv[2] / $CHARON_STATIC_CANDIDATES_OUT, to
redirect a one-off or test run away from the real file), then compare with the crash-demand list,
which is built by a different route (SDK dump + registry join): the two should agree on the
undecided rows that apps send, and where they differ one of the two has a bug.

Usage: python3 static-candidates.py <surface-diff --list output> [output-path]
"""
import csv, json, os, re, sys
from collections import defaultdict

# corpus/ is DATA, in the durable location CHARON_CORPUS_ROOT addresses (default coordination/),
# independent of this script's own location. See tools/corpus/README.md.
CORPUS_ROOT = os.environ.get("CHARON_CORPUS_ROOT") or os.path.join(
    os.path.expanduser("~"), "Git", "projects", "ios", "coordination")
CORPUS = os.path.join(CORPUS_ROOT, "corpus")
if not os.path.isdir(CORPUS):
    sys.exit("static-candidates.py: no corpus/ data directory found at %s. Set CHARON_CORPUS_ROOT to "
              "the directory that contains corpus/." % CORPUS)
MINOS = {"ish": (11, 0), "ppsspp": (11, 0), "pojav": (12, 2), "provenance": (16, 0),
         "delta": (14, 0), "utm": (14, 0), "aidoku": (15, 0), "yattee": (14, 0),
         "session": (15, 0), "telegram": (11, 0)}
LINE = re.compile(r"^\s+(\?|\d+(?:\.\d+)*)\s+(method|property|class|protocol|constant|function)\s+(.+?)\s*$")

def selectors(api, kind):
    m = re.match(r"^[-+]\[\w+ (.+)\]$", api)
    if m:
        return [m.group(1)]
    if kind == "property" and "." in api:
        n = api.split(".", 1)[1]
        up = n[0].upper() + n[1:]
        return [n, "set" + up + ":", "is" + up]
    return []

def main(path, out_override=None):
    fw = None
    cands = []                                   # (framework, version|None, kind, api)
    for line in open(path, errors="replace"):
        h = re.match(r"^(\w+): \d+ declared", line)
        if h:
            fw = h.group(1); continue
        m = LINE.match(line)
        if m and fw:
            v = None if m.group(1) == "?" else tuple(int(p) for p in m.group(1).split("."))
            cands.append((fw, v, m.group(2), m.group(3)))
    universe = set(l.rstrip("\n") for l in open(os.path.expanduser("~/.charon/dyld/6.0/selectors_armv7.txt")))
    sends = defaultdict(set)
    for app in MINOS:
        c = set(json.load(open(os.path.join(CORPUS, "selcache", app + ".json"))))
        d = set(json.load(open(os.path.join(CORPUS, "defcache", app + ".json"))))
        for s in (c - d) - universe:            # same rule as the crash list: a name 6.0 already has is ambiguous
            sends[s].add(app)
    out = []
    for fw, v, kind, api in cands:
        if kind not in ("method", "property"):
            continue
        apps = set()
        for s in selectors(api, kind):
            if kind == "property" and s == api.split(".", 1)[1] and ("is" + s[0].upper() + s[1:]) in universe and s not in universe:
                continue
            apps |= sends.get(s, set())
        if not apps:
            continue
        crash = sorted(a for a in apps if v is not None and MINOS[a] >= v)
        out.append((len(crash), len(apps), fw, ".".join(map(str, v)) if v else "?", kind, api, sorted(apps)))
    out.sort(key=lambda t: (-t[0], -t[1], t[5]))
    # Real corpus/static-candidates-demand.tsv was overwritten once by a test run against a
    # fabricated input during this migration (see README) -- CHARON_STATIC_CANDIDATES_OUT (or the
    # positional arg below) lets a one-off or test run redirect the write without touching it.
    p = out_override or os.environ.get("CHARON_STATIC_CANDIDATES_OUT") or os.path.join(CORPUS, "static-candidates-demand.tsv")
    with open(p, "w") as f:
        f.write("unguarded_callers\tapps\tframework\tintroduced\tkind\tapi\tsenders\n")
        for cr, n, fw_, v, k, a, apps in out:
            f.write(f"{cr}\t{n}\t{fw_}\t{v}\t{k}\t{a}\t{','.join(apps)}\n")
    total = len([1 for c in cands if c[2] in ("method", "property")])
    print(f"listed candidates: {len(cands)} ({total} methods/properties); sent by >=1 corpus app: {len(out)} -> {p}")
    print(f"  of those with a known version: {sum(1 for o in out if o[3] != '?')}; unversioned ('?'): {sum(1 for o in out if o[3] == '?')}")

    # ---- compare with the crash-demand list (different route to the same question)
    mine = {}
    for r in list(csv.reader(open(os.path.join(CORPUS, "crash-demand-top.tsv"), encoding="utf-8"), delimiter="\t"))[1:]:
        api = re.sub(r" \(\+\d+ owners\)$", "", r[2])
        mine[api] = r
    theirs = {o[5]: o for o in out}
    my_undec = {a for a, r in mine.items() if r[3] == "selector" and r[11].startswith("undecided") and r[4] in ("UIKit", "Foundation")}
    t_sent = {a for a, o in theirs.items() if o[0] >= 1}
    both = my_undec & t_sent
    print(f"\ncrash list: undecided selector rows {len(my_undec)}; static list rows the corpus sends unguarded {len(t_sent)}; in both {len(both)}")
    only_theirs = sorted(t_sent - my_undec, key=lambda a: -theirs[a][0])
    only_mine = sorted(my_undec - set(theirs), key=lambda a: -int(mine[a][9]))
    print(f"  only in the static list (my list lacks them): {len(only_theirs)}")
    for a in only_theirs[:12]:
        o = theirs[a]; print(f"     {o[0]}/{o[1]} {o[3]:5} {mine[a][11] if a in mine else 'not in my list':14} {a[:70]}")
    print(f"  only in my list (the static list does not call them undecided): {len(only_mine)}")
    for a in only_mine[:12]:
        r = mine[a]; print(f"     {r[9]}/{r[8]} {r[5]:5} {r[12][:22]:22} {a[:64]}")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
