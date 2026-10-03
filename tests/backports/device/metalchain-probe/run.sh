#!/bin/sh
# run.sh - the port's Metal 4 command chain on the emulated iPhone3,1 6.1.3 guest, through heavy.sh.
# The log is the deliverable.
#
# WHY iPhone3,1 6.1.3 AND NOT A HOST: the port's Metal 4 queue wraps the port's CharonMetalQueue, which
# holds an EAGL context over OpenGL ES 2.0, and OpenGLES/EAGL.h is a DEVICE framework - a host binary
# cannot compile the file at all. So Apple's side was measured on the host and written down in
# tests/backports/device/metalchain-expectations.h, and this is where the port meets it.
#
# **THE HASH CHECK IS THE POINT OF THIS SCRIPT, NOT A NICETY IN IT.** `xmake emulate install` has been
# observed reporting "installing .. install ok!" and leaving the image's copy of the program unchanged,
# so a guest run has executed a binary two edits old and reported its output as a result. Every run
# compares the built binary against the one in the image's rootfs and stops if they differ. A run that
# does not happen is better than a run that reports the wrong binary's answers, and a silent stale run is
# worse than both. The identity read is LC_UUID and not a byte hash, because that is 7e035ac0's rule: a
# hash of the bytes before the code signature cannot prove provenance - strip rewrites those bytes, and
# an unsigned build has none there at all - while neither strip nor ldid -S changes LC_UUID.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=${METALCHAINPROBE_ROOT:-$(cd "$here/../../../.." && pwd)}
out="$here/run"
mkdir -p "$out"
cd "$here"
export METALCHAINPROBE_ROOT="$root"

/opt/homebrew/bin/xmake f -c -p iphoneos -a armv7 -y > "$out/configure.log" 2>&1
/opt/homebrew/bin/xmake emulate install > "$out/install.log" 2>&1

program=metalchain-probe
built=$(find "$here/build" -name "$program" -type f 2>/dev/null | head -1)
image=$(ls -d "$HOME"/.charon/emulator/images.noindex/metalchainprobe-* 2>/dev/null | head -1)
installed=$(ls "$image"/*/rootfs/usr/libexec/$program 2>/dev/null | head -1)

uuid_of() {
  [ -f "$1" ] || { echo "(no file)"; return; }
  /usr/bin/otool -l "$1" 2>/dev/null | awk '/cmd +LC_UUID/ { seen = 1; next } seen && $1 == "uuid" { print $2; exit }'
}

{
  printf 'built     %s\n' "${built:-NOT FOUND}"
  printf 'installed %s\n' "${installed:-NOT FOUND}"
  if [ -n "$built" ] && [ -n "$installed" ] && [ -f "$installed" ]; then
    ua=$(uuid_of "$built"); ub=$(uuid_of "$installed")
    printf 'built     LC_UUID %s\n' "$ua"
    printf 'installed LC_UUID %s\n' "$ub"
    printf 'built     mtime   %s\n' "$(stat -f %m "$built")"
    printf 'installed mtime   %s\n' "$(stat -f %m "$installed")"
    if [ "$(stat -f %m "$installed")" -lt "$(stat -f %m "$built")" ]; then
      printf 'the copy is OLDER than the build it was copied from, so the run is NOT going ahead\n'
      printf 'HASHES MISMATCH\n'
    elif [ "$ua" = "$ub" ] && [ -n "$ua" ] && [ "$ua" != "(no file)" ]; then
      printf 'HASHES MATCH\n'
    else
      printf 'the two carry different LC_UUIDs, so the image holds a program from another build\n'
      printf 'HASHES MISMATCH\n'
    fi
  else
    printf 'one of the two is missing, so the run is NOT going ahead\n'
    printf 'HASHES MISMATCH\n'
  fi
} > "$out/hash.txt" 2>&1
grep -q "HASHES MATCH" "$out/hash.txt" || { cat "$out/hash.txt"; exit 1; }
cat "$out/hash.txt"

/opt/homebrew/bin/xmake emulate -d iPhone3,1 -r 6.1.3 -t 900 -s 300 run "/usr/libexec/$program" > "$out/run.log" 2>&1 || true
/opt/homebrew/bin/xmake emulate log > "$out/guest.log" 2>&1 || true
echo
echo "run.sh: the verdict is in $out/run.log and the guest's own output in $out/guest.log"
