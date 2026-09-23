#!/usr/bin/env python3
"""Rank a real app's WEAK imports (Telegram UIStack build on the 4S) by what an absent symbol does.

A weak import does not stop dyld when the symbol is missing; the address resolves to NULL. What
happens next depends on the kind of symbol and on whether the code checks first:
  constant (data)   read straight  -> load through a NULL address       -> CRASH-ON-USE
  C function        called         -> call to NULL                      -> CRASH-ON-USE
  ObjC class        messaged       -> message to nil, a silent no-op    -> SILENTLY DIFFERENT
                                      (a crash only later, if the nil result is used as an object)
The list alone does not say whether each use is guarded (`if (&kSym)`, #available, respondsToSelector:),
so nothing here proves a crash. What it can do is: classify each symbol by kind through the SDK dump,
say whether it EXISTS now (registry status implemented/inert = present, not NULL), how new it is,
and how many corpus apps import it (a second, independent view of the same name).

Usage: weak-imports.py <file, one symbol per line>
Output: corpus/weak-imports-ranked.tsv
"""
import json, os, re, sys
from collections import defaultdict

# corpus/ is DATA, in the durable location CHARON_CORPUS_ROOT addresses (default coordination/),
# independent of this script's own location. See tools/corpus/README.md.
CORPUS_ROOT = os.environ.get("CHARON_CORPUS_ROOT") or os.path.join(
    os.path.expanduser("~"), "Git", "projects", "ios", "coordination")
CORPUS = os.path.join(CORPUS_ROOT, "corpus")
if not os.path.isdir(CORPUS):
    sys.exit("weak-imports.py: no corpus/ data directory found at %s. Set CHARON_CORPUS_ROOT to the "
              "directory that contains corpus/." % CORPUS)
# Coordinator regenerates the shared export after each merge; CHARON_REGISTRY_TSV lets a run read a
# different one (e.g. regenerated straight from origin/main) WITHOUT touching the shared file.
EXPORT = os.environ.get("CHARON_REGISTRY_TSV", "/private/tmp/charon-registry-export/carried-registry.tsv")
# Already caught in a real Telegram run on the device (read directly, absent -> NULL -> crash), per Coordinator.
CAUGHT = {"AVAudioSessionPortBluetoothLE", "AVAudioSessionMediaServicesWereLostNotification", "AVAudioSessionModeVideoChat"}

def ver(t):
    return tuple(int(p) for p in t.split(".")) if t else None

