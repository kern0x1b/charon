#!/bin/sh
# run.sh — the PORT's CGImageMetadata against the HOST's own ImageIO, case by case, with a mutation
# planted to show the comparison can go red.
#
# WHY TWO BINARIES AND NOT ONE: a function has one name in both libraries. Linking the port's object and
# the host's ImageIO into one program cannot happen (the linker sees the same definition twice), so each
# build answers the same cases and run.sh compares the two outputs line by line. What the port's answers
# come from the port is proved in the PORT build itself, not assumed: cases.m's PORTONLY binding record
# reads dladdr() for every function this slice carries and fails if any of them is still ImageIO's.
#
# WHAT IT IS NOT: it is not tests/backports/host/imageio/run.sh, which links the host's ImageIO on both
# sides of every one of its five checks and so compares the host with itself. Nothing in this tree compared
# the port's CGImageMetadata with anything before this file.
#
# A difference is only allowed where known-differences.txt declares it, with the case name spelled exactly.
# An undeclared difference fails; a declared difference that stops differing fails too, because then the
# declaration is stale and a reader would trust a difference that is no longer there.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
port=$root/packages/a/apple-backports/Graphics
build=${BUILD:-$root/.agent-work/runs/imageio-metadata}
mkdir -p "$build"

# THE OBJECT LIST IS A FILE, so a band extends this harness instead of forking it, and a band on disk that
# the list does not name is a band nothing would check. The check for that is asserted, by planting a name
# the list does not have and asking again.
objects=$here/objects.txt
[ -f "$objects" ] || { echo "FAIL  no objects.txt beside run.sh"; exit 1; }
files=""
while read -r f <&3 || [ -n "$f" ]; do
  [ -f "$port/$f" ] || { echo "FAIL  objects.txt names $f and there is no $port/$f"; exit 1; }
  files="$files $port/$f"
done 3< "$objects"
files=${files# }
[ -n "$files" ] || { echo "FAIL  objects.txt names no object"; exit 1; }

coverage_missing() {  # $1 = a list file; prints the objects on disk that it does not name
  ls "$port"/ImageIOMetadata*.m | xargs -n1 basename | sort > "$build/ondisk.txt"
  sort "$1" > "$build/listed.txt"
  comm -23 "$build/ondisk.txt" "$build/listed.txt"
}
miss=$(coverage_missing "$objects")
[ -z "$miss" ] || { echo "FAIL  an object is on disk and NOT in objects.txt, so nothing would check it:"; echo "$miss" | sed 's/^/    /'; exit 1; }
{ grep -v '^ImageIOMetadata7\.m$' "$objects" || true; } > "$build/objects-minus-one.txt"
case "$(coverage_missing "$build/objects-minus-one.txt")" in
  *ImageIOMetadata7.m*) : ;;
  *) echo "FAIL  the coverage check did not detect ImageIOMetadata7.m removed from the list"; exit 1 ;;
esac
echo "  COVERAGE: an object on disk and not in objects.txt is detected, and is named"

# THE PORT BUILD: its own objects plus the name objects the cases ask for by symbol (the prefixes of the
# namespaces are 7.0 names the release does not export, so they come from the port), and ImageIO itself
# for the namespace constants iOS 6 does export. A definition in an object wins over one in a dylib, which
# is what the port relies on at run time, and cases.m proves it with dladdr.
# shellcheck disable=SC2086  # $files is a LIST and must word-split
xcrun clang -w -DCHARON_PORT -fobjc-arc -I"$port" $files "$here/cases.m" \
  -framework Foundation -framework CoreFoundation -framework ImageIO -o "$build/port" 2>"$build/port.log" || {
  echo "BUILD  port"; head -5 "$build/port.log" | sed 's/^/    /'; exit 1; }
xcrun clang -w -DCHARON_HOST -fobjc-arc "$here/cases.m" \
  -framework Foundation -framework CoreFoundation -framework ImageIO -o "$build/host" 2>"$build/host.log" || {
  echo "BUILD  host"; head -5 "$build/host.log" | sed 's/^/    /'; exit 1; }

"$build/port" > "$build/port.out" 2>"$build/port.err" || { echo "FAIL  the port build raised"; head -5 "$build/port.err" | sed 's/^/    /'; exit 1; }
"$build/host" > "$build/host.out" 2>"$build/host.err" || { echo "FAIL  the host build raised"; head -5 "$build/host.err" | sed 's/^/    /'; exit 1; }

