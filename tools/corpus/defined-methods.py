#!/usr/bin/env python3
"""Per app: selectors the bundle DEFINES (method_t entries: name, then types, then imp),
from `otool -arch arm64 -oV` over every Mach-O. A method entry is `name` immediately
followed by a `types` line; ivars carry `type` and properties `attributes`, so they
do not match. Selectors an app defines are override points/callbacks (UIKit calls them,
the app does not send them) -> used to separate SENDS from IMPLEMENTS. Output:
corpus/defcache/<app>.json"""
import json, os, re, subprocess, sys
# corpus/ is DATA (selcache/, defcache/, extracted apps), not this script's own location -- it
# lives in a durable place addressed by CHARON_CORPUS_ROOT (default coordination/), independent of
# wherever this script itself is copied to. See tools/corpus/README.md.
CORPUS_ROOT = os.environ.get("CHARON_CORPUS_ROOT") or os.path.join(
    os.path.expanduser("~"), "Git", "projects", "ios", "coordination")
CORPUS = os.path.join(CORPUS_ROOT, "corpus")
if not os.path.isdir(CORPUS):
    sys.exit("defined-methods.py: no corpus/ data directory found at %s. Set CHARON_CORPUS_ROOT to "
              "the directory that contains corpus/." % CORPUS)
NAME = re.compile(r"^\s+name\s+0x[0-9a-f]+\s+(\S.*)$")
TYPES = re.compile(r"^\s+types\s+0x")
def defined(binary):
    try:
        out = subprocess.run(["otool", "-arch", "arm64", "-oV", binary], capture_output=True, text=True).stdout
    except Exception:
        return set()
    names, pending = set(), None
    for line in out.splitlines():
        m = NAME.match(line)
        if m:
            pending = m.group(1).strip(); continue
        if pending is not None:
            if TYPES.match(line):
                names.add(pending)
            pending = None
    return names
# Guarded so defined() can be imported (scan-selectors.py does exactly this, rather than
# keeping a second copy of this regex) without also running the batch driver below as an
# import side effect.
if __name__ == "__main__":
    os.makedirs(os.path.join(CORPUS, "defcache"), exist_ok=True)
    for app in ["ish","ppsspp","pojav","provenance","delta","utm","aidoku","yattee","session","telegram"]:
        base = os.path.join(CORPUS, app, "extracted", "Payload")
        d = next((os.path.join(base, e) for e in os.listdir(base) if e.endswith(".app")), None) if os.path.isdir(base) else None
        if not d: continue
        s = set()
        for root, _dirs, files in os.walk(d):
            for n in files:
                if n.endswith((".png",".plist",".nib",".car",".json",".strings",".storyboardc")): continue
                p = os.path.join(root, n)
                if b"Mach-O" in subprocess.run(["file", p], capture_output=True).stdout:
                    s |= defined(p)
        json.dump(sorted(s), open(os.path.join(CORPUS, "defcache", app + ".json"), "w"))
        print(f"{app}: {len(s)} defined selectors", flush=True)
    print("DEF-DONE", flush=True)
