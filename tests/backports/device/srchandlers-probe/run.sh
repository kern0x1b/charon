#!/bin/sh
# What the release itself does with a barrier source's cancellation and registration handlers on the
# emulated iPhone3,1 at 6.1.3 (10B329), through heavy.sh, one scenario per process. This is the standing
# evidence for one measured fact about that release, and it builds from origin/main on its own: no shim
# of the cancellation or registration kind is in the binary, which the nm gate below checks.
#
# The fact, measured 2026-10-04 and gated at the bottom of this file: **libdispatch-228 already runs both
# of those handlers alone on a concurrent target queue.** The prediction this file used to carry said the
# opposite - that below iOS 10 these two handlers are ordinary blocks on the source's target queue, since
# the barrier bit belongs to the source only from iOS 10 - and the run refuted it: `alone=yes` on the
# concurrent width for cancel, registration and both retargets. So the shims that stood beside these
# readings were withdrawn: they answered alone=yes where the release already answers alone=yes, and the
# step where they take the handler off the source ends the process on signal 5 here
# (`dispatch_source_set_{cancel,registration}_handler(source, NULL)`, measured on its own).
#
# `alone` is only a reading because of the ordinaryasync case at the bottom of the table: the guest reports
# ONE processor, so an ordinary block submitted to a concurrent target queue would answer alone=yes if that
# queue ran one block at a time. It answers alone=no. So the queue is concurrent, and the source's handler
# really did run alone.
#
# Two things about this guest are measured, not assumed: `xmake emulate run` takes a bare path (a command
# with words after it comes back `fail(spawn error 2)`, and a bare path gives argc=1), so the scenario can
# only be named by forking; and a forked child's writes to this guest's standard output do not reach the
# runner's capture, so a child answers through a pipe and this script's parent reads it and prints it.
# fork itself works - the six guest checks at the top of the program's output.
#
# LC_UUID, not a byte hash: strip rewrites the bytes before the signature and ldid -S changes those again,
# and neither touches LC_UUID, so the UUID is what identifies a build. The image is found by that UUID and
# never by `ls -d <prefix>-* | head -1`: a project's configuration is part of its image's name, so a second
# image appears as soon as the configuration changes and the glob cannot tell them apart.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# Four ".." up from this directory (tests/backports/device/srchandlers-probe) is the repository root: the
# directory is device's child, device is backports', backports is tests', tests is the root's.
root=${SRCH_ROOT:-$here/../../../..}
out="$here/run"
mkdir -p "$out"
cd "$here"
export SRCH_ROOT="$root"

device=${SRCH_DEVICE:-iPhone3,1}
release=${SRCH_RELEASE:-6.1.3}
xmake=/opt/homebrew/bin/xmake
heavy=$HOME/Git/projects/ios/coordination/heavy.sh

# Configure, build and install run directly and only the emulator run goes through heavy.sh, which puts it
# in the bulk lane. heavy.sh breaks this project's `xmake f`: measured 2026-10-04 with the same lock in
# place, the same command under heavy.sh fails its configure with every package reported as not found -
# shade, swiftshader, emulator-guest, iphoneos-sdk, ld64, ldid, llvm, firmware-tools - and
# `error: <no error object>`, while run directly it configures with rc=0.
"$xmake" f -p iphoneos -a armv7 -y > "$out/configure.log" 2>&1
"$xmake" -y > "$out/build.log" 2>&1
"$xmake" emulate -d "$device" -r "$release" install > "$out/install.log" 2>&1

program=sourcehandlers
built="$here/build/iphoneos/armv7/release/$program"

uuid_of() {
  [ -f "$1" ] || { echo "(no file)"; return; }
  /usr/bin/otool -l "$1" 2>/dev/null | awk '/cmd +LC_UUID/ { seen = 1; next } seen && $1 == "uuid" { print $2; exit }'
}

built_uuid=$(uuid_of "$built")
installed=
for candidate in "$HOME"/.charon/emulator/images.noindex/srchandlersprobe-*/"${device}"_*/rootfs/usr/libexec/$program; do
  [ -f "$candidate" ] || continue
  if [ "$(uuid_of "$candidate")" = "$built_uuid" ]; then
    installed=$candidate
    break
  fi
done
{
  printf 'built     %s\n' "$built"
  printf 'built     LC_UUID %s\n' "$built_uuid"
  printf 'installed %s\n' "${installed:-NOT FOUND}"
  printf 'every image of this project, and the LC_UUID of the program in each:\n'
  for candidate in "$HOME"/.charon/emulator/images.noindex/srchandlersprobe-*; do
    [ -d "$candidate" ] || continue
    printf '  %s  %s\n' "$(basename "$candidate")" \
      "$(uuid_of "$candidate/${device}_10B329/rootfs/usr/libexec/$program")"
  done
  if [ -n "$installed" ]; then
    printf 'the image holding this build was found by its LC_UUID, not by its name\n'
    printf 'HASHES MATCH\n'
  else
    printf 'no image holds a program with this build LC_UUID, so the run is NOT going ahead\n'
    printf 'HASHES MISMATCH\n'
  fi
} > "$out/hash.txt" 2>&1
grep -q "HASHES MATCH" "$out/hash.txt" || { cat "$out/hash.txt"; exit 1; }
cat "$out/hash.txt"

