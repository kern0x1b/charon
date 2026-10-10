#!/bin/sh
# run-app.sh - the CoreMIDI round trip as an installed application on the emulated iPhone 4S at 6.1.3 (app/main.m).
# Launched through SpringBoard with `xmake emulate launch`; the application's standard output is the verdict.
# Usage: sh tests/backports/emulate/coremidi/run-app.sh [--minimum 6.1.3]
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
stamp=$(date +%Y%m%d-%H%M%S)
# Built outside the daemon's directory: the application's project sits there otherwise, and xmake would pick the daemon's
# project for it. The default is a run folder of this checkout (.agent-work/runs), never the system temp directory.
build=${COREMIDI_APP_BUILD:-$root/.agent-work/runs/coremidi-app/$minimum-$stamp}
out=$build
mkdir -p "$build"
cp "$here/app/xmake.lua" "$here/app/control" "$here/app/Info.plist" "$build/"
if [ -n "${CHARCOREMIDI_NO_BACKGROUND:-}" ]; then
    # The variant without the background mode: the audio entry of UIBackgroundModes is taken out of the copy.
    plutil -remove UIBackgroundModes "$build/Info.plist"
fi
cd "$build"
CHARCOREMIDI_ROOT=$root CHARCOREMIDI_MINIMUM=$minimum xmake f -p iphoneos -a armv7 -y >"$out/configure.log" 2>&1 || {
    echo "the application did not configure; $out/configure.log says why" >&2
    tail -20 "$out/configure.log" >&2
    exit 1
}
CHARCOREMIDI_ROOT=$root CHARCOREMIDI_MINIMUM=$minimum xmake emulate -d iPhone4,1 -r "$minimum" install >"$out/install.log" 2>&1 || {
    echo "the application did not install; $out/install.log says why" >&2
    tail -20 "$out/install.log" >&2
    exit 1
}
# The launch's output is this run's own file (the run folder is new), and the verdict is read from it alone: the device's log
# keeps the lines of earlier runs, so it is printed for diagnosis and never searched for the verdict.
set +e
CHARCOREMIDI_ROOT=$root CHARCOREMIDI_MINIMUM=$minimum xmake emulate -d iPhone4,1 -r "$minimum" launch local.charon.backports.coremidiapp >"$out/launch.log" 2>&1
launch_status=$?
xmake emulate -d iPhone4,1 -r "$minimum" log >"$out/emulate.log" 2>&1
log_status=$?
set -e
cat "$out/launch.log"
echo "run folder: $out (launch status $launch_status, log status $log_status)"
if ! grep -q '^roundtrip: PASS' "$out/launch.log"; then
    echo "the round trip did not pass: no 'roundtrip: PASS' line in this run's $out/launch.log" >&2
    exit 1
fi
# A nonzero launch status is accepted only when the application's own device verdict for this run shows a clean exit. The
# emulator reports an application that ends as its budget is reached as a failed launch (failure "exited", reason "reached"),
# and the application's exit status is in that verdict (verdict.json beside the emulator log named in launch.log).
if [ "$launch_status" -ne 0 ]; then
    device=$(sed -n 's|.*emulator log is \(/[^ ]*\)/emulator\.log.*|\1|p' "$out/launch.log" | tail -1)
    exit_field=""
    if [ -n "$device" ] && [ -f "$device/verdict.json" ]; then
        exit_field=$(grep -o '"exit":{[^}]*}' "$device/verdict.json") || exit_field=""
    fi
    case "$exit_field" in
        *'"status":0'*'"signal":0'*|*'"signal":0'*'"status":0'*) ;;
        *)
            echo "the launch exited $launch_status and the application's exit is not clean: $device/verdict.json" >&2
            exit 1
            ;;
    esac
    echo "the launch status $launch_status is the emulator's report of the budget and the exit; the application's own exit is clean ($exit_field)"
fi
