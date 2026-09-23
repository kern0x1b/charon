#!/usr/bin/env python3
"""Scan live (non-Swift, recompilable) ObjC apps from Katabasis's target set into a
SEPARATE live store (keeps the canonical 10-app store untouched), arm64-aware for
their fat armv7+arm64 bundles. Then emit the band-11-12 Foundation/CoreData/Security
/CFNetwork slice merged with the corpus's Swift-gated demand, tagging live vs gated.

Usage: python3 live-scan.py ingest   # scan the 3 live apps into store-live.json
       python3 live-scan.py fcs      # write merged band-11-12-FCS slice (default)
"""
import os, re, subprocess, sys, json, importlib.util
HERE = os.path.dirname(os.path.realpath(__file__))
# aggregate.py is a NEIGHBOR SCRIPT (found beside this file wherever it is copied to);
# store.json/store-live.json and everything under corpus/ is DATA, in the durable location
# CHARON_CORPUS_ROOT addresses (default coordination/). See tools/corpus/README.md.
spec = importlib.util.spec_from_file_location("agg", os.path.join(HERE, "aggregate.py"))
agg = importlib.util.module_from_spec(spec); spec.loader.exec_module(agg)
CORPUS_ROOT = os.environ.get("CHARON_CORPUS_ROOT") or os.path.join(
    os.path.expanduser("~"), "Git", "projects", "ios", "coordination")
CORPUS = os.path.join(CORPUS_ROOT, "corpus")
if not os.path.isdir(CORPUS):
    sys.exit("live-scan.py: no corpus/ data directory found at %s. Set CHARON_CORPUS_ROOT to the "
              "directory that contains corpus/ (holds store.json, store-live.json)." % CORPUS)

LIVE_STORE = os.path.join(CORPUS, "store-live.json")
LIVE_APPS = {
 "oba":   "/Users/alexanderhavrysh/Git/projects/ios/emulator-lab/recompile/targets/OneBusAway_v2.3.2/Payload/OneBusAway.app",
 "xkcd":  "/Users/alexanderhavrysh/Git/projects/ios/emulator-lab/recompile/targets/xkcd.Open.Source/Payload/xkcd Open Source.app",
 "zebra": "/Users/alexanderhavrysh/Git/projects/ios/emulator-lab/recompile/targets/Zebra-1.1.17/Payload/Zebra.app",
}
FOCUS = {"Foundation","CoreFoundation","CoreData","Security","LocalAuthentication","CFNetwork"}

def scan_arm64(binary):
    try:
        r = subprocess.run(["nm","-arch","arm64","-m",binary], capture_output=True, text=True)
    except Exception:
        return {}, set()
    und, defd = {}, set()
    for line in r.stdout.splitlines():
        toks = line.split()
        try:
            i = toks.index("external")
        except ValueError:
            continue
        if i + 1 >= len(toks):
            continue
        sym = toks[i+1]
        if not sym.startswith("_"):
            continue
        if "(undefined)" in line:
            und[sym] = und.get(sym, True) and ("weak external" in line)
        elif i == 0 or toks[i-1] != "non-external":
            defd.add(sym)
    return und, defd

def ingest():
    agg.scan_symbols = scan_arm64          # arm64-aware for fat bundles
    agg.STORE = LIVE_STORE
    for name, appdir in LIVE_APPS.items():
        if os.path.isdir(appdir):
            agg.ingest(name, appdir)
        else:
            print(f"{name}: MISSING {appdir}")

def fcs():
    reg = agg.load_registry()
    live = json.load(open(LIVE_STORE)) if os.path.exists(LIVE_STORE) else {"apps":{}}
    corpus = json.load(open(agg.STORE if agg.STORE.endswith("store.json") else os.path.join(CORPUS,"store.json")))
    from collections import defaultdict
    rows = defaultdict(lambda: {"live": set(), "gated": set()})
    for src, store in (("live", live), ("gated", corpus)):
        for app, d in store["apps"].items():
            for r in d["demand"]:
                if r.get("cat")!="FRAMEWORK" or r["band"]!="11-12" or r["framework"] not in FOCUS: continue
                if agg.is_swift_mangled(r["name"]): continue
                rows[(r["framework"], r["kind"], r["name"])][src].add(app)
    out = []
    for (fw,kind,name), e in rows.items():
        st = agg.carried_status(reg, kind, name, fw)
        out.append((len(e["live"]), len(e["gated"]), st, fw, kind, name, sorted(e["live"]), sorted(e["gated"])))
    out.sort(key=lambda t: (-t[0], -t[1]))
    p = os.path.join(CORPUS, "band-11-12-FCS.tsv")
    with open(p, "w") as f:
        f.write("live_apps\tgated_apps\tstatus\tframework\tkind\tname\tlive_callers\tgated_callers\n")
        for lv,gt,st,fw,kind,name,lc,gc in out:
            f.write(f"{lv}\t{gt}\t{st}\t{fw}\t{kind}\t{name}\t{','.join(lc)}\t{','.join(gc)}\n")
    print(f"band-11-12 FCS rows: {len(out)}; with LIVE callers: {sum(1 for r in out if r[0]>0)} -> {p}")
    for lv,gt,st,fw,kind,name,lc,gc in [r for r in out if r[0]>0][:30]:
        print(f"  live{lv}/gated{gt} {st:11} {fw:14} {kind:6} {name}  live={lc}")

if __name__ == "__main__":
    (ingest if (len(sys.argv)>1 and sys.argv[1]=="ingest") else fcs)()