# What the binary must hold and must not hold, which is the point of this gate. It must NOT hold any of
# the six shims whose premise the run refuted: a build that linked one again would answer the
# cancellation and registration questions with the shim rather than with the release. It MUST hold the
# two the event cases compare against - the barrier event handler's shim and the resume that writes the
# activation record it asks, both on origin/main. And the plain dispatch names the binary claims must be
# dispatch_block_create alone: a shim that claimed a plain name would answer these calls instead of
# libdispatch's. Counts come from nm's third field, the symbol's own name, because
# _charon_dispatch_source_create contains _dispatch_ and a substring count would read a shim as a claim on
# the release's name.
{
  printf 'every charon_dispatch_* this binary defines:\n'
  nm "$built" 2>/dev/null | awk '$2 == "t" || $2 == "T" { print $1, $2, $3 }' | grep -E ' _charon_dispatch_' | sort -k3 || true
  printf 'the release names this binary defines itself (dispatch_block_create is the one a shim claims):\n'
  nm "$built" 2>/dev/null | awk '$2 == "t" || $2 == "T" { print $1, $2, $3 }' | grep -E ' _dispatch_' | sort -k3 || true
} > "$out/symbols.txt" 2>&1
present=$(awk '$3 ~ /^_charon_dispatch_(source_create|set_target_queue|source_set_cancel_handler|source_set_registration_handler|source_cancel)$/ { print $3 }' "$out/symbols.txt" | tr '\n' ' ')
wanted=$(awk '$3 ~ /^_charon_dispatch_(resume|source_set_event_handler)$/ { print $3 }' "$out/symbols.txt" | sort | tr '\n' ' ')
claimed=$(awk '$3 ~ /^_dispatch_/ { print $3 }' "$out/symbols.txt" | tr '\n' ' ')
cat "$out/symbols.txt"
printf 'the withdrawn shims in the binary: %s\n' "${present:-none}"
printf 'the event handler shims in the binary: %s\n' "${wanted:-none}"
printf 'the release names this binary claims: %s\n' "${claimed:-none}"
if [ -n "$present" ]; then
  printf 'a withdrawn shim is linked in, so these readings would not be the release own, so NO run\n'
  printf 'SYMBOLS MISMATCH\n'
  exit 1
fi
if [ "$wanted" != "_charon_dispatch_resume _charon_dispatch_source_set_event_handler " ] && \
   [ "$wanted" != "_charon_dispatch_source_set_event_handler _charon_dispatch_resume " ]; then
  printf 'the event handler shims are not both linked, so the two columns would not be two columns, so NO run\n'
  printf 'SYMBOLS MISMATCH\n'
  exit 1
fi
if [ "$claimed" != "_dispatch_block_create " ] && [ "$claimed" != "_dispatch_block_create" ]; then
  printf 'the binary claims a plain dispatch name other than dispatch_block_create, so NO run\n'
  printf 'SYMBOLS MISMATCH\n'
  exit 1
fi
printf 'no withdrawn shim is linked, both event handler shims are, and the only release name this binary claims is dispatch_block_create\n'
printf 'SYMBOLS MATCH\n'

"$heavy" "$xmake" emulate -d "$device" -r "$release" -t 900 -s 300 run \
    "/usr/libexec/$program" > "$out/run.log" 2>&1 || true
"$xmake" emulate logfile > "$out/guest.log" 2>&1 || true
sed 's/\x1b\[[0-9;]*m//g' "$out/run.log"