def main(path):
    syms = [l.strip() for l in open(path, errors="replace") if l.strip()]
    sdk = json.load(open(os.path.join(CORPUS, "sdk-introduced.json")))
    reg, intro = {}, {}
    for l in open(EXPORT):
        p = l.rstrip("\n").split("\t")
        if len(p) >= 3 and p[0] != "framework":
            reg[p[1]] = p[2]
            if len(p) >= 4 and p[3]:
                intro[p[1]] = p[3]
    # Provisional decisions handed down by Coordinator that the registry export does not carry yet. Marked
    # "(override)" everywhere they show, and only used when the registry has no row for the symbol.
    overrides = {}
    op = os.path.join(CORPUS, "decision-overrides.tsv")
    if os.path.exists(op):
        for l in list(open(op))[1:]:
            q = l.rstrip("\n").split("\t")
            if len(q) >= 2:
                overrides[q[0]] = q[1]
    store = json.load(open(os.path.join(CORPUS, "store.json")))
    corpus = defaultdict(lambda: {"apps": set(), "strong": set()})
    for app, d in store["apps"].items():
        for r in d["demand"]:
            e = corpus[r["name"]]
            e["apps"].add(app)
            if not r.get("weak"):
                e["strong"].add(app)

    rows = []
    for raw in syms:
        if raw.startswith("_OBJC_CLASS_$_"):
            kind, name = "class", raw[len("_OBJC_CLASS_$_"):]
        elif raw.startswith("_OBJC_METACLASS_$_"):
            kind, name = "metaclass", raw[len("_OBJC_METACLASS_$_"):]
        elif raw.startswith(("_$s", "_$S", "$s", "$S")):
            kind, name = "swift", raw
        elif raw.startswith(("__Z", "_Z")):
            kind, name = "c++", raw
        elif raw.startswith("__"):
            kind, name = "runtime", raw
        else:
            name = raw[1:] if raw.startswith("_") else raw
            e = sdk.get(name + "()")
            kind = "function" if e else ("constant" if sdk.get(name) and sdk[name][0] == "constant" else None)
            if kind is None:
                # no SDK row: Apple's k-prefix marks a constant; otherwise lowercase names are almost
                # always functions and Capitalised ones constants
                kind = "constant?" if re.match(r"k[A-Z]", name) else ("function?" if name[:1].islower() else "constant?")
        base = name if kind in ("class", "metaclass") else name
        keys = [base, base + "()", raw, raw[1:] if raw.startswith("_") else raw]
        st = next((reg[k] for k in keys if k in reg), None)
        if st is None and raw in overrides:
            st = overrides[raw] + " (override)"
        srow = sdk.get(base) or sdk.get(base + "()")
        version = intro.get(next((k for k in keys if k in intro), ""), "") or (srow[1] if srow and srow[1] else "")
        framework = srow[2] if srow else ""
        c = corpus.get(raw) or corpus.get(name) or {"apps": set(), "strong": set()}
        rows.append({"raw": raw, "name": name, "kind": kind, "status": st or "no registry row", "introduced": version,
                     "framework": framework, "apps": len(c["apps"]), "strong": len(c["strong"]), "caught": name in CAUGHT})

    def present(r):
        return r["status"] in ("implemented", "inert")
    METAL = re.compile(r"Metal|MTL|MTK")
    def tier(r):
        if r["caught"]:
            return "0 caught on device"
        if METAL.search(r["name"]) and not present(r):
            return "6 Metal (not portable to A5)"
        if present(r):
            return "9 exists now"
        if r["kind"] in ("constant", "constant?"):
            return "1 NULL constant"
        if r["kind"] in ("function", "function?"):
            return "2 NULL function"
        if r["kind"] in ("class", "metaclass"):
            return "3 nil class"
        if r["kind"] == "runtime":
            return "5 compiler runtime (Katabasis)"
        return "4 swift/c++ (other track)"
    for r in rows:
        r["tier"] = tier(r)
    def ver_key(r):
        v = ver(r["introduced"]) if r["introduced"] else (99,)
        return v
    rows.sort(key=lambda r: (r["tier"], -r["apps"], ver_key(r), r["name"]))
    out = os.path.join(CORPUS, "weak-imports-ranked.tsv")
    with open(out, "w") as f:
        f.write("tier\tsymbol\tkind\tframework\tintroduced\tregistry\tcorpus_apps_importing\tcorpus_strong\n")
        for r in rows:
            f.write(f"{r['tier']}\t{r['raw']}\t{r['kind']}\t{r['framework']}\t{r['introduced']}\t{r['status']}\t{r['apps']}\t{r['strong']}\n")
    print(f"{len(rows)} weak imports -> {out}")
    tally = defaultdict(lambda: defaultdict(int))
    for r in rows:
        tally[r["tier"]][r["status"]] += 1
    for t in sorted(tally):
        print(f"  {t:28} {sum(tally[t].values()):>4}   " + ", ".join(f"{k} {v}" for k, v in sorted(tally[t].items(), key=lambda kv: -kv[1])))
    fw = defaultdict(lambda: defaultdict(int))
    for r in rows:
        if r["tier"][0] in "0123":
            fw[r["framework"] or "(not in my SDK dump)"][r["tier"][0] + ":" + r["status"]] += 1
    print("\nby framework (tiers 0-3 only: what would be NULL or nil), top 14:")
    for f_, c in sorted(fw.items(), key=lambda kv: -sum(kv[1].values()))[:14]:
        print(f"  {f_:26} {sum(c.values()):>3}   " + ", ".join(f"{k} x{v}" for k, v in sorted(c.items())))
    tg = store["apps"].get("telegram", {"demand": []})
    tg_names = {r["name"] for r in tg["demand"]}
    hit = [r for r in rows if r["raw"] in tg_names or r["name"] in tg_names]
    print(f"\noverlap with the release Telegram in my corpus (a different, arm64 build): {len(hit)} of {len(rows)} weak symbols also appear in its imports")
    return rows

if __name__ == "__main__":
    main(sys.argv[1])
