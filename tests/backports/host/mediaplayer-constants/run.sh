#!/bin/sh
# The port's MediaPlayer constants against Apple's own, in one process, with a mutant per constant.
#
# Each run: the port's two objects are compiled with every constant name renamed to charonHost_*, Apple's
# own MediaPlayer answers for the unrenamed name beside it, and the two tables are diffed. A name the port
# does not define is a LINK ERROR, and a run that compared nothing is a failure.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
port=$root/packages/a/apple-backports/MediaPlayer
build=${BUILD:-$root/.agent-work/runs/mediaplayer-constants}
mkdir -p "$build"
names_seen=0

# DISCOVERED, not listed: the band objects are one file per release and a hardcoded pair meant a new band
# had to be added in four places at once. Sorted, so the object order is the same on every machine.
files=$(ls "$port"/MediaPlayerConstants*.m | sort)
[ -n "$files" ] || { echo "no MediaPlayerConstants*.m in $port"; exit 1; }
echo "  band objects: $(echo "$files" | wc -l | tr -d ' ')"
grep -h '^extern NSString \*const ' $files | sed 's/^extern NSString \*const //; s/;$//' > "$build/strings.txt"
n=$(wc -l < "$build/strings.txt" | tr -d ' ')
d=$(grep -hc '^NSString \*const ' $files | paste -sd+ - | bc)
[ "$d" -eq "$n" ] || { echo "$n constants are declared and $d are defined - a name is declared without a value"; exit 1; }

# WHICH ORACLE JUDGES WHICH NAME is DERIVED, never listed. The host is asked first for every name; the ones
# it has no answer for are the ones a RELEASE CACHE must judge. Deriving it means a new constant the host cannot judge
# is picked up automatically, and a planted name proves the cache reader fails rather than returning
# nothing - a reader that silently returned nothing is how these two would have been carried unverified.
#
# THE RELEASE IS 7.0's armv7 CACHE, and the reader for it is named by the reader itself: an image of 32 bits
# has 32-bit pointers and no flags above an address, which tools/cfconst.py cannot read in place, and it
# refuses such an image BY NAME and names the other reader in that refusal. So the routing below is not a
# constant written down, it is that refusal, and it is checked: if the shared-cache reader stops refusing
# this image, or stops naming the extracted-image reader, the run stops rather than carrying on with the
# reader this image may no longer need.
CF=$root/tools/cfconst.py
CF32=$root/tools/cfconst/cache32.py
IMG=/System/Library/Frameworks/MediaPlayer.framework/MediaPlayer
CACHE_ROOT=${CACHE_ROOT:-$HOME/.charon/dyld}
CACHE=$CACHE_ROOT/7.0/dyld_shared_cache_armv7
: > "$build/oracle.txt"
: > "$build/cache.txt"
probe="$build/probe.m"
# The probe is written by python, not by shell printf: printf ate the backslashes and produced a probe
# that did not compile, which is a worse way to learn a quoting rule than to write the bytes directly.
python3 - "$build/strings.txt" "$probe" <<'PROBE'
import sys
names = [l.strip() for l in open(sys.argv[1]) if l.strip()]
src = ['#import <Foundation/Foundation.h>', '#import <dlfcn.h>', '#include <stdio.h>',
       'int main(void){@autoreleasepool{',
       'void *h=dlopen("/System/Library/Frameworks/MediaPlayer.framework/MediaPlayer",RTLD_LAZY);',
       'if(!h){fprintf(stderr,"no framework\\n");return 2;}',
       'const char *n[]={']
src += ['  "%s",' % x for x in names]
src += ['  0};',
        'for(int k=0;n[k];k++){ if(dlsym(h,n[k])) printf("H %s\\n", n[k]); }',
        'return 0;}}']
open(sys.argv[2],'w').write('\n'.join(src) + '\n')
PROBE
xcrun clang -fobjc-arc -w "$probe" -framework Foundation -o "$build/probe" 2>"$build/probe.log" || {
  echo "BUILD  the probe did not compile"; tail -3 "$build/probe.log" | sed 's/^/    /'; exit 1; }
