#!/usr/bin/env python3
"""Selector-level corpus demand (methods/properties on classes iOS 6 already has).

Per app: the ObjC selector STRINGS in the bundle (__TEXT,__objc_methname across
every Mach-O) that are NOT in the stock iOS 6.0 selector universe
(selectors_armv7.txt) => "new" selectors (added >=7.0, or app/3rd-party private).
Aggregated by corpus app-count. Cross-app frequency (>=2 apps) denoises app-private
names (unlikely shared across unrelated apps). Each new selector is annotated
against the current registry's method rows -[Class sel] to give framework:class:status
where catalogued (that's the F+UIKit + decided info; introduced-release lives in the
registry JSON on the consumer side, not in the flat export).

CAVEATS to state: __objc_methname mixes referenced and app-defined selectors (otool
can't resolve __objc_selrefs on chained-fixup arm64), so this over-approximates;
frequency>=2 and the registry join filter it. Not class-bound except via the registry
match. Precise per-class resolved selectors come from Katabasis runtime collect.

Usage: python3 selector-demand.py [extract|report]
  extract : (re)build per-app selector caches (slow: otool over all bundle binaries)
  report  : aggregate + annotate + write selector-demand-7-10.tsv (default)
"""
import os, re, subprocess, sys, json
from collections import defaultdict

# corpus/ is DATA, in the durable location CHARON_CORPUS_ROOT addresses (default coordination/),
# independent of this script's own location. See tools/corpus/README.md.
CORPUS_ROOT = os.environ.get("CHARON_CORPUS_ROOT") or os.path.join(
    os.path.expanduser("~"), "Git", "projects", "ios", "coordination")
CORPUS = os.path.join(CORPUS_ROOT, "corpus")
if not os.path.isdir(CORPUS):
    sys.exit("selector-demand.py: no corpus/ data directory found at %s. Set CHARON_CORPUS_ROOT to "
              "the directory that contains corpus/." % CORPUS)
CACHE_DIR = os.path.join(CORPUS, "selcache")
SEL60 = os.path.join(os.path.expanduser("~"), ".charon", "dyld", "6.0", "selectors_armv7.txt")
REG = os.environ.get("CHARON_REGISTRY_TSV", "/private/tmp/charon-registry-export/carried-registry.tsv")
APPS = ["ish","ppsspp","pojav","provenance","delta","utm","aidoku","yattee","session","telegram"]

def bundle_selectors(appdir):
    sels = set()
    for root, _d, files in os.walk(appdir):
        for name in files:
            if name.endswith((".png",".plist",".nib",".car",".json",".strings",".storyboardc")):
                continue
            p = os.path.join(root, name)
            try:
                if b"Mach-O" not in subprocess.run(["file", p], capture_output=True).stdout:
                    continue
                out = subprocess.run(["otool","-v","-s","__TEXT","__objc_methname",p],
                                     capture_output=True, text=True).stdout
            except Exception:
                continue
            for line in out.splitlines():
                m = re.match(r"^[0-9a-f]{8,}\s+(\S.*)$", line)
                if m:
                    sels.add(m.group(1).strip())
    return sels

def extract():
    os.makedirs(CACHE_DIR, exist_ok=True)
    for app in APPS:
        base = os.path.join(CORPUS, app, "extracted", "Payload")
        d = None
        if os.path.isdir(base):
            for e in os.listdir(base):
                if e.endswith(".app"):
                    d = os.path.join(base, e); break
        if not d:
            continue
        sels = bundle_selectors(d)
        json.dump(sorted(sels), open(os.path.join(CACHE_DIR, app + ".json"), "w"))
        print(f"{app}: {len(sels)} selectors cached", flush=True)
    print("EXTRACT-DONE", flush=True)

def registry_selectors():
    """selector -> list of (framework, class, status) from -[Class sel] / +[Class sel] method rows."""
    idx = defaultdict(list)
    if not os.path.exists(REG):
        return idx
    with open(REG) as f:
        next(f, None)
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) < 3:
                continue
            fw, api, status = p[0], p[1], p[2]
            m = re.match(r"[-+]\[(\S+)\s+(.+)\]$", api)
            if m:
                idx[m.group(2)].append((fw, m.group(1), status))
    return idx

def report():
    universe = set(l.rstrip("\n") for l in open(SEL60))
    regsel = registry_selectors()
    app_sel = {}
    for app in APPS:
        p = os.path.join(CACHE_DIR, app + ".json")
        if os.path.exists(p):
            app_sel[app] = set(json.load(open(p)))
    freq = defaultdict(set)
    for app, sels in app_sel.items():
        for s in sels - universe:
            freq[s].add(app)
    rows = sorted(freq.items(), key=lambda kv: -len(kv[1]))
    FUI = {"Foundation", "UIKit", "UIFoundation", "CoreFoundation"}
    out = os.path.join(CORPUS, "selector-demand-7-10.tsv")
    with open(out, "w") as f:
        f.write("apps\tselector\tregistry_matches(framework:class:status)\tapplist\n")
        for sel, apps in rows:
            anno = ";".join(f"{fw}:{cls}:{st}" for fw, cls, st in regsel.get(sel, []))
            f.write(f"{len(apps)}\t{sel}\t{anno}\t{','.join(sorted(apps))}\n")
    # F+UIKit-matched view (selector matches a registry method row in F/UIKit), by app count
    fui_rows = []
    for sel, apps in rows:
        m = [(fw, cls, st) for fw, cls, st in regsel.get(sel, []) if fw in FUI]
        if m:
            fui_rows.append((len(apps), sel, m, sorted(apps)))
    # "kind" heuristic: a selector whose ONLY registry classes are protocols the app
    # IMPLEMENTS (*Delegate/*DataSource/*Observer) is a harmless-if-absent callback
    # (framework just won't call it), not a method the app SENDS. Flag so consumers
    # prioritise SENT methods. Definitive sent/implements split = Katabasis runtime collect.
    def is_impl(m):
        return all(cls.endswith(("Delegate", "DataSource", "Observer")) for _fw, cls, _st in m)
    outf = os.path.join(CORPUS, "selector-demand-FUIKit.tsv")
    with open(outf, "w") as f:
        f.write("apps\tkind\tselector\tframework:class:status\tapplist\n")
        # sent-likely first, then by app count
        for n, sel, m, apps in sorted(fui_rows, key=lambda t: (is_impl(t[2]), -t[0])):
            f.write(f"{n}\t{'impl?' if is_impl(m) else 'send?'}\t{sel}\t{';'.join(f'{fw}:{cls}:{st}' for fw,cls,st in m)}\t{','.join(apps)}\n")
    print(f"# {len(app_sel)} apps; {len(rows)} new selectors (not in 6.0). Full: {out}")
    print(f"# F+UIKit-registry-matched: {len(fui_rows)} selectors -> {outf}")
    print(f"# TOP 'send?' (app calls on a system class; not a delegate it implements):")
    for n, sel, m, apps in sorted([r for r in fui_rows if not is_impl(r[2])], key=lambda t: -t[0])[:30]:
        print(f"  {n:>2}  {sel:44} {';'.join(f'{fw}:{cls}:{st}' for fw,cls,st in m)}")
    print(f"# TOP F+UIKit-registry-matched new selectors by app-count (framework:class:status):")
    for n, sel, m, apps in fui_rows[:60]:
        tag = ";".join(f"{fw}:{cls}:{st}" for fw, cls, st in m)
        print(f"  {n:>2}  {sel:52} {tag}")

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "report"
    (extract if cmd == "extract" else report)()
