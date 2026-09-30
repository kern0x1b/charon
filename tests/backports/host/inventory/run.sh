#!/bin/sh
# The GENERIC host-inventory differential, for any framework with a spec. It sits beside the per-framework
# harnesses rather than in place of them: FileProvider has its own differential.m/run.sh on main and that
# work is not replaced by this, only joined.
#
#   ./run.sh FRAMEWORK
#
# Three controls, each of which exists because the version without it reported a clean run over nothing:
#   1. a class prefix that matches nothing exits 3 and the run FAILS - an empty comparison is not green;
#   2. the host's class count is compared with the count the spec expects, so a host that answers less is
#      visible instead of merely smaller;
#   3. every `never_call` name is checked against the BUILT OBJECT, not the source tree: the port does not
#      keep .o files in its source tree, so a check that read $pkg/*.o was reading an empty set and passing.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
spec=${1:?usage: run.sh FRAMEWORK}
json=$root/tools/corpus/spec/$spec.json
[ -f "$json" ] || { echo "FAIL  no spec at $json"; exit 1; }
prefix=$(python3 -c "import json;print(json.load(open('$json'))['class_prefix'])")
expect=$(python3 -c "import json;print(json.load(open('$json')).get('expect_classes',''))")
pkg=$root/packages/a/apple-backports/$(python3 -c "import json;print(json.load(open('$json')).get('package',''))")
build=${BUILD:-$root/.agent-work/runs/inventory}
mkdir -p "$build"
[ -n "$prefix" ] || { echo "FAIL  the spec has no class_prefix, so the probe would match every class on the host"; exit 1; }
link=""
for fw in $(python3 -c "import json;print(' '.join(json.load(open('$json')).get('frameworks',[])))"); do
  [ -n "$fw" ] || { echo "FAIL  the spec names no frameworks, so the host cannot be asked about them"; exit 1; }
  link="$link -framework $fw"
done
xcrun clang -w -fobjc-arc "$here/inventory.m" -framework Foundation $link -o "$build/inventory" 2>"$build/c.log" || {
  echo "BUILD  the inventory probe"; head -3 "$build/c.log" | sed 's/^/    /'; exit 1; }
"$build/inventory" "$prefix" "$spec" > "$build/host.txt" 2>&1 || {
  echo "FAIL  the host registers nothing under $prefix, so this comparison would be empty"; exit 1; }
got=$(sed -n 's/^TOTALS.*classes=\([0-9]*\).*/\1/p' "$build/host.txt")
gotp=$(sed -n 's/^TOTALS.*protocols=\([0-9]*\).*/\1/p' "$build/host.txt")
echo "  HOST: $prefix -> $got classes, $gotp protocols"
[ "$got" -gt 0 ] || { echo "FAIL  the host answered 0 classes"; exit 1; }
if [ -n "$expect" ]; then
  [ "$got" -eq "$expect" ] || { echo "FAIL  the spec expects $expect classes and the host answered $got"; exit 1; }
  echo "  COUNT: $got classes, as the spec expects"
fi
# the port's objects are BUILT here, so the never_call check reads symbols rather than an empty set
rm -rf "$build/obj"; mkdir -p "$build/obj"
n=0
for f in "$pkg"/${prefix#NS}*.m "$pkg"/[A-Z]*.m; do
  [ -f "$f" ] || continue
  xcrun clang -fobjc-arc -w -I "$pkg" -c "$f" -o "$build/obj/$(basename "$f" .m).o" 2>"$build/o.log" || {
    echo "BUILD  $(basename "$f")"; head -3 "$build/o.log" | sed 's/^/    /'; exit 1; }
  n=$((n+1))
done
[ "$n" -gt 0 ] || { echo "FAIL  no object was built, so a never_call check would compare nothing"; exit 1; }
echo "  PORT: $n objects built and read"
python3 - "$json" "$build/obj" "$root/tests/backports" <<'PY'
import json, subprocess, sys, glob, os
import re
import re
spec = json.load(open(sys.argv[1])); objdir = sys.argv[2]
objs = glob.glob(os.path.join(objdir, '*.o'))
if not objs:
    print('FAIL  no object to read'); sys.exit(1)
syms = ''
for o in objs:
    syms += subprocess.run(['nm', '-a', o], capture_output=True, text=True).stdout
def exact_symbol_present(name):
    return any(line.rstrip().endswith(' ' + name) for line in syms.splitlines() if line.strip())
missing, total = [], 0
for piece in spec['pieces']:
    for name in piece.get('never_call', []):
        total += 1
        if not exact_symbol_present(name):
            missing.append(name)
if missing:
    print('FAIL  carried-for-callable but NOT in the built object: %s' % ', '.join(missing)); sys.exit(1)
print('  CARRIED: %d never_call names present as an exact nm symbol in the built object' % total)
print('  NOT CHECKED: whether any harness calls them - see the comment above, that half is not implemented')
PY
echo "inventory: $spec green"
