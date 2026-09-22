#!/usr/bin/env python3
"""Corpus API-demand aggregator (name-based, arch-independent).

Modern App Store apps are arm64-only; stock iOS 6.0 has only armv7/armv7s
caches, so demand is measured by NAME: a symbol an app imports that stock 6.0
does not export is a backport candidate. A later cache confirms it is a real
Apple system symbol (not a 3rd-party embedded-framework symbol, which appears in
no Apple cache) and gives its home framework and INTRODUCTION BAND, routing it
to the right backport session.

Cache ladder (from dump-cache.lua), oldest first after the 6.0 baseline:
  6.0      baseline (present here => not a candidate)
  7.0.1    introduced in iOS 7            -> Backports 7-10
  10.3.4   introduced in iOS 8-10.3       -> Backports 7-10 / 10
  12.0     introduced in iOS 11-12        -> Backports 11-12
  (not in any) -> residual: iOS 13+ system OR 3rd-party; excluded from ranking.

Sub-commands:
  ingest <app> <path-to-.app>   scan bundle's Mach-O, classify, merge store.json
  report                        frequency-ranked demand
"""
import json, os, re, subprocess, sys

HERE = os.path.dirname(__file__)
CACHES = os.path.join(HERE, "..", "caches")
STORE = os.path.join(HERE, "store.json")
LADDER = [("7", "7.0.1"), ("8-10", "10.3.4"), ("11-12", "12.0"), ("13+", "18.0")]  # band -> cache stem
BAND_ROUTE = {"7": "Backports 7-10", "8-10": "Backports 7-10/10",
              "11-12": "Backports 11-12", "13+": "beyond current backports"}

def load_cache_tsv(stem):
    """symbol -> framework (first seen); also returns the symbol set."""
    attr = {}
    path = os.path.join(CACHES, stem + ".tsv")
    with open(path) as f:
        for line in f:
            sym, _, fw = line.rstrip("\n").partition("\t")
            if sym and sym not in attr:
                attr[sym] = fw
    return attr

def build_index():
    b60 = set(load_cache_tsv("6.0"))
    ladder = [(band, load_cache_tsv(stem)) for band, stem in LADDER]
    return b60, ladder

def macho_binaries(appdir):
    out = []
    for root, _dirs, files in os.walk(appdir):
        for name in files:
            if name.endswith((".png", ".plist", ".nib", ".car", ".json", ".strings", ".storyboardc")):
                continue
            p = os.path.join(root, name)
            try:
                if b"Mach-O" in subprocess.run(["file", p], capture_output=True).stdout:
                    out.append(p)
            except Exception:
                pass
    return out

def scan_symbols(binary):
    """One nm -m pass. Returns (undefined:{sym:weak}, defined:set).
    weak = imported under #available (NULL-tolerant); strong = hard dep.
    defined = external symbols this binary EXPORTS (used to drop intra-app /
    bundled-3rd-party symbols whose name collides with an Apple private class,
    e.g. Session bundles WebRTC.framework exporting RTC* that also exist in
    Apple's private cached WebRTC)."""
    try:
        r = subprocess.run(["nm", "-m", binary], capture_output=True, text=True)
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
        sym = toks[i + 1]
        if not sym.startswith("_"):
            continue
        if "(undefined)" in line:
            und[sym] = und.get(sym, True) and ("weak external" in line)
        elif i == 0 or toks[i - 1] != "non-external":   # defined external
            defd.add(sym)
    return und, defd

def sym_kind(sym):
    m = re.match(r"_OBJC_(META)?CLASS_\$_(.+)", sym)
    if m:
        return "class", m.group(2)
    return "symbol", sym

# Segment the attributed home into what each demand actually implies:
#   FRAMEWORK - public *.framework API (Foundation/UIKit/WebKit/...) => backport target
#   SYSCALL   - libsystem_kernel => a syscall stock 6.0 lacks (kernel/libsystem shim)
#   SYSLIB    - other libsystem_*/libsqlite3/libcommonCrypto => low-level OS shim
#   RUNTIME   - libobjc/libdyld/libc++/compiler-rt/unwind => Katabasis runtime, NOT a backport
RUNTIME_LIBS = ("libobjc", "libdyld", "libc++", "libc++abi", "libcompiler_rt",
                "libunwind", "libSystem", "libdbm")  # libdbm hosts unwind/compiler-rt exports
