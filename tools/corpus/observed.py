#!/usr/bin/env python3
"""Observed-on-device layer, and the owner-unknown selector list.

1. OBSERVED: parse Katabasis's on-device API-gap logs (flag xl-exp-null-missing, runtime
   ea23bfb): every message no class implements is logged once as `<+|->Class selector` and
   answered by a null object so the app keeps running; `XLNullObject` lines are echoes of the
   same message and are ignored. Classes starting with `_` are private internal probes
   (WebKit forwarders, XPC), reported apart from public API gaps.
   Output corpus/observed-device.tsv, cross-referenced with the static crash list.

2. OWNER-UNKNOWN: selectors the corpus apps send that stock 6.0 lacks and that appear in a
   later release's string pool, but that the SDK dump does not know (protocol members whose
   availability the dump did not record, e.g. UICoordinateSpace). Name-only evidence, so it is
   kept OUT of the main ranking. Property-attribute strings, type encodings and private
   (underscore) names are filtered. The owner is unknown, so Metal cannot be excluded by owner:
   a NAME heuristic sets `likely_metal`, and it is INCOMPLETE (it misses blend-factor and
   sampler setters such as setAlphaBlendOperation:, setMagFilter:), so much of the head is still
   Metal. Read it by eye; the rows that stand out are the UICoordinateSpace family.
   Output corpus/crash-demand-owner-unknown.tsv.

Known blind spot, not fixable here: a selector NAME that stock 6.0 has on an unrelated class
(coordinateSpace exists on a private MapKit class) is subtracted by the name universe and so
hidden. Recovering it owner-aware needs a complete 6.0 class inventory; the one available
lacks class methods/categories for many ordinary selectors (blackColor, new), so the attempt
returned mostly junk. Only the on-device log catches those.
"""
import csv, glob, json, os, re, sys
from collections import defaultdict

# corpus/ is DATA, in the durable location CHARON_CORPUS_ROOT addresses (default coordination/),
# independent of this script's own location. See tools/corpus/README.md.
CORPUS_ROOT = os.environ.get("CHARON_CORPUS_ROOT") or os.path.join(
    os.path.expanduser("~"), "Git", "projects", "ios", "coordination")
CORPUS = os.path.join(CORPUS_ROOT, "corpus")
if not os.path.isdir(CORPUS):
    sys.exit("observed.py: no corpus/ data directory found at %s. Set CHARON_CORPUS_ROOT to the "
              "directory that contains corpus/." % CORPUS)
LOGS = "/Users/alexanderhavrysh/Git/projects/ios/emulator-lab/recompile/device-logs"
MINOS = {"ish": (11, 0), "ppsspp": (11, 0), "pojav": (12, 2), "provenance": (16, 0),
         "delta": (14, 0), "utm": (14, 0), "aidoku": (15, 0), "yattee": (14, 0),
         "session": (15, 0), "telegram": (11, 0)}
METAL = re.compile(r"(atIndex:|Encoder|PipelineState|Threadgroup|drawPrimitives|PixelFormat|colorAttachments|"
                   r"newFunctionWithName|setVertex|setFragment|setBuffer:|setTexture:|CompletedHandler|commandBuffer|"
                   r"texture2DDescriptor|renderPassDescriptor|newBufferWith|newTextureWith|newLibrary|newCommandQueue|drawable)")
JUNK = re.compile(r'^(T.?[,@#qQBcCsSiIlLfd^*{\[].*,.*|[TV][@#qQBcCsSiIlLfd^*{]\S*|[vBcCsSiIlLqQfd@#:^*{}\[\]0-9]+)$')