# PORTONLY records are the port's own guards: they exist on the port side and must not on the host's, and
# they are dropped from both before the comparison so a port-only line cannot read as a difference.
portonly=$(grep -c '^PORTONLY' "$build/port.out" || true)
hostonly=$(grep -c '^PORTONLY' "$build/host.out" || true)
[ "$portonly" -gt 0 ] || { echo "FAIL  the port printed no PORTONLY record, so its guards are not being asked"; exit 1; }
[ "$hostonly" -eq 0 ] || { echo "FAIL  the host printed $hostonly PORTONLY records; they are the port's guards"; exit 1; }
binding=$(sed -n 's/^PORTONLY binding\t//p' "$build/port.out")
case "$binding" in
  *'=imageio,'*) echo "FAIL  a function this slice carries is still ImageIO's, not the port's: $binding"; exit 1 ;;
  *'=port'*) ;;
  *) echo "FAIL  the binding record did not name every function: $binding"; exit 1 ;;
esac
echo "  BINDING: every function this slice carries resolves to the port's object"
grep -v '^PORTONLY' "$build/port.out" > "$build/port.cmp"
grep -v '^PORTONLY' "$build/host.out" > "$build/host.cmp"

n=$(wc -l < "$build/port.cmp" | tr -d ' ')
h=$(wc -l < "$build/host.cmp" | tr -d ' ')
[ "$n" -gt 0 ] || { echo "FAIL  no case printed anything"; exit 1; }
[ "$n" -eq "$h" ] || { echo "FAIL  the two builds printed $n and $h records, so the comparison would pair different cases"; exit 1; }

diff -u "$build/host.cmp" "$build/port.cmp" > "$build/diff.txt" || true
# a line of the diff that starts with '-' is a record the two builds answer differently
grep '^-' "$build/diff.txt" | grep -v '^---' | sed 's/^-\([^-].*\)$/\1/' | cut -f1 | sort -u > "$build/differing-cases.txt"
differing=$(wc -l < "$build/differing-cases.txt" | tr -d ' ')
declared=0
if [ -f "$here/known-differences.txt" ]; then
  # a case NAME carries a space ("tag unknown-ns-no-prefix"), so the ends are trimmed and the middle is not
  grep -v '^#' "$here/known-differences.txt" | grep -v '^[[:space:]]*$' | cut -d'#' -f1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | sort -u > "$build/declared.txt"
  declared=$(wc -l < "$build/declared.txt" | tr -d ' ')
fi
echo "  COMPARED: $n cases, $differing differ, $declared declared in known-differences.txt"
# a declared difference that no longer differs is stale, and a reader would go on trusting it
if [ -s "$build/declared.txt" ]; then
  stale=$(comm -23 "$build/declared.txt" "$build/differing-cases.txt")
  [ -z "$stale" ] || { echo "FAIL  declared as differing and no longer differing:"; echo "$stale" | sed 's/^/    /'; exit 1; }
fi
undeclared=$(comm -13 "$build/declared.txt" "$build/differing-cases.txt")
[ -z "$undeclared" ] || { echo "FAIL  the port differs from the host on a case nobody declared:"; echo "$undeclared" | sed 's/^/    /'; exit 1; }
if [ "$differing" -eq 0 ]; then echo "  GREEN: every case answers what the host answers"; fi

# THE MUTATION: the port's own source changed, the same cases asked again, and the comparison must notice.
# Without it a harness that compares nothing would print GREEN above and this file would be worthless.
plant=$build/plant
rm -rf "$plant"; mkdir -p "$plant"
cp "$here/cases.m" "$plant/cases.m"
# shellcheck disable=SC2086
for f in $files; do cp "$f" "$plant/$(basename "$f")"; done
target=$plant/$(basename $(echo $files | cut -d' ' -f1))
# the default prefix of a public namespace is a table entry; changing one entry must move the answer
sed -i '' "s/table\[7\].prefix = kCGImageMetadataPrefixTIFF;/table[7].prefix = CFSTR(\"charon-plant\");/" "$target"
hit=$(grep -c "charon-plant" "$target" || true)
[ "$hit" -eq 1 ] || { echo "FAIL  the mutation changed nothing (the pattern is stale)"; exit 1; }
plantfiles=""
for f in $plant/*.m; do
  [ "$f" = "$plant/cases.m" ] && continue
  plantfiles="$plantfiles $f"
done
# shellcheck disable=SC2086
xcrun clang -w -DCHARON_PORT -fobjc-arc -I"$port" $plantfiles "$plant/cases.m" \
  -framework Foundation -framework CoreFoundation -framework ImageIO -o "$build/plantbin" 2>"$build/plant.log" || {
  echo "BUILD  the mutated port"; head -5 "$build/plant.log" | sed 's/^/    /'; exit 1; }
"$build/plantbin" > "$build/plant.out" 2>/dev/null || { echo "FAIL  the mutated port build raised"; exit 1; }
grep -v '^PORTONLY' "$build/plant.out" > "$build/plant.cmp"
if diff -q "$build/host.cmp" "$build/plant.cmp" > /dev/null; then
  echo "  NOT NOTICED  changing a namespace's default prefix and the comparison did not see it"; exit 1
fi
echo "  MUTATION: a changed default prefix is noticed, so the comparison can go red"
echo "imageio-metadata: $n cases compared, $differing declared differences, mutation RED"
exit 0