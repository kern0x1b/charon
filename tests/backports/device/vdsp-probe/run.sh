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
# where xmake put it, and where the guest will look for it
built=$(find "$here/build" -name "$program" -type f 2>/dev/null | head -1)
image=$(ls -d "$HOME"/.charon/emulator/images.noindex/vdspprobe-* 2>/dev/null | head -1)
installed="$image/iPhone2,1_10B329/rootfs/usr/libexec/$program"
{
  printf 'built     %s\n' "${built:-NOT FOUND}"
  printf 'installed %s\n' "$installed"
  if [ -n "$built" ] && [ -f "$installed" ]; then
    a=$(shasum -a 256 "$built" | awk '{print $1}')
    b=$(shasum -a 256 "$installed" | awk '{print $1}')
    printf 'built     sha256 %s\n' "$a"
    printf 'installed sha256 %s\n' "$b"
    if [ "$a" = "$b" ]; then
      printf 'HASHES MATCH - the guest will run the binary that was just built\n'
    else
      printf 'HASHES DIFFER - the image holds a different binary, so the run is NOT going ahead\n'
    fi
  else
    printf 'one of the two is missing, so the run is NOT going ahead\n'
  fi
} > "$out/hash.txt" 2>&1
grep -q "HASHES MATCH" "$out/hash.txt" || { cat "$out/hash.txt"; exit 1; }
cat "$out/hash.txt"

/opt/homebrew/bin/xmake emulate -t 900 -s 300 run "/usr/libexec/$program" > "$out/run.log" 2>&1 || true
/opt/homebrew/bin/xmake emulate log > "$out/guest.log" 2>&1 || true
