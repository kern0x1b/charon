#!/usr/bin/env python3
"""Generate the v3 corpus deliverable: report.md + per-band TSVs, from store.json.
Unions Katabasis's cleaned `class` rows (corpus-absent/*.absent.tsv) as a
cross-check column. Run after a full re-ingest."""
import json, os, sys, importlib.util
from collections import defaultdict

HERE = os.path.dirname(os.path.realpath(__file__))
# aggregate.py is a NEIGHBOR SCRIPT (found beside this file wherever it is copied to); store.json
# and everything under corpus/ is DATA, in the durable location CHARON_CORPUS_ROOT addresses
# (default coordination/), independent of this script's own location. See tools/corpus/README.md.
spec = importlib.util.spec_from_file_location("agg", os.path.join(HERE, "aggregate.py"))
agg = importlib.util.module_from_spec(spec); spec.loader.exec_module(agg)
CORPUS_ROOT = os.environ.get("CHARON_CORPUS_ROOT") or os.path.join(
    os.path.expanduser("~"), "Git", "projects", "ios", "coordination")
CORPUS = os.path.join(CORPUS_ROOT, "corpus")
if not os.path.isdir(CORPUS):
    sys.exit("gen-report.py: no corpus/ data directory found at %s. Set CHARON_CORPUS_ROOT to the "
              "directory that contains corpus/ (holds store.json, caches/, band-*.tsv)." % CORPUS)
store = json.load(open(os.path.join(CORPUS, "store.json")))
reg = agg.load_registry()
DROP = "/Users/alexanderhavrysh/Git/projects/ios/emulator-lab/recompile/corpus-absent"

# Katabasis class rows per app (cleaned system-only)
kata = defaultdict(set)
if os.path.isdir(DROP):
    for f in os.listdir(DROP):
        if not f.endswith(".absent.tsv"):
            continue
        app = f[:-len(".absent.tsv")].split("-ext-")[0]
        for line in open(os.path.join(DROP, f)):
            p = line.rstrip("\n").split("\t")
            if p and p[0] == "class" and len(p) > 1:
                kata[app].add(p[1])

apps = sorted(store["apps"])
# aggregate my demand
agg_rows = {}   # (cat,kind,name,fw,band) -> {apps,strong}
for app, d in store["apps"].items():
    for r in d["demand"]:
        if agg.is_swift_mangled(r["name"]):
            continue
        cat = r.get("cat", "FRAMEWORK")
        key = (cat, r["kind"], r["name"], r["framework"], r["band"])
        e = agg_rows.setdefault(key, {"apps": set(), "strong": set()})
        e["apps"].add(app)
        if not r.get("weak"):
            e["strong"].add(app)

def band_tally(cat_filter):
    gap = defaultdict(int); carried = defaultdict(int); na = defaultdict(int)
    for (cat, kind, name, fw, band), e in agg_rows.items():
        if cat != cat_filter:
            continue
        st = agg.carried_status(reg, kind, name, fw)
        (na if st == "n/a-A5" else carried if st not in agg.GAP_STATUS else gap)[band] += 1
    return gap, carried, na

CACHES = os.path.join(CORPUS, "caches")
def _load_cache_set(stem):
    s = set()
    p = os.path.join(CACHES, stem + ".tsv")
    if os.path.exists(p):
        for line in open(p):
            sym = line.split("\t", 1)[0]
            if sym:
                s.add(sym)
    return s
def _full(kind, name):
    return ("_OBJC_CLASS_$_" + name) if kind == "class" else name

def write_band_files():
    # The lumped "13+" band is split into introduced-13-16 vs 17-18 using the 16.0
    # cache (no 14/15 cache to isolate 13-14 exactly; consumers filter to their
    # window with their own introduced-version data).
    in16 = _load_cache_set("16.0")
    buckets = defaultdict(list)   # output band -> rows
    for (cat, kind, name, fw, b), e in agg_rows.items():
        if cat != "FRAMEWORK":
            continue
        ob = ("13-16" if _full(kind, name) in in16 else "17-18") if b == "13+" else b
        st = agg.carried_status(reg, kind, name, fw)
        buckets[ob].append((len(e["strong"]), len(e["apps"]), st, fw, kind, name, ",".join(sorted(e["apps"]))))
    for ob, rows in buckets.items():
        rows.sort(key=lambda t: (0 if t[2] in agg.GAP_STATUS else (2 if t[2] == "n/a-A5" else 1), -t[0], -t[1], t[3], t[5]))
        with open(os.path.join(CORPUS, f"band-{ob}.tsv"), "w") as fh:
            fh.write("strong\tapps\tblocker\tcarried\tframework\tkind\tname\tapplist\n")
            for s, a, st, fw, kind, name, al in rows:
                # launch-blocker: a strong (hard-linked) gap => dyld aborts pre-main if absent
                lb = "LAUNCH-BLOCK" if (s >= 1 and st in agg.GAP_STATUS) else ""
                fh.write(f"{s}\t{a}\t{lb}\t{st}\t{fw}\t{kind}\t{name}\t{al}\n")