def main():
    universe = set(l.rstrip("\n") for l in open(os.path.expanduser("~/.charon/dyld/6.0/selectors_armv7.txt")))
    sdk = json.load(open(os.path.join(CORPUS, "sdk-introduced.json")))
    sdk_sel = set()
    for api, (k, v, fw) in sdk.items():
        m = re.match(r"^[-+]\[\w+ (.+)\]$", api)
        if m: sdk_sel.add(m.group(1))
        elif k == "property" and "." in api:
            n = api.split(".", 1)[1]; sdk_sel.update({n, "set" + n[0].upper() + n[1:] + ":", "is" + n[0].upper() + n[1:]})
    reg = {}
    for l in open(os.environ.get("CHARON_REGISTRY_TSV", "/private/tmp/charon-registry-export/carried-registry.tsv")):
        p = l.rstrip("\n").split("\t")
        if len(p) >= 3: reg[p[1]] = p[2]
    reg_sel = {}
    for api, st in reg.items():
        m = re.match(r"^[-+]\[\w+ (.+)\]$", api)
        if m and (m.group(1) not in reg_sel or st in ("implemented", "inert")):
            reg_sel[m.group(1)] = st

    def status_for(sign, cls, sel):
        for k in ("%s[%s %s]" % (sign, cls, sel), "-[%s %s]" % (cls, sel), "+[%s %s]" % (cls, sel)):
            if k in reg:
                return reg[k]
        base = sel[3].lower() + sel[4:] if sel.startswith("set") and len(sel) > 3 and sel.endswith(":") else sel
        for k in ("%s.%s" % (cls, sel), "%s.%s" % (cls, base.rstrip(":"))):
            if k in reg:
                return reg[k]
        if sel in reg_sel:
            return reg_sel[sel] + " (on another class: check it is this one)"
        return "no row"
    # caches/sel/ lives at coordination/corpus/caches/, the durable home it was moved to this
    # session (was in the system temp path before that): an explicit override first, then the real
    # location, then fail loud instead of crashing on a FileNotFoundError that names only the wrong
    # path and nothing about where the right one actually is.
    _CACHES_SEL_CANDIDATES = [p for p in [
        os.environ.get("CHARON_CACHES_DIR"),
        os.path.join(CORPUS, "caches"),
    ] if p]
    _CACHES_SEL = next((p for p in _CACHES_SEL_CANDIDATES if os.path.isdir(os.path.join(p, "sel"))), None)
    if _CACHES_SEL is None:
        sys.exit("observed.py: no caches/sel/ directory found (looked in %s). Set CHARON_CACHES_DIR "
                  "to the directory that contains sel/." % ", ".join(_CACHES_SEL_CANDIDATES))
    strs = {r: set(l.rstrip("\n") for l in open(os.path.join(_CACHES_SEL, "sel", r + ".strings")))
            for r in ("7.0.1", "10.3.4", "12.0")}
    cnt = defaultdict(set)
    for app in MINOS:
        c = set(json.load(open(os.path.join(CORPUS, "selcache", app + ".json"))))
        d = set(json.load(open(os.path.join(CORPUS, "defcache", app + ".json"))))
        for s in c - d:
            cnt[s].add(app)

    # ---- 2. owner-unknown list
    ou = []
    for s, apps in cnt.items():
        if s in universe or s in sdk_sel or s.startswith("_") or JUNK.match(s) or "," in s:
            continue
        rel = next((r for r in ("7.0.1", "10.3.4", "12.0") if s in strs[r]), None)
        if not rel or len(apps) < 3:
            continue
        bound = {"7.0.1": (7, 1), "10.3.4": (10, 3), "12.0": (12, 0)}[rel]
        crash = sorted(a for a in apps if MINOS[a] >= bound)
        ou.append((len(crash), len(apps), s, {"7.0.1": "<=7", "10.3.4": "8-10", "12.0": "11-12"}[rel], crash,
                   "yes" if METAL.search(s) else "no"))
    ou.sort(key=lambda t: (-t[0], -t[1], t[2]))
    p = os.path.join(CORPUS, "crash-demand-owner-unknown.tsv")
    with open(p, "w") as f:
        f.write("unguarded_callers\tapps\tselector\tfirst_release_string_seen\tlikely_metal(name heuristic)\tregistry_any_owner\tcallers\n")
        for cr, n, s, b, apps, mt in ou:
            f.write(f"{cr}\t{n}\t{s}\t{b}\t{mt}\t{reg_sel.get(s, 'no row')}\t{','.join(apps)}\n")
    ou_set = {t[2] for t in ou}

    # ---- main static list, for the cross-reference
    main_sel = {}
    for r in list(csv.reader(open(os.path.join(CORPUS, "crash-demand-top.tsv"), encoding="utf-8"), delimiter="\t"))[1:]:
        api = re.sub(r" \(\+\d+ owners\)$", "", r[2])
        m = re.match(r"^[-+]\[\w+ (.+)\]$", api)
        if m: main_sel[m.group(1)] = r[0]
        elif "." in api and not api.startswith(("-", "+", "_")):
            n = api.split(".", 1)[1]
            for s in (n, "set" + n[0].upper() + n[1:] + ":", "is" + n[0].upper() + n[1:]): main_sel.setdefault(s, r[0])

    # ---- 1. observed
    obs = {}
    run_time = {}                                 # run -> mtime of its newest xl-missing log
    for path in sorted(set(glob.glob(os.path.join(LOGS, "*", "*xl-missing*.log")) + glob.glob(os.path.join(LOGS, "*", "xl-missing.log")))):
        run = os.path.basename(os.path.dirname(path))
        run_time[run] = max(run_time.get(run, 0), os.path.getmtime(path))
        for line in open(path, errors="replace"):
            m = re.match(r"^([+-])(\S+) (.+)$", line.strip())
            if not m or m.group(2) == "XLNullObject":
                continue
            obs.setdefault((m.group(1), m.group(2), m.group(3)), set()).add(run)
    def app_of(run):
        return run.split("-")[0]
    latest = {}
    for run, t in run_time.items():
        a = app_of(run)
        if a not in latest or t > run_time[latest[a]]:
            latest[a] = run
    def device_state(runs):
        apps = {app_of(r) for r in runs}
        parts = []
        for a in sorted(apps):
            n_runs = sum(1 for r in run_time if app_of(r) == a)
            if n_runs == 1:
                parts.append("%s: one run so far" % a)
            elif latest[a] in runs:
                parts.append("%s: still missing in the latest run (%s)" % (a, latest[a]))
            else:
                parts.append("%s: NOT seen in the latest run (%s): fixed on device, or not reached" % (a, latest[a]))
        return "; ".join(parts)
    out = os.path.join(CORPUS, "observed-device.tsv")
    with open(out, "w") as f:
        f.write("run\tkind\tclass\tselector\tclass_visibility\tin_6.0_names\tin_static_main_list\tin_owner_unknown_list\tcorpus_apps_sending\tregistry_status_now\tdevice_state\tnote\n")
        for (sign, cls, sel), runs in sorted(obs.items(), key=lambda kv: (kv[0][1].startswith("_"), kv[0][1], kv[0][2])):
            vis = "private (internal probe)" if cls.startswith("_") else "public"
            note = ""
            if sel in universe and vis == "public":
                note = "name exists on another 6.0 class: hidden from the static list by name subtraction"
            elif sel in ou_set:
                note = "found by the owner-unknown list (SDK dump has no row)"
            f.write("\t".join([",".join(sorted(runs)), "class msg" if sign == "+" else "instance msg", cls, sel, vis,
                               "yes" if sel in universe else "no", main_sel.get(sel, "no"),
                               "yes" if sel in ou_set else "no", str(len(cnt.get(sel, ()))),
                               status_for(sign, cls, sel), device_state(runs), note]) + "\n")
    print(f"owner-unknown selectors (>=3 apps): {len(ou)} -> {p}")
    print(f"observed missing messages: {len(obs)} -> {out}")
    for (sign, cls, sel), runs in sorted(obs.items(), key=lambda kv: (kv[0][1].startswith("_"), kv[0][1])):
        vis = "private" if cls.startswith("_") else "PUBLIC"
        print(f"  {vis:7} {sign}{cls} {sel}  | 6.0 name:{sel in universe} static:{main_sel.get(sel, 'no')} owner-unknown:{sel in ou_set} apps:{len(cnt.get(sel, ()))}")

if __name__ == "__main__":
    main()
