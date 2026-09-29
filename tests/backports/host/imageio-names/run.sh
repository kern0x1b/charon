#!/bin/sh
# The PORT's ImageIO name constants against the HOST's own ImageIO, and a mutant per constant.
#
# The port's object is COMPILED, LINKED into a private copy of portread.c, and READ through dlsym, so the
# value compared against Apple's is the port's own and not a string this script already had. The previous
# version of this harness read ImageIONames130.m for NAMES only, wrote the host's answers to green.txt and
# then grepped that file for a mutant marker it could never contain: changing all 22 CFSTR values still
# printed 22 of 22 and exited 0. A comparison that cannot go red proves nothing.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
port=$root/packages/a/apple-backports/Graphics
build=${BUILD:-$root/.agent-work/runs/imageio-names}
mkdir -p "$build"
obj=${PORT_OBJ:-$build/ImageIONames130.o}

files=$(ls "$port"/ImageIONames130.m)
grep -h '^extern CFStringRef const ' $files | sed 's/^extern CFStringRef const //; s/;$//' > "$build/names.txt"
n=$(wc -l < "$build/names.txt" | tr -d ' ')
d=$(grep -h '^CFStringRef const ' $files | wc -l | tr -d ' ')
[ "$n" -gt 0 ] && [ "$d" -eq "$n" ] || { echo "FAIL  $n declared and $d defined"; exit 1; }
echo "  constants: $n"

xcrun clang -w "$here/probe.c" -framework CoreFoundation -framework ImageIO -o "$build/probe" 2>"$build/probe.log" || {
  echo "BUILD  probe"; head -3 "$build/probe.log" | sed 's/^/    /'; exit 1; }
xcrun clang -w -I"$root/packages/a/apple-backports" -c "$files" -o "$obj" 2>"$build/port.log" || {
  echo "BUILD  the port object"; head -3 "$build/port.log" | sed 's/^/    /'; exit 1; }

value_of() {  # $1 = program, $2 = symbol: the value it READS, empty if it did not read one
  "$1" "$2" 2>/dev/null | sed -n 's/^  VALUE //p'
}

# compare the port's read values against the host's, for every name
compare() {  # $1 = label, $2 = the port object to link, $3 = expect (agree|differ)
  xcrun clang -w "$here/portread.c" "$2" -framework CoreFoundation -o "$build/pr" 2>"$build/pr.log" || {
    echo "BUILD  $1: portread did not link"; head -3 "$build/pr.log" | sed 's/^/    /'; exit 1; }
  agree=0; differ=0
  : > "$build/differs.txt"
  while read -r name <&3; do
    p=$(value_of "$build/pr" "$name"); h=$(value_of "$build/probe" "$name")
    if [ -z "$p" ]; then echo "FAIL  $1: the port reader returned nothing for $name"; exit 1; fi
    if [ "$p" = "$h" ]; then agree=$((agree+1)); else differ=$((differ+1)); echo "$name" >> "$build/differs.txt"; fi
  done 3< "$build/names.txt"
  echo "  $1: $agree agree, $differ differ"
  case "$3" in
    agree)  [ "$differ" -eq 0 ] || { echo "FAIL  $1: the port disagrees with Apple on $(head -1 "$build/differs.txt")"; exit 1; } ;;
    differ) [ "$differ" -gt 0 ] || { echo "FAIL  $1: nothing differed, so the comparison cannot be seen to fail"; exit 1; } ;;
  esac
}

# THE GREEN RUN: the port's own object, linked and read
compare "GREEN (port vs host)" "$obj" agree
echo "  GREEN: all $n of the port's values read through the port's own object equal Apple's"

# THE CONTROL on the planted name: the host reader must report a name it does not have
"$build/probe" kCGImagePropertyNoSuchNameForTheControl > "$build/ctl.txt" 2>&1 || true
grep -q 'VERDICT missing' "$build/ctl.txt" || { echo "FAIL  the planted name was not reported missing"; exit 1; }
echo "  CONTROL: the planted name is reported missing by the host reader"

# THE TWO PLANTS THE REVIEWER USED, kept as permanent checks: the comparison must notice a wrong value
# whether ALL of them are wrong or ONE is. A comparison that only notices the total cannot see a single
# bad constant, and the previous harness noticed neither.
pdir=$build/plants
rm -rf "$pdir"; mkdir -p "$pdir"
cp "$files" "$pdir/all.m"; cp "$files" "$pdir/one.m"
sed -i '' 's%CFSTR("\([^"]*\)")%CFSTR("charon-plant-all")%g' "$pdir/all.m"
first=$(sed -n 's/^extern CFStringRef const \([A-Za-z0-9_]*\);/\1/p' "$files" | head -1)
sed -i '' "s%^CFStringRef const $first = CFSTR(\"[^\"]*\");%CFStringRef const $first = CFSTR(\"charon-plant-one\");%" "$pdir/one.m"
xcrun clang -w -I"$root/packages/a/apple-backports" -c "$pdir/all.m" -o "$pdir/all.o" 2>/dev/null
xcrun clang -w -I"$root/packages/a/apple-backports" -c "$pdir/one.m" -o "$pdir/one.o" 2>/dev/null
compare "PLANT all 22 wrong" "$pdir/all.o" differ
compare "PLANT one wrong ($first)" "$pdir/one.o" differ
echo "  PLANTS: the comparison goes red on all-wrong and on one-wrong"

sh "$here/merged-sample.sh" || { echo "FAIL  the merged-row control failed"; exit 1; }

# THE MUTANTS: one per constant, each COMPILED, LINKED and READ
i=0; ran=0; red=0
while read -r name <&3; do
  i=$((i+1))
  rm -rf "$build/m$i"; mkdir -p "$build/m$i"
  f="$build/m$i/$(basename "$files")"
  sed "s%^CFStringRef const $name = CFSTR(\"[^\"]*\");%CFStringRef const $name = CFSTR(\"charon-mutant-$i\");%" "$files" > "$f"
  c=$(diff "$files" "$f" | grep -c '^>' || true)
  [ "$c" -eq 1 ] || { echo "FAIL  mutant $i: the copy differs in $c lines, not 1"; exit 1; }
  xcrun clang -w -I"$root/packages/a/apple-backports" -c "$f" -o "$build/m$i/m.o" 2>"$build/m$i/c.log" || {
    echo "BUILD  mutant $i did not compile"; head -3 "$build/m$i/c.log" | sed 's/^/    /'; exit 1; }
  xcrun clang -w "$here/portread.c" "$build/m$i/m.o" -framework CoreFoundation -o "$build/m$i/pr" 2>"$build/m$i/l.log" || {
    echo "BUILD  mutant $i did not link"; head -3 "$build/m$i/l.log" | sed 's/^/    /'; exit 1; }
  ran=$((ran+1))
  if [ "$(value_of "$build/m$i/pr" "$name")" = "$(value_of "$build/probe" "$name")" ]; then
    echo "  NOT NOTICED  mutant $i changes $name and the comparison did not see it"; exit 1
  fi
  red=$((red+1))
done 3< "$build/names.txt"
echo "imageio-names: $n constants, $ran mutants run, $red RED"
[ "$ran" -eq "$n" ] && [ "$red" -eq "$n" ] || { echo "  incomplete"; exit 1; }
exit 0