def categorize(fw):
    if not fw.endswith(".dylib"):
        return "FRAMEWORK"
    if fw == "libsystem_kernel.dylib":
        return "SYSCALL"
    stem = fw[:-6]
    if any(stem == r or stem.startswith(r) for r in RUNTIME_LIBS):
        return "RUNTIME"
    return "SYSLIB"

def ingest(app, appdir):
    b60, ladder = build_index()
    bins = macho_binaries(appdir)
    U = {}          # symbol -> weak(bool); strong in any binary wins
    defined = set() # symbols the app's own bundle exports (intra-app satisfied)
    for b in bins:
        und, defd = scan_symbols(b)
        for s, w in und.items():
            U[s] = U.get(s, True) and w
        defined |= defd
    demand = {}     # (kind,name) -> {framework, band, cat, weak}
    residual = 0
    bundled = 0
    for s, weak in U.items():
        if s in b60:
            continue
        if s in defined:            # satisfied by the app's own bundle (3rd-party / name collision)
            bundled += 1
            continue
        band = fw = None
        for bnd, attr in ladder:
            if s in attr:
                band, fw = bnd, attr[s]
                break
        if band is None:
            residual += 1           # iOS13+ system or 3rd-party embedded; not ranked
            continue
        kind, name = sym_kind(s)
        # fold metaclass into class; a class is strong if any of its symbols is strong
        cur = demand.get((kind, name))
        if cur is None:
            demand[(kind, name)] = {"framework": fw, "band": band, "cat": categorize(fw), "weak": weak}
        else:
            cur["weak"] = cur["weak"] and weak
    store = json.load(open(STORE)) if os.path.exists(STORE) else {"apps": {}}
    store["apps"][app] = {
        "binaries": len(bins),
        "demand": [{"kind": k, "name": n, "framework": v["framework"], "band": v["band"],
                    "cat": v["cat"], "weak": v["weak"]}
                   for (k, n), v in sorted(demand.items())],
        "residual": residual,
    }
    json.dump(store, open(STORE, "w"), indent=1, sort_keys=True)
    byband = {}
    for v in demand.values():
        byband[v["band"]] = byband.get(v["band"], 0) + 1
    cls = sum(1 for (k, _) in demand if k == "class")
    print(f"{app}: {len(bins)} binaries, {len(demand)} system demands "
          f"({cls} classes, {len(demand)-cls} symbols) "
          f"bands={byband} residual(non-Apple)={residual} bundle-satisfied={bundled}")

# Carried-vs-gap: source of truth is Backports 7-10's registry export (status,
# framework, kind, api, introduced). Classes match by name; constants are stored
# without the leading underscore, so we strip it from our symbol names.
# Fresh registry export from Coordinator at current main (c310e54): framework/api/status.
# Coordinator regenerates on request; ping when a fresh cut is needed (our worktree lags main).
# Coordinator regenerates the shared export after each merge; CHARON_REGISTRY_TSV lets a run read a
# different one (e.g. regenerated straight from origin/main) WITHOUT touching the shared file.
REGISTRY_TSV = os.environ.get("CHARON_REGISTRY_TSV", "/private/tmp/charon-registry-export/carried-registry.tsv")
_STATUS_RANK = {"implemented": 0, "inert": 1, "ignored": 2, "absent": 3}
# Frameworks unreachable on our A5 hardware (iPhone 4S / iPad 2): Metal needs
# A7+, so MTLCreateSystemDefaultDevice() returns nil and apps fall back to GLES;
# backporting the descriptor cluster would be silently wrong. Mark, don't rank.
A5_UNREACHABLE = {"Metal", "MetalKit", "MetalPerformanceShaders", "MetalPerformanceShadersGraph"}