# The measured table, as a gate. Every row is what the run recorded on 2026-10-04, read field by field in
# the order the program prints them; a row that stops answering, or answers differently, fails by name.
# The two rows that carry the finding are cancel concurrent and registration concurrent with alone=yes,
# and the row that makes alone=yes readable at all is ordinaryasync concurrent with alone=no.
# The twelve event rows, measured 2026-10-04. Every one of them is the same line, and that is the finding:
# on this release a source's event handler does not run while another block is holding a CONCURRENT target
# queue - not with a barrier block made by dispatch_block_create, not with a plain block literal, not with
# the shim origin/main carries and not with the release's own call. The reading that makes that mean
# something is ordinaryasync in the table above, in the same run on the same kind of queue: a plain
# dispatch_async block there answers alone=no, so the queue does run two blocks at once and a source's
# handler is what waits. The serial rows are alone=yes for the same reason the cancellation and
# registration serial rows are: on a serial queue there is one block at a time.
cat > "$out/wanted.tsv" <<'TABLE'
cancel	concurrent	system	held=yes ran=yes alone=yes second=no returned=yes order=-
cancel	serial	system	held=yes ran=yes alone=yes second=no returned=yes order=-
registration	concurrent	system	held=yes ran=yes alone=yes second=no returned=yes order=-
registration	serial	system	held=yes ran=yes alone=yes second=no returned=yes order=-
neverresumed	concurrent	system	held=yes ran=no alone=n/a second=n/a returned=yes order=-
neverresumed	serial	system	held=yes ran=no alone=n/a second=n/a returned=yes order=-
retargetbefore	concurrent	system	held=yes ran=yes alone=yes second=yes returned=yes order=-
retargetbefore	serial	system	held=yes ran=yes alone=yes second=yes returned=yes order=-
retargetafter	concurrent	system	held=yes ran=yes alone=yes second=yes returned=yes order=-
retargetafter	serial	system	held=yes ran=yes alone=yes second=yes returned=yes order=-
onqueue	concurrent	system	held=n/a ran=yes alone=yes second=no returned=yes order=-
onqueue	serial	system	held=n/a ran=yes alone=yes second=no returned=yes order=-
resumecancel	concurrent	system	held=n/a ran=yes alone=yes second=no returned=no order=RC
resumecancel	serial	system	held=n/a ran=yes alone=yes second=no returned=no order=RC
ordinaryasync	concurrent	system	held=yes ran=yes alone=no second=n/a returned=yes order=-
ordinaryasync	serial	system	held=yes ran=yes alone=yes second=n/a returned=yes order=-
event	concurrent	system	held=n/a ran=yes alone=yes second=no returned=yes order=-
event	concurrent	shim	held=n/a ran=yes alone=yes second=no returned=yes order=-
event	serial	system	held=n/a ran=yes alone=yes second=no returned=yes order=-
event	serial	shim	held=n/a ran=yes alone=yes second=no returned=yes order=-
eventafresume	concurrent	system	held=n/a ran=yes alone=yes second=no returned=yes order=-
eventafresume	concurrent	shim	held=n/a ran=yes alone=yes second=no returned=yes order=-
eventafresume	serial	system	held=n/a ran=yes alone=yes second=no returned=yes order=-
eventafresume	serial	shim	held=n/a ran=yes alone=yes second=no returned=yes order=-
ordinaryevent	concurrent	system	held=n/a ran=yes alone=yes second=no returned=yes order=-
ordinaryevent	concurrent	shim	held=n/a ran=yes alone=yes second=no returned=yes order=-
ordinaryevent	serial	system	held=n/a ran=yes alone=yes second=no returned=yes order=-
ordinaryevent	serial	shim	held=n/a ran=yes alone=yes second=no returned=yes order=-
TABLE

# A child that ended on a signal has no row, and a row that is missing must fail: with the shims linked
# this is exactly how a run reported sixteen clean ends and no answers at all.
died=$(grep -c 'CHILD ENDED' "$out/run.log" || true)
guest_failed=$(grep -cE '^guest .*: (ENDED|FORK FAILED)' "$out/run.log" || true)

RUNLOG="$out/run.log" awk -v wanted="$out/wanted.tsv" -v died="$died" -v guest_failed="$guest_failed" '
# One pass per wanted row: the log is read from the start each time, which is sixteen reads of a
# thirty-line file and keeps the comparison a plain string equality against the row.
# The handle is closed on every call, including the one that finds nothing. awk keeps the position of a
# file between getline calls, so an unclosed handle would make each row start where the previous one
# stopped, and the comparison would then only work while the table happened to be in the same order as
# the log - which is a property of this run, not of the check.
function answer(which, width, api,   line) {
    while ((getline line < logfile) > 0) {
        if (index(line, which " " width " " api ": ") == 1) {
            close(logfile)
            return line
        }
    }
    close(logfile)
    return ""
}
BEGIN {
    logfile = ENVIRON["RUNLOG"]
    fails = 0
    while ((getline row < wanted) > 0) {
        split(row, parts, "\t")
        which = parts[1]; width = parts[2]; api = parts[3]; expect = parts[4]
        got = answer(which, width, api)
        # The log line is "<case> <width> <api>: <fields>" and the table row is
        # "<case>\t<width>\t<api>\t<fields>"; what is compared is the fields, which are one string in
        # both. Everything up to the first ": " goes, so the column name is not written twice: a strip
        # that named the column would silently compare nothing for the other column, which is how the
        # twelve shim rows first came out as twelve identical-looking mismatches.
        sub(/^[^:]*: /, "", got)
        if (got == "") {
            printf "FAIL  the %s case on a %s target queue, %s column, did not answer at all\n", which, width, api
            fails++
        } else if (got != expect) {
            printf "FAIL  the %s column answers \"%s\" for the %s case on a %s target queue, where this measurement recorded \"%s\"\n", api, got, which, width, expect
            fails++
        }
    }
    if (died != 0) {
        printf "FAIL  %s scenario(s) ended without answering, so the table above cannot be complete\n", died
        fails++
    }
    if (guest_failed != 0) {
        printf "FAIL  %s of the guest capability checks did not pass, so fork is not sound here\n", guest_failed
        fails++
    }
    if (fails == 0)
        printf "ok    the release runs a cancellation and a registration handler alone on a concurrent target queue, and the ordinary-block control is what makes that reading mean it\n"
    else
        printf "%d checks failed\n", fails
    exit(fails == 0 ? 0 : 1)
}
'
