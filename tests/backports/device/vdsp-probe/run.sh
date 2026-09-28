#!/bin/sh
# The probe on the emulated iPhone2,1 6.1.3 (10B329) guest, through heavy.sh. The log is the deliverable:
# the release's own vDSP against this band's kernel, on the target's own arithmetic.
#
# **The hash check is the point of this script, not a nicety in it.** `xmake emulate install` has been observed
# reporting "installing .. install ok!" and leaving the image's copy of the program unchanged, so a guest run
# has been executing a binary two edits old and reporting its output as a result. Every run now compares the
# built binary against the one in the image's rootfs and stops if they differ. A run that does not happen is
# better than a run that reports the wrong binary's answers, and a silent stale run is worse than both.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=${VDSPPROBE_ROOT:-$(cd "$here/../../../.." && pwd)}
out="$here/run"
mkdir -p "$out"
cd "$here"
export VDSPPROBE_ROOT="$root"
/opt/homebrew/bin/xmake f -c -p iphoneos -a armv7 -y > "$out/configure.log" 2>&1
/opt/homebrew/bin/xmake emulate install > "$out/install.log" 2>&1

program=vdsp-biquad-probe
built=$(find "$here/build" -name "$program" -type f 2>/dev/null | head -1)
image=$(ls -d "$HOME"/.charon/emulator/images.noindex/vdspprobe-* 2>/dev/null | head -1)
installed="$image/iPhone2,1_10B329/rootfs/usr/libexec/$program"

# **LC_UUID, not a byte hash, and that is 7e035ac0's rule rather than mine.** A hash of the bytes before the
# code signature cannot prove provenance: strip rewrites those bytes, and an unsigned build has no bytes there
# at all, so the "before" region of one is empty. Neither strip nor ldid -S changes LC_UUID, so the UUID is
# what identifies a build. It is read through `otool -l` rather than parsed by hand, because Charon's ld64
# writes the magic byte-swapped and a hand-rolled reader would have to know that.
uuid_of() {
  [ -f "$1" ] || { echo "(no file)"; return; }
  /usr/bin/otool -l "$1" 2>/dev/null | awk '/cmd +LC_UUID/ { seen = 1; next } seen && $1 == "uuid" { print $2; exit }'
}

{
  printf 'built     %s\n' "${built:-NOT FOUND}"
  printf 'installed %s\n' "$installed"
  if [ -n "$built" ] && [ -f "$installed" ]; then
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

/opt/homebrew/bin/xmake emulate -t 900 -s 300 run "/usr/libexec/$program" > "$out/run.log" 2>&1 || true
/opt/homebrew/bin/xmake emulate log > "$out/guest.log" 2>&1 || true
