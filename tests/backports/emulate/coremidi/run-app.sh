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
# Built outside the checkout: the application's project sits inside the daemon's directory, and xmake would pick the daemon's
# project for it there (the display-probe run does the same, in the system temp path).
build=${COREMIDI_APP_BUILD:-${TMPDIR:-/tmp}/charon-coremidi-app/$minimum-$stamp}
out=$build
mkdir -p "$build"
cp "$here/app/xmake.lua" "$here/app/control" "$here/app/Info.plist" "$build/"
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
CHARCOREMIDI_ROOT=$root CHARCOREMIDI_MINIMUM=$minimum xmake emulate -d iPhone4,1 -r "$minimum" launch local.charon.backports.coremidiapp >"$out/launch.log" 2>&1 || true
xmake emulate -d iPhone4,1 -r "$minimum" log >"$out/emulate.log" 2>&1 || true
cat "$out/launch.log"
echo "run folder: $out"