"$build/probe" > "$build/host-has.txt"
# THE READER MUST EXIST. The path was cwd-relative, so from the case directory the reader was not found,
# its stderr was discarded, and the control below "passed" on a program that had never run. Both readers
# are named here, because which one reads this image is the refusal below's answer and not a constant.
[ -f "$CF" ] || { echo "CACHE-ORACLE  the shared-cache reader is not there: $CF"; exit 1; }
[ -f "$CF32" ] || { echo "CACHE-ORACLE  the extracted-image reader is not there: $CF32"; exit 1; }
[ -f "$CACHE" ] || { echo "CACHE-ORACLE  no held release cache at $CACHE, so no name the host cannot judge"; echo "      can be judged at all. Set CACHE_ROOT to the directory holding the dyld caches."; exit 1; }
# WHICH READER, ASKED. One call to the shared-cache reader for a name the image certainly does not carry:
# its refusal is what says the image is 32-bit and which reader reads it, and the check is that the refusal
# is still that one - the previous version of this test asked for the planted name and matched on wording
# ("not exported by the image") the reader has never printed, so the control passed on a refusal about the
# image's WIDTH and proved nothing about a name.
wide=$(python3 "$CF" "$CACHE" "$IMG" CharonNoSuchPlantedName 2>&1 || true)
case "$wide" in
  *"$(basename "$CF32")"*) : ;;
  *) echo "CACHE-ORACLE  the shared-cache reader did not refuse this image by naming the extracted-image reader,"
     echo "      so the reader chosen below is not the one it names:"; printf '%s\n' "$wide" | head -2 | sed 's/^/    /'; exit 1;;
esac
# THE EXTRACTION, the way that refusal says to read it: dyld.lua's own extract() writes the image out of
# the cache, and the 32-bit reader walks that image's symbol table. tools/cache-extract.lua checks that it
# wrote a non-empty file, because a caller that went on to read an image that was never written would be
# reading nothing - which is the shape of failure this whole control exists to catch.
image=$build/MediaPlayer
rm -f "$image"
xmake lua "$root/tools/cache-extract.lua" "$root/modules" "$CACHE" "$IMG" "$image" > "$build/extract.log" 2>&1 || {
  echo "CACHE-ORACLE  the MediaPlayer image of $CACHE did not extract:"; tail -3 "$build/extract.log" | sed 's/^/    /'; exit 1; }
sed 's/^/  /' "$build/extract.log"
# THE NEGATIVE CONTROL MUST BE THE READER S OWN REFUSAL, not merely a non-zero status. A missing program
# also exits non-zero, so a status-only control cannot tell "refused a planted name" from "never ran": the
# reader s own words are required, and its stderr is KEPT rather than discarded so the text is checkable.
# The refusal is now "not an exported symbol of this image", which is the line the reader prints AND the
# status it exits with; both are asked for, because the 32-bit reader used to print the line and exit 0.
ctl=$(python3 "$CF32" "$image" CharonNoSuchPlantedName 2>&1) && {
  echo "CACHE-ORACLE  the extracted-image reader answered for a planted name, so it cannot be trusted to fail here"; exit 1; }
case "$ctl" in
  *"not an exported symbol of this image"*) : ;;
  *) echo "CACHE-ORACLE  the extracted-image reader did not refuse a planted name in its own words, so this proves nothing:"
     printf '%s\n' "$ctl" | head -2 | sed 's/^/    /'; exit 1;;
esac
while read -r nm <&3; do
  if grep -qx "H $nm" "$build/host-has.txt"; then
    printf 'host\t%s\n' "$nm" >> "$build/oracle.txt"
  else
    v=$(python3 "$CF32" "$image" "$nm" 2>"$build/cf-$nm.log" | awk -F'\t' '{print $3}') || v=""
    [ -n "$v" ] || { echo "CACHE-ORACLE  $nm: the host has no such symbol and no held release exports it, so nothing can judge it"
       sed 's/^/    /' "$build/cf-$nm.log"; exit 1; }
    printf 'cache\t%s\t%s\n' "$nm" "$v" >> "$build/oracle.txt"
  fi
done 3< "$build/strings.txt"
echo "  oracles: $(grep -c '^host' "$build/oracle.txt") judged by the host, $(grep -c '^cache' "$build/oracle.txt") by a release cache"

