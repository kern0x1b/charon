#!/bin/sh
# The biquad probe on the emulated iPhone2,1 6.1.3 (10B329) guest, through heavy.sh. The log is the
# deliverable: the release's own vDSP_biquad against this band's kernel, on the target's own arithmetic.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=${VDSPPROBE_ROOT:-$(cd "$here/../../../.." && pwd)}
out="$here/run"
mkdir -p "$out"
cd "$here"
export VDSPPROBE_ROOT="$root"
# -c clears the cached configure: without it a target added after the last configure is not in the
# project, the install carries only the programs it knew about, and the run then fails with "spawn error 2"
# on a path the install never created.
/opt/homebrew/bin/xmake f -c -p iphoneos -a armv7 -y > "$out/configure.log" 2>&1
/opt/homebrew/bin/xmake emulate install > "$out/install.log" 2>&1
# /usr/libexec, not /usr/bin: that is where the package's program lands, and asking for /usr/bin fails
# with "spawn error 2" after a boot that otherwise worked.
printf 'exit=%s\n' "$?" >> "$out/run.log"
/opt/homebrew/bin/xmake emulate -t 900 -s 300 run /usr/libexec/vdsp-biquad-probe > "$out/run.log" 2>&1 || true
/opt/homebrew/bin/xmake emulate log > "$out/guest.log" 2>&1 || true