def top_rows(bands, gaps_only=True, n=40):
    out = []
    for (cat, kind, name, fw, band), e in agg_rows.items():
        if cat != "FRAMEWORK" or band not in bands:
            continue
        st = agg.carried_status(reg, kind, name, fw)
        if gaps_only and st not in agg.GAP_STATUS:
            continue
        out.append((len(e["strong"]), len(e["apps"]), st, band, fw, kind, name, sorted(e["apps"])))
    out.sort(key=lambda t: (-t[0], -t[1], t[3], t[4], t[6]))
    return out[:n]

write_band_files()
g7, c7, n7 = band_tally("FRAMEWORK")
R = os.path.join(CORPUS, "corpus-report.md")
with open(R, "w") as f:
    w = f.write
    w("# App-corpus priority report v3 — 10 OSS apps, demand vs stock iOS 6.0\n\n")
    w(f"**Corpus ({len(apps)} apps, self-built OSS release IPAs, arm64, cryptid 0):** " + ", ".join(apps) + ".\n\n")
    w("**Method:** name-based (arch-independent). demand = {symbols imported across every Mach-O in the bundle, `nm -m`} − {stock iOS 6.0 exports} − {symbols the app's own bundle defines/exports}. The last term drops intra-app and bundled-3rd-party symbols even when a name collides with an Apple *private* class (e.g. Session bundles WebRTC.framework, so its RTC* are not counted as system). Each survivor is attributed to home framework + introduction band via a dyld cache ladder 6.0→7.0.1→10.3.4→12.0→18.0 (canonical `dyld.load()`); the 18.0 tier catches iOS13+ system demand (\"13+\", beyond current backports) so residual is now ~0. weak/strong from `nm -m`; carried-status from Backports 7-10's registry export.\n\n")
    w("**Scope:** classes + constants (link-time symbols). Methods/properties are runtime-dispatched (invisible to nm) → covered by Katabasis `sel` rows. Metal marked `n/a-A5` (A5 devices never ran Metal; `MTLCreateSystemDefaultDevice()` returns nil). SYSCALL/RUNTIME route to Katabasis.\n\n")
    w("## Actionable backport demand (bands 7–12) — distinct FRAMEWORK class+constant\n\n")
    w("| band | route | GAP | carried | n/a-A5 |\n| --- | --- | --- | --- | --- |\n")
    for b in ("7", "8-10", "11-12"):
        w(f"| {b} | {agg.BAND_ROUTE[b]} | {g7[b]} | {c7[b]} | {n7[b]} |\n")
    w(f"| **7–12 total** | | **{g7['7']+g7['8-10']+g7['11-12']}** | **{c7['7']+c7['8-10']+c7['11-12']}** | **{n7['7']+n7['8-10']+n7['11-12']}** |\n")
    # launch-blocker tally: strong gaps that abort dyld pre-main if absent
    lb = defaultdict(int)
    for (cat, kind, name, fw, band), e in agg_rows.items():
        if cat != "FRAMEWORK" or band not in ("7", "8-10", "11-12"):
            continue
        if len(e["strong"]) >= 1 and agg.carried_status(reg, kind, name, fw) in agg.GAP_STATUS:
            lb[band] += 1
    w(f"\n**LAUNCH-BLOCKERS (strong/hard-linked gaps, bands 7–12):** {lb['7']+lb['8-10']+lb['11-12']} of the {g7['7']+g7['8-10']+g7['11-12']} gaps are strong — a missing hard-linked symbol aborts dyld before main, so the app never starts (proven: iSH won't launch without NSUserActivity). These are the load-gating set: apps stay dead until they exist (or Katabasis weak-binds them). The rest are `#available`-guarded and degrade to nil.\n")
    w(f"\n**Frontier (band 13+, beyond current backports):** {g7['13+']} distinct system class+constant demands introduced iOS 13–18 — real for the \"all apps\" goal but out of current 7–12 scope.\n\n")
    w("## Top gaps, bands 7–12, most-apps-first\n")
    w("`LB` = LAUNCH-BLOCKER: a strong (hard-linked) gap — if absent, dyld aborts before main and the app never starts (proven on iPad2: iSH won't launch without NSUserActivity). All-weak gaps (blank) degrade to nil gracefully. Katabasis is separately weak-binding uncovered classrefs so the long tail degrades instead of hard-failing.\n\n```\n")
    w(f"{'LB':2} {'str':>3} {'app':>3}  {'carried':11} {'band':6} {'framework':22} {'kind':6} name\n")
    for s, a, st, band, fw, kind, name, al in top_rows(("7", "8-10", "11-12")):
        lb = "LB" if s >= 1 else "  "
        w(f"{lb} {s:>3} {a:>3}  {st:11} {band:6} {fw:22} {kind:6} {name}\n")
    w("```\n\n## Cross-check vs Katabasis translator (class agreement)\n\n")
    w("| app | corpus classes | katabasis classes | agree |\n| --- | --- | --- | --- |\n")
    for app in apps:
        mine = set(r["name"] for r in store["apps"][app]["demand"] if r["kind"] == "class")
        k = kata.get(app, set())
        both = mine & k
        w(f"| {app} | {len(mine)} | {len(k) if k else '-'} | {len(both) if k else '-'} |\n")
print("wrote", R)
print("bands 7-12 gaps:", g7['7']+g7['8-10']+g7['11-12'], " 13+ frontier:", g7['13+'])