# the differential is a template and the three generated pieces come from ONE pass over the port's own
# extern list. They were built by two separate pipelines before, and they disagreed about the LAST name:
# calls.h invoked a check that checks.h had not defined. Two things derived separately from one source is
# the same shape as the -D double rename, so they are now derived together or not at all.
: > "$build/decls.h"; : > "$build/checks.h"; : > "$build/calls.h"
while read -r name <&3; do
  or=$(awk -F'\t' -v n="$name" '$2==n{print $1}' "$build/oracle.txt")
  cv=$(awk -F'\t' -v n="$name" '$2==n{print $3}' "$build/oracle.txt")
  [ -n "$or" ] || { echo "BUILD  $name has no oracle"; exit 1; }
  printf 'extern NSString *const %s;\nextern NSString *const charonHost_%s;\n' "$name" "$name" >> "$build/decls.h"
  if [ "$or" = cache ]; then cvlit=$(printf '%s' "$cv" | sed 's/"/\\"/g')
  else cvlit=""; fi
  printf 'static void charonCheck_%s(void) { charonCompareString(@"%s", charonHost_%s, (NSString *const *)dlsym(g_handle, "%s"), "%s", %s%s%s); }\n' \
    "$name" "$name" "$name" "$name" "$or" "$([ "$or" = cache ] && printf '"%s"' "$cvlit" || printf 'NULL')" >> "$build/checks.h"
  printf '    charonCheck_%s();\n' "$name" >> "$build/calls.h"
  names_seen=$((names_seen + 1))
done 3< "$build/strings.txt"
[ "$names_seen" -eq "$n" ] || { echo "expected $n names in the generated pieces, got $names_seen"; exit 1; }
{ sed -n '1,/@@DECLS@@/p' "$here/differential.m" | sed '$d'
  cat "$build/decls.h"
  sed -n '/@@DECLS@@/,/@@CHECKS@@/p' "$here/differential.m" | sed '1d;$d'
  cat "$build/checks.h"
  sed -n '/@@CHECKS@@/,/@@CALLS@@/p' "$here/differential.m" | sed '1d;$d'
  cat "$build/calls.h"
  sed -n '/@@CALLS@@/,$p' "$here/differential.m" | sed '1d'
} > "$build/differential.m"
# THE SYNTAX STEP, before the link, so a scoping or quoting error is a compile error naming its line and
# not a truncated link diagnostic. A message-length and caret setting is the pipeline's, not the tool's.
xcrun clang -fsyntax-only -fmessage-length=0 -fno-caret-diagnostics -fobjc-arc \
  -I"$root/packages/a/apple-backports" "$build/differential.m" 2>"$build/syntax.log" || {
    echo "BUILD  the generated differential does not compile:"; grep "error:" "$build/syntax.log" | head -4 | sed 's/^/    /'; exit 1; }

green=0; red=0

run_case() {   # $1 = output tag, $2.. = the object sources to compile with the renames
  out=$1; shift
  renames=""
  while read -r rn <&4; do renames="$renames -D$rn=charonHost_$rn"; done 4< "$build/strings.txt"
  case "$renames" in *" -D"*) ;; *) echo "BUILD  $out: no renames were built, so the port objects would carry the UNPREFIXED names"; return 1;; esac
  objs=""
  k=0
  for src in "$@"; do
    k=$((k+1))
    xcrun clang -fobjc-arc -w $renames -I"$root/packages/a/apple-backports" -c "$src" -o "$build/$out-$k.o" \
      2>"$build/$out-$k.log" || { echo "BUILD  $out: $src did not compile"; tail -3 "$build/$out-$k.log" | sed 's/^/    /'; return 1; }
    objs="$objs $build/$out-$k.o"
  done
  # The generated differential declares the charonHost_* names ITSELF, so compiling it under the SAME -D
  # renames is a double rename and the -D wins: #define NAME charonHost_NAME collides with the extern the
  # template already emits. The port's objects keep the -D; the differential does not.
  xcrun clang -fobjc-arc -w -I"$root/packages/a/apple-backports" "$build/differential.m" $objs \
    -framework Foundation -o "$build/$out.bin" 2>"$build/$out.link" || {
      echo "BUILD  $out FAILED to link - a name the port does not define is a link error here"
      tail -3 "$build/$out.link" | sed 's/^/    /'; return 1; }
  # NOT `|| true`: a link that produced no binary must fail here, or the loop reaches its own
  # -x check having been told the build worked.
  if [ -x "$build/$out.bin" ]; then "$build/$out.bin" > "$build/$out.txt" 2>&1 || true; fi
}