def load_registry():
    reg = {}
    if not os.path.exists(REGISTRY_TSV):
        return reg
    with open(REGISTRY_TSV) as f:
        header = next(f, "")
        # Support both formats: new "framework\tapi\tstatus" and old "status\tframework\tkind\tapi\t..."
        new_fmt = header.startswith("framework\t")
        for line in f:
            p = line.rstrip("\n").split("\t")
            if new_fmt:
                if len(p) < 3:
                    continue
                api, status = p[1], p[2]
            else:
                if len(p) < 4:
                    continue
                status, api = p[0], p[3]
            if api not in reg or _STATUS_RANK.get(status, 9) < _STATUS_RANK.get(reg[api], 9):
                reg[api] = status
    return reg

def carried_status(reg, kind, name, framework):
    if framework in A5_UNREACHABLE:
        return "n/a-A5"
    # Mach-O prepends exactly one underscore to C symbols; strip just that one.
    api = name if kind == "class" else (name[1:] if name.startswith("_") else name)
    # The registry writes a C FUNCTION as `name()` (README: "a function as
    # UIGraphicsBeginImageContextWithOptions()"). A Mach-O symbol carries no parentheses, so looking up the
    # bare name alone silently misses every carried C function and reports it as a gap. Try both spellings.
    for k in (api, api + "()"):
        if k in reg:
            return reg[k]
    return "gap?"   # gap? = undecided/not listed => treat as gap

CAT_ORDER = {"FRAMEWORK": 0, "SYSCALL": 1, "SYSLIB": 2, "RUNTIME": 3}
GAP_STATUS = {"gap?", "absent"}   # not carried today => real priority
def is_swift_mangled(name):
    # Swift symbols (_$s.../_$S...) are Swift-runtime domain, never ObjC backports.
    return name.startswith("_$s") or name.startswith("_$S") or name.startswith("$s") or name.startswith("$S")
def report(only=None):
    store = json.load(open(STORE))
    reg = load_registry()
    agg = {}   # (cat,kind,name,framework,band) -> {apps:set, strong:set}
    for app, d in store["apps"].items():
        for r in d["demand"]:
            if is_swift_mangled(r["name"]):
                continue
            cat = r.get("cat") or categorize(r["framework"])
            if only and cat not in only:
                continue
            key = (cat, r["kind"], r["name"], r["framework"], r["band"])
            e = agg.setdefault(key, {"apps": set(), "strong": set()})
            e["apps"].add(app)
            if not r.get("weak", False):
                e["strong"].add(app)
    def sortkey(kv):
        (cat, kind, name, fw, band), e = kv
        status = carried_status(reg, kind, name, fw)
        gap = 0 if status in GAP_STATUS else 1     # gaps first
        return (CAT_ORDER.get(cat, 9), gap, -len(e["strong"]), -len(e["apps"]), band, fw, name)
    rows = sorted(agg.items(), key=sortkey)
    apps = sorted(store["apps"])
    print(f"# Corpus system-API demand vs stock iOS 6.0  ({len(apps)} apps: {', '.join(apps)})")
    print(f"# carried-status from registry (main 6318a82); gap?=undecided/not-listed=gap; n/a-A5=unreachable Metal")
    print(f"# columns: #apps  strong/weak  carried  band  route  framework  kind  name")
    for (cat, kind, name, fw, band), e in rows:
        status = carried_status(reg, kind, name, fw)
        na = len(e["apps"]); ns = len(e["strong"]); nw = na - ns
        flag = "GAP " if status in GAP_STATUS else "    "
        print(f"{na:>4}  s{ns}/w{nw:<3} {flag}{status:11} {band:6} {BAND_ROUTE.get(band,'?'):18} "
              f"{fw:22} {kind:6} {name}    [{','.join(sorted(e['apps']))}]")

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "report"
    if cmd == "ingest":
        ingest(sys.argv[2], sys.argv[3])
    elif cmd == "report":
        only = set(sys.argv[2].split(",")) if len(sys.argv) > 2 else None
        report(only)
    else:
        print(__doc__)
