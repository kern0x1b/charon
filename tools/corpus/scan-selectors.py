#!/usr/bin/env python3
"""Per app: every selector name the bundle carries (__objc_methname strings -> corpus/selcache/
<app>.json) and every selector the bundle DEFINES (method_t name/types/imp triplets, via
defined-methods.py's own defined() -> corpus/defcache/<app>.json). crash-demand.py computes
sends = carried - universe(iOS 6.0) - defined from these two files; this is the one script that
builds both from a real .app bundle, so the two stay from the same binary by construction
instead of two separately-run tools that could silently drift apart.

Neither half duplicates aggregate.py's ingest()/scan-app.sh: those operate on `nm -m`'s external
symbol table and dyld's own missing-imports check -- the LINKER-visible surface (classes,
protocols, C functions/constants), which is what builds store.json's `demand`. Selector names
(__objc_methname) are never linker symbols at all -- Objective-C messaging resolves them
dynamically, so `nm` never lists one -- an entirely different Mach-O section this script is the
first to read. The Mach-O-binary walk and the `defined()` regex WOULD have been a third and a
second copy of logic aggregate.py and defined-methods.py already have -- both are imported from
there instead of re-implemented, the same importlib pattern sdk-introduced.py already uses for
surface-diff-latest.py.

Verified against the one binary that was reachable all session (iSH, katabasis/targets/iSH/
Payload/iSH.app): both outputs reproduce the existing corpus/selcache/ish.json and
corpus/defcache/ish.json byte-for-byte. Usage:

    python3 scan-selectors.py <app-name> <path-to-.app>
"""
import importlib.util, json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
# corpus/ is DATA, in the durable location CHARON_CORPUS_ROOT addresses (default coordination/),
# independent of this script's own location. aggregate.py/defined-methods.py are NEIGHBOR SCRIPTS,
# found beside this file. See tools/corpus/README.md.
CORPUS_ROOT = os.environ.get("CHARON_CORPUS_ROOT") or os.path.join(
    os.path.expanduser("~"), "Git", "projects", "ios", "coordination")
CORPUS = os.path.join(CORPUS_ROOT, "corpus")
if not os.path.isdir(CORPUS):
    sys.exit("scan-selectors.py: no corpus/ data directory found at %s. Set CHARON_CORPUS_ROOT to "
              "the directory that contains corpus/." % CORPUS)


def _load(modname, filename):
    candidates = [p for p in [
        os.environ.get("CHARON_TOOLS_DIR") and os.path.join(os.environ["CHARON_TOOLS_DIR"], filename),
        os.path.join(HERE, filename),
    ] if p]
    path = next((p for p in candidates if os.path.isfile(p)), None)
    if path is None:
        sys.exit("scan-selectors.py: no %s found (looked in %s). Set CHARON_TOOLS_DIR." %
                  (filename, ", ".join(candidates)))
    spec = importlib.util.spec_from_file_location(modname, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


agg = _load("agg", "aggregate.py")
dm = _load("dm", "defined-methods.py")


def carried_names(binary):
    """Every __objc_methname string the binary's __TEXT carries -- sent OR defined, a name is
    a name regardless. otool -v resolves each entry to (address, string); a bare address with no
    trailing text is a null-byte padding continuation, not a second selector, and is skipped."""
    try:
        out = subprocess.run(["otool", "-v", "-s", "__TEXT", "__objc_methname", binary],
                              capture_output=True, text=True).stdout
    except Exception:
        return set()
    names = set()
    for line in out.splitlines()[2:]:  # skip "<binary>:" and "Contents of (...)" header lines
        parts = line.split(None, 1)
        if len(parts) == 2:
            names.add(parts[1])
    return names


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: scan-selectors.py <app-name> <path-to-.app>")
    app, appdir = sys.argv[1], sys.argv[2]
    bins = agg.macho_binaries(appdir)
    if not bins:
        sys.exit("scan-selectors.py: no Mach-O binaries found under %s" % appdir)
    carried, defined = set(), set()
    for b in bins:
        carried |= carried_names(b)
        defined |= dm.defined(b)
    for sub in ("selcache", "defcache"):
        os.makedirs(os.path.join(CORPUS, sub), exist_ok=True)
    json.dump(sorted(carried), open(os.path.join(CORPUS, "selcache", app + ".json"), "w"))
    json.dump(sorted(defined), open(os.path.join(CORPUS, "defcache", app + ".json"), "w"))
    print(f"{app}: {len(bins)} binaries, {len(carried)} carried selectors, {len(defined)} defined", flush=True)


if __name__ == "__main__":
    main()
