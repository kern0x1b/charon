#!/bin/sh
# protocol-sources.sh — the 6.1.3 gate's protocol step on its own, so a band can run it without the gate.
#
# For every library, the sources modules/apple/backports.lua's protocol_sources() writes are read out of
# the registry the way that function reads it, then compiled for the triple of their rows' minimum, with
# that library's own folder on the include path and the library's flags, against the 16.4 SDK. It is the
# step that caught UIKit's eight trait protocols: the rows were in the registry, the sources were
# generated, and CharonUIKitProtocols.h had never been regenerated to declare them, so
# UIKitBackportsProtocols17.0.m did not compile and nothing before the gate reads that header.
#
# protocol_headers_test.lua is the cheap half of this and runs in the light guard: a row whose protocol is
# declared nowhere the source can see. This is the half no cheap check can make, because a forward
# declaration is correct when the SDK supplies the body and a compile error when it does not:
#
#   error: @protocol is using a forward protocol declaration of 'UICGFloatTraitDefinition'
#
# Usage: protocol-sources.sh <sdk16> <outdir>
#   exit status: the number of sources that did not compile (0 when every one of them compiled)
set -u
SDK=$1
OUT=$2
ROOT=$(cd "$(dirname "$0")/../.." && pwd)   # tests/addon -> the checkout root
# The pinned toolchain of tools/matter-framework.sh, so a run compiles what the gate compiles. $CLANG
# overrides it; the version is a pin, not a preference, and a clang that is not the one the library is
# built with answers a different question.
CLANG=${CLANG:-$HOME/.xmake/packages/l/llvm/23.1.1/6a8c97aaa69241df9ed69ac86f13a045/bin/clang}
[ -x "$CLANG" ] || { echo "protocol-sources: no clang at $CLANG; set CLANG to the pinned one"; exit 2; }
W=${TMPDIR:-/tmp}/charon-protocol-sources
rm -rf "$OUT"; mkdir -p "$OUT/src" "$OUT/obj"
python3 - "$ROOT" "$OUT" <<'PY'
import json, os, re, sys
root, out = sys.argv[1], sys.argv[2]
libraries = []
for line in open(os.path.join(root, "modules", "apple", "backports.lua"), encoding="utf-8"):
    m = re.search(r'name = "([A-Za-z]+Backports)", folder = "([A-Za-z]+)"', line)
    if m:
        libraries.append({"name": m.group(1), "folder": m.group(2)})
written = []
for lib in libraries:
    folder = lib["folder"]
    files = []
    d = os.path.join(root, "packages", "a", "apple-backports", "registry", folder)
    if os.path.isdir(d):
        files += [os.path.join(d, f) for f in sorted(os.listdir(d)) if f.endswith(".json")]
    single = os.path.join(root, "packages", "a", "apple-backports", "registry", folder + ".json")
    if os.path.isfile(single):
        files.append(single)
    bands, floors = {}, {}
    for f in files:
        held = json.load(open(f, encoding="utf-8"))
        entries = held.get("entries") if isinstance(held, dict) else held
        for e in entries or []:
            if e.get("kind") == "protocol" and e.get("status") == "implemented":
                intro = e.get("introduced") or "0"
                bands.setdefault(intro, []).append(e["api"])
                m = e.get("minimum")
                if m and (intro not in floors or tuple(map(int, m.split("."))) > tuple(map(int, floors[intro].split(".")))):
                    floors[intro] = m
    for intro in sorted(bands, key=lambda s: tuple(map(int, s.split(".")))):
        names = sorted(bands[intro])
        target = os.path.join(out, "src", "%sProtocols%s.m" % (lib["name"], intro))
        body = ["// %sProtocols%s.m - written by modules/apple/backports.lua, not by hand." % (lib["name"], intro),
                "#import \"Charon%sProtocols.h\"" % lib["folder"], "",
                "static void charon_%s_protocols(void) __attribute__((used));" % lib["name"],
                "static void charon_%s_protocols(void)" % lib["name"], "{"]
        for n in names:
            body.append("    (void)@protocol(%s);" % n)
        body += ["}", ""]
        open(target, "w", encoding="utf-8").write("\n".join(body))
        written.append({"file": target, "folder": folder, "name": lib["name"],
                        "introduced": intro, "minimum": floors.get(intro, "6.0"), "count": len(names)})
json.dump(written, open(os.path.join(out, "written.json"), "w"), indent=1)
print("%d protocol sources over %d libraries" % (len(written), len({w['folder'] for w in written})))
PY
fail=0
python3 - "$OUT" <<'PY' > "$OUT/plan.txt"
import json, sys
for w in json.load(open(sys.argv[1] + "/written.json")):
    print("%s\t%s\t%s\t%s" % (w["file"], w["folder"], w["minimum"], w["name"]))
PY
while IFS='	' read -r file folder minimum name; do
  base=$(basename "$file" .m)
  target="armv7-apple-ios${minimum}"
  if "$CLANG" -target "$target" -isysroot "$SDK" -fobjc-arc -Os -g0 -Wall \
       -Wno-unguarded-availability-new -Wno-unguarded-availability \
       -I"$ROOT/packages/a/apple-backports/$folder" \
       -c "$file" -o "$OUT/obj/$base.o" 2> "$OUT/obj/$base.diag"; then
    echo "COMPILE ok   $base.m  ($target, $folder)"
  else
    echo "COMPILE FAIL $base.m  ($target, $folder)"
    grep -m3 'error:' "$OUT/obj/$base.diag" | sed 's/^/    /'
    fail=$((fail+1))
  fi
done < "$OUT/plan.txt"
total=$(wc -l < "$OUT/plan.txt" | tr -d ' ')
if [ "$total" = "0" ]; then
    echo "protocol-sources: no protocol source was generated, so nothing was compiled and this run says"
    echo "nothing about the tree; the registry it reads is $ROOT/packages/a/apple-backports/registry and the"
    echo "libraries come from $ROOT/modules/apple/backports.lua"
    exit 2
fi
echo "gate-shape: $total source(s), $fail failed"
exit $fail