# THE GREEN RUN: the real sources
run_case green $files || { echo "the real build did not link"; exit 1; }
ok=$(grep -c '^OK' "$build/green.txt" || true)
dis=$(grep -c '^DIFFERS' "$build/green.txt" || true)
noor=$(grep -c '^NO-ORACLE' "$build/green.txt" || true)
echo "  GREEN: $ok of $n agree, and the planted control is reported:"
grep -E '^(MISSING|NO-ORACLE)' "$build/green.txt" | sed 's/^/    /'
# THE AGREEMENT IS ASSERTED, not printed. The binary s own exit status cannot carry it, because the
# PLANTED CONTROL ALWAYS FAILS BY DESIGN, so the process always exits non-zero and that bit is worth
# nothing. Reviewer ec0142a3 changed one port value and this printed "12 of 13 agree" and exited 0.
[ "$noor" -eq 0 ] || { echo "FAIL  $noor constants were compared by no oracle at all"; exit 1; }
[ "$dis" -eq 0 ] || { echo "FAIL  the real build disagrees with Apple on $dis constants, by name:"
  grep '^DIFFERS' "$build/green.txt" | cut -f2 | sed 's/^/    /'; exit 1; }
[ "$ok" -eq "$n" ] || { echo "FAIL  only $ok of $n constants agree with Apple, and the other $((n-ok)) are not OK:"
  grep -E '^(DIFFERS|MISSING|NO-ORACLE|NULL|PORT-NULL)' "$build/green.txt" | cut -f1,2 | sed 's/^/    /'; exit 1; }
# WHICH ORACLE JUDGED WHICH NAME is printed, so a name no oracle judged is visible rather than green.
grep '^OK' "$build/green.txt" | awk -F'\t' '$4=="oracle=cache" {printf "    judged by a RELEASE CACHE\t%s\t%s\n", $2, $3}'

# THE WHOLE FAMILY, NOT ONE FILE. The check compares every implemented constant row in
# registry/MediaPlayer/*.json against every constant the port's objects define, in BOTH directions. The
# defect it exists for is one a single-file series cannot see: a row in mpitemconstants.json left
# `implemented` with nothing behind it while the series that touched absent_MediaPlayer.json passed. The
# media harness above cannot catch that either - it asserts declared == defined WITHIN the files it can
# see, and a file that is missing from the commit is invisible to it, so it passed at 30 of 30 against 31
# rows once already.
reg=$root/packages/a/apple-backports/registry/MediaPlayer
python3 "$here/rows-vs-objects.py" "$reg" "$port" | sed 's/^/ /'

# THE CONTROL: on the REAL tree the comparison must pass, and it must have examined something. A checker
# that compared nothing passes silently, so a nonzero count is part of what is asserted here.
ctl=$(python3 "$here/rows-vs-objects.py" "$reg" "$port" 2>&1) || { echo "FAIL  the real tree does not satisfy the row/object comparison"; exit 1; }
case "$ctl" in *"examined, so nothing was proved"*) echo "FAIL  the comparison examined nothing"; exit 1;; esac
examined=$(printf '%s\n' "$ctl" | sed -n 's/.*[^0-9]\([0-9][0-9]*\) implemented constant rows.*/\1/p')
[ "${examined:-0}" -gt 0 ] || { echo "FAIL  the comparison reported ${examined:-0} rows examined"; exit 1; }
echo "  rows-vs-objects: CONTROL passed on the real tree, $examined rows examined"

# THE MUTANT: the same comparison with ONE OBJECT FILE REMOVED must FAIL, and must name a constant. A
# check that cannot fail here would have passed on the real tree for the wrong reason, which is the same
# class of mistake as a control that only asserted a nonzero exit.
drop=$build/rows-dropped
rm -rf "$drop"; mkdir -p "$drop"
for f in "$port"/MediaPlayerConstants*.m; do cp "$f" "$drop/"; done
victim=$(ls "$drop" | head -1)
rm "$drop/$victim"
lost=$(python3 "$here/rows-vs-objects.py" "$reg" "$drop" 2>&1) && {
  echo "FAIL  dropping $victim did not fail the comparison, so the check cannot see a missing object"; exit 1; }
case "$lost" in
  *UNBACKED*) : ;;
  *) echo "FAIL  dropping $victim failed the comparison but named no unbacked constant:"; printf '%s\n' "$lost" | head -3 | sed 's/^/    /'; exit 1;;
