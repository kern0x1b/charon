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

files="$port/MediaPlayerConstants90.m $port/MediaPlayerConstants82.m"
grep -h '^extern NSString \*const ' $files | sed 's/^extern NSString \*const //; s/;$//' > "$build/strings.txt"
n=$(wc -l < "$build/strings.txt" | tr -d ' ')
[ "$n" -eq 13 ] || { echo "expected 13 constants, the port declares $n"; exit 1; }

# the differential is a template and the three generated pieces come from ONE pass over the port's own
# extern list. They were built by two separate pipelines before, and they disagreed about the LAST name:
# calls.h invoked a check that checks.h had not defined. Two things derived separately from one source is
# the same shape as the -D double rename, so they are now derived together or not at all.
: > "$build/decls.h"; : > "$build/checks.h"; : > "$build/calls.h"
while read -r name <&3; do
  printf 'extern NSString *const %s;\nextern NSString *const charonHost_%s;\n' "$name" "$name" >> "$build/decls.h"
  printf 'static void charonCheck_%s(void) { charonCompareString(@"%s", charonHost_%s, (NSString *const *)dlsym(g_handle, "%s")); }\n' \
    "$name" "$name" "$name" "$name" >> "$build/checks.h"
  printf '    charonCheck_%s();\n' "$name" >> "$build/calls.h"
  names_seen=$((names_seen + 1))
done 3< "$build/strings.txt"
[ "$names_seen" -eq 13 ] || { echo "expected 13 names in the generated pieces, got $names_seen"; exit 1; }
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
# THE AGREEMENT IS ASSERTED, not printed. The binary's own exit status cannot carry it, because the
# PLANTED CONTROL ALWAYS FAILS BY DESIGN, so the process always exits non-zero and that bit is worth
# nothing. The reviewer's change to one port value printed "GREEN: 12 of 13 agree" and this run still
# exited 0 having finished "13 mutants run, 13 RED" - the mutants are a separate proof and they do not
# notice a value that is wrong in the REAL sources. So the counts are checked here, by name.
ok=$(grep -c '^OK' "$build/green.txt" || true)
dis=$(grep -c '^DIFFERS' "$build/green.txt" || true)
noor=$(grep -c '^NO-ORACLE' "$build/green.txt" || true)
echo "  GREEN: $ok of $n agree, and the planted control is reported:"
grep '^MISSING' "$build/green.txt" | sed 's/^/    /'
[ "$noor" -eq 0 ] || { echo "FAIL  $noor constants were compared by no oracle at all"; exit 1; }
[ "$dis" -eq 0 ] || { echo "FAIL  the real build disagrees with Apple on $dis constants, by name:"
  grep '^DIFFERS' "$build/green.txt" | cut -f2 | sed 's/^/    /'; exit 1; }
[ "$ok" -eq "$n" ] || { echo "FAIL  only $ok of $n constants agree with Apple, and the other $((n-ok)) are not OK:"
  grep -E '^(DIFFERS|MISSING|NO-ORACLE|NULL|PORT-NULL)' "$build/green.txt" | cut -f1,2 | sed 's/^/    /'; exit 1; }

# THE MUTANTS: one per constant. A mutant directory must hold BOTH objects, because a port's constants
# live in more than one object and a mutant that changes the 9.0 object still has to LINK against the
# 8.2 one. The untouched object is copied unchanged. A build that produces no binary is a FAILURE and not
# a skip: a loop that continues past a broken build reports "0 mutants" as a pass, which is how this
# harness claimed coverage it never had.
i=0; ran=0
while read -r name <&3; do
  i=$((i+1))
  rm -rf "$build/src-m$i" "$build/m$i"; mkdir -p "$build/src-m$i"
  for f in MediaPlayerConstants90 MediaPlayerConstants82; do
    [ -f "$port/$f.m" ] || continue
    cp "$port/$f.m" "$build/src-m$i/$f.m"
  done
  # change exactly this one constant, in whichever object holds it
  for f in MediaPlayerConstants90 MediaPlayerConstants82; do
    [ -f "$build/src-m$i/$f.m" ] || continue
    if grep -q "^NSString \*const $name = " "$build/src-m$i/$f.m"; then
        # the mutation is an awk one-liner keyed on the exact name, with the variables EXPANDED: a
        # single-quoted sed BRE left $name and $i literal, matched nothing, and produced a copy
        # identical to the original - which the loop then correctly reported as NOT NOTICED
        sed "s%^NSString \*const $name = @\"[^\"]*\";%NSString *const $name = @\"charon-mutant-$i\";%" \
          "$build/src-m$i/$f.m" > "$build/src-m$i/$f.tmp" && mv "$build/src-m$i/$f.tmp" "$build/src-m$i/$f.m"
        # and the copy must DIFFER FROM THE ORIGINAL BY EXACTLY ONE LINE, or it is not a mutation
        c=$(diff "$port/$f.m" "$build/src-m$i/$f.m" | grep -c "^>" || true)
        [ "$c" -eq 1 ] || { echo "BUILD  mutant $i: $f.m differs from the original in $c lines, not 1 - the mutation did not apply"; exit 1; }
        d=$(grep -c "^NSString \*const " "$build/src-m$i/$f.m")
        o=$(grep -c "^NSString \*const " "$port/$f.m")
        [ "$d" -eq "$o" ] || { echo "BUILD  mutant $i: $f.m has $d definitions and the original has $o"; exit 1; }
    fi
  done
  # BOTH files, explicitly, and a file that is not there is an error rather than a shorter command
  m90="$build/src-m$i/MediaPlayerConstants90.m"
  m82="$build/src-m$i/MediaPlayerConstants82.m"
  for f in "$m90" "$m82"; do
    [ -f "$f" ] || { echo "BUILD  mutant $i: $f is missing"; exit 1; }
  done
  run_case "m$i" "$m90" "$m82" || { echo "BUILD  mutant $i did not build"; exit 1; }
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
exit 0
