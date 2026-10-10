#!/bin/sh
# run.sh - the CoreMIDI backport's round trip on the emulated iPhone 4S at 6.1.3 (roundtrip.m).
#
# Usage: sh tests/backports/emulate/coremidi/run.sh [--minimum 6.1.3]
# The verdict is the last line of the run's output: "roundtrip: PASS" or "roundtrip: FAIL (n failures)".
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
minimum=6.1.3
while [ $# -gt 0 ]; do
    case "$1" in
        --minimum) minimum=$2; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
done
work=${WORK:-$here/.agent-work}
stamp=$(date +%Y%m%d-%H%M%S)
out=$work/runs/coremidi-$minimum-$stamp
mkdir -p "$out"
cd "$here"
xmake f -p iphoneos -a armv7 -y >"$out/configure.log" 2>&1 || {
    echo "the port did not configure; $out/configure.log says why" >&2
    tail -20 "$out/configure.log" >&2
    exit 1
}
xmake emulate -d iPhone4,1 -r "$minimum" install >"$out/install.log" 2>&1 || {
    echo "the port did not install; $out/install.log says why" >&2
    tail -20 "$out/install.log" >&2
    exit 1
}
# The run's output is this run's own file, and the verdict is read from it alone: the device's log keeps the lines of earlier
# runs, so it is printed for diagnosis and never searched for the verdict.
set +e
CHARCOREMIDI_ROOT=$root CHARCOREMIDI_MINIMUM=$minimum \
xmake emulate -d iPhone4,1 -r "$minimum" run /usr/libexec/charoncoremidi >"$out/run.log" 2>&1
run_status=$?
xmake emulate -d iPhone4,1 -r "$minimum" log >"$out/emulate.log" 2>&1
log_status=$?
set -e
cat "$out/run.log"
echo "run folder: $out (run status $run_status, log status $log_status)"
if [ "$run_status" -ne 0 ]; then
    echo "the run exited $run_status: $out/run.log says why" >&2
    exit 1
fi
if ! grep -q '^roundtrip: PASS' "$out/run.log"; then
    echo "the round trip did not pass: no 'roundtrip: PASS' line in this run's $out/run.log" >&2
    exit 1
fi