esac
echo "  rows-vs-objects: MUTANT caught - removing $victim was reported, by name"

# THE MUTANTS: one per constant. A mutant directory must hold BOTH objects, because a port's constants
# live in more than one object and a mutant that changes the 9.0 object still has to LINK against the
# 8.2 one. The untouched object is copied unchanged. A build that produces no binary is a FAILURE and not
# a skip: a loop that continues past a broken build reports "0 mutants" as a pass, which is how this
# harness claimed coverage it never had.
i=0; ran=0
while read -r name <&3; do
  i=$((i+1))
  rm -rf "$build/src-m$i" "$build/m$i"; mkdir -p "$build/src-m$i"
  for f in $files; do
    cp "$f" "$build/src-m$i/$(basename "$f")"
  done
  # change exactly this one constant, in whichever object holds it
  for f in $files; do
    b=$(basename "$f")
    [ -f "$build/src-m$i/$b" ] || continue
    if grep -q "^NSString \*const $name = " "$build/src-m$i/$b"; then
        # the mutation is an awk one-liner keyed on the exact name, with the variables EXPANDED: a
        # single-quoted sed BRE left $name and $i literal, matched nothing, and produced a copy
        # identical to the original - which the loop then correctly reported as NOT NOTICED
        sed "s%^NSString \*const $name = @\"[^\"]*\";%NSString *const $name = @\"charon-mutant-$i\";%" \
          "$build/src-m$i/$b" > "$build/src-m$i/$b.tmp" && mv "$build/src-m$i/$b.tmp" "$build/src-m$i/$b"
        # and the copy must DIFFER FROM THE ORIGINAL BY EXACTLY ONE LINE, or it is not a mutation
        c=$(diff "$f" "$build/src-m$i/$b" | grep -c "^>" || true)
        [ "$c" -eq 1 ] || { echo "BUILD  mutant $i: $b differs from the original in $c lines, not 1 - the mutation did not apply"; exit 1; }
        d=$(grep -c "^NSString \*const " "$build/src-m$i/$b")
        o=$(grep -c "^NSString \*const " "$f")
        [ "$d" -eq "$o" ] || { echo "BUILD  mutant $i: $f.m has $d definitions and the original has $o"; exit 1; }
    fi
  done
  # BOTH files, explicitly, and a file that is not there is an error rather than a shorter command
  muts=""
  for f in $files; do
    b="$build/src-m$i/$(basename "$f")"
    [ -f "$b" ] || { echo "BUILD  mutant $i: $b is missing"; exit 1; }
    muts="$muts $b"
  done
  # shellcheck disable=SC2086
  run_case "m$i" $muts || { echo "BUILD  mutant $i did not build"; exit 1; }
  [ -x "$build/m$i.bin" ] || { echo "BUILD  mutant $i produced no binary"; exit 1; }
  ran=$((ran+1))
  if grep -q '^DIFFERS' "$build/m$i.txt"; then
    echo "  RED  mutant $i changes $name: $(grep -m1 '^DIFFERS' "$build/m$i.txt" | cut -f2)"
    red=$((red+1))
  else
    echo "  NOT NOTICED  mutant $i changes $name and the comparison did not see it"; exit 1
  fi
done 3< "$build/strings.txt"

echo "mediaplayer-constants: $n constants, $ran mutants run, $red RED"
[ "$ran" -eq "$n" ] || { echo "  only $ran of $n mutants ran"; exit 1; }
[ "$red" -eq "$n" ] || { echo "  only $red of $n mutants were noticed"; exit 1; }
miss=$(grep -c '^MISSING' "$build/green.txt" || true)
[ "$miss" -eq 1 ] || { echo "FAIL  $miss names are MISSING, and exactly one is the planted control"; exit 1; }
grep '^MISSING' "$build/green.txt" | grep -q 'MPNoSuchConstantForTheControl' || { echo "FAIL  the planted control was not the name reported missing"; exit 1; }
grep -q '^NO-ORACLE' "$build/green.txt" && { echo "a constant was compared by nothing"; exit 1; }
j=$(grep -c '^OK' "$build/green.txt" || true)
[ "$j" -eq "$n" ] || { echo "  only $j of $n constants were judged by an oracle"; exit 1; }
exit 0
