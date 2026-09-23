#!/usr/bin/env python3
"""STOPGAP method-level signal (until Katabasis `sel` collect lands).

For each corpus app, extract the ObjC selectors it references (__TEXT,__objc_methname
across every Mach-O in the bundle) and intersect with the selectors of the methods
the backports registry catalogues. Output, grouped by (framework, class): each
catalogued method, its carried-status, and how many apps reference its selector.

HONEST CAVEATS (state these to consumers):
- selref = the app REFERENCES the selector; NOT resolved/unresolved, NOT a proven call.
- a selector is arch-independent but NOT class-bound: one `foo:` can belong to several
  classes, so "selector X referenced by N apps" is coarse. Sessions map it to the
  methods of the class they are implementing. Precise per-class resolved/unresolved
  comes from Katabasis `sel`.
"""
import os, re, subprocess, sys
from collections import defaultdict

# corpus/ is DATA, in the durable location CHARON_CORPUS_ROOT addresses (default coordination/),
# independent of this script's own location. See tools/corpus/README.md.
CORPUS_ROOT = os.environ.get("CHARON_CORPUS_ROOT") or os.path.join(
    os.path.expanduser("~"), "Git", "projects", "ios", "coordination")
CORPUS = os.path.join(CORPUS_ROOT, "corpus")
if not os.path.isdir(CORPUS):
    sys.exit("stopgap-selectors.py: no corpus/ data directory found at %s. Set CHARON_CORPUS_ROOT to "
              "the directory that contains corpus/." % CORPUS)
# Was hardcoded to a dead worktree's own per-session scratchpad
# (claude-501/.../sleepy-rubin-d4242b/.../scratchpad/exports/carried-registry.tsv) -- it still
# existed by luck (per-session temp dirs aren't cleaned immediately) but nothing in this repo
# points at it and it dies with that session's cleanup, silently and without error. Every other
# reader of this export uses the shared path below; aligned to match, still overridable.
REG = os.environ.get("CHARON_REGISTRY_TSV", "/private/tmp/charon-registry-export/carried-registry.tsv")
APPS = ["ish","ppsspp","pojav","provenance","delta","utm","aidoku","yattee","session","telegram"]

def registry_methods():
    """selector -> list of (framework, class, status, introduced)."""
    sel = defaultdict(list)
    for line in open(REG):
        p = line.rstrip("\n").split("\t")
        if len(p) < 5 or p[2] != "method":
            continue
        status, fw, _kind, api, introduced = p[:5]
        m = re.match(r"[-+]\[(\S+)\s+(.+)\]$", api)
        if not m:
            continue
        cls, selector = m.group(1), m.group(2)
        sel[selector].append((fw, cls, status, introduced))
    return sel

def bundle_selectors(appdir):
    seen = set()
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
                    seen.add(m.group(1).strip())
    return seen

def main():
    regsel = registry_methods()
    app_sels = {}
    for app in APPS:
        d = None
        base = os.path.join(CORPUS, app, "extracted", "Payload")
        if os.path.isdir(base):
            for e in os.listdir(base):
                if e.endswith(".app"):
                    d = os.path.join(base, e); break
        if d:
            app_sels[app] = bundle_selectors(d)
            print(f"# {app}: {len(app_sels[app])} referenced selectors", file=sys.stderr)
    # intersect
    rows = []  # (napps, fw, cls, status, selector, apps)
    for selector, entries in regsel.items():
        apps = sorted(a for a, s in app_sels.items() if selector in s)
        if not apps:
            continue
        for fw, cls, status, introduced in entries:
            rows.append((len(apps), fw, cls, status, selector, apps))
    # group by (fw, class), gaps first
    GAP = {"absent","ignored"}   # undecided not present as method rows; absent=known gap
    bycls = defaultdict(list)
    for n, fw, cls, status, selector, apps in rows:
        bycls[(fw, cls)].append((n, status, selector, apps))
    order = sorted(bycls, key=lambda k: -max(x[0] for x in bycls[k]))
    print("# STOPGAP method-level signal — selector referenced by app (coarse, class-unbound; see caveats)")
    print(f"# {len(app_sels)} apps; registry method selectors matched in {len(bycls)} classes\n")
    for (fw, cls) in order:
        ms = sorted(bycls[(fw, cls)], key=lambda x: (-x[0], x[2]))
        print(f"{fw}  {cls}")
        for n, status, selector, apps in ms:
            flag = "GAP" if status in GAP else "   "
            print(f"    {n:>2}  {flag} {status:11} {selector}   [{','.join(apps)}]")

if __name__ == "__main__":
    main()
