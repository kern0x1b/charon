#!/bin/sh
# run-app.sh - the Matter cluster port as an installed application on the emulated iPhone 4S at 6.1.3 (app/main.m): the
# Identify, OnOff and TestCluster classes are looked up in the library, each gets a cached read, a write and read back,
# and a subscribe, and the application's standard output is the verdict. The same steps as the CoreMIDI application
# (tests/backports/emulate/coremidi/run-app.sh), with its verdict line in place of the round trip's.
# Usage: sh tests/backports/emulate/matter/run-app.sh [--minimum 6.1.3]
#        CHARMATTER_RED=1 sh tests/backports/emulate/matter/run-app.sh   the red path: the cached read expects a wrong
#        error code, so the run must print "matter: FAIL" and exit non-zero, and that is what this script then checks.
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
# Built outside the application's own directory, in a run folder of this checkout (never the system temp directory).
out=${MATTER_APP_BUILD:-$root/.agent-work/runs/matter-app/$minimum-$stamp}
mkdir -p "$out"
cp "$here/app/xmake.lua" "$here/app/control" "$here/app/Info.plist" "$out/"
cd "$out"
if [ -n "${CHARMATTER_RED:-}" ]; then
    expect=FAIL
else
    expect=PASS
fi
CHARMATTER_ROOT=$root CHARMATTER_MINIMUM=$minimum xmake f -p iphoneos -a armv7 -y >"$out/configure.log" 2>&1 || {
    echo "the application did not configure; $out/configure.log says why" >&2
    tail -20 "$out/configure.log" >&2
    exit 1
}
CHARMATTER_ROOT=$root CHARMATTER_MINIMUM=$minimum xmake emulate -d iPhone4,1 -r "$minimum" install >"$out/install.log" 2>&1 || {
    echo "the application did not install; $out/install.log says why" >&2
    tail -20 "$out/install.log" >&2
    exit 1
}
set +e
CHARMATTER_ROOT=$root CHARMATTER_MINIMUM=$minimum xmake emulate -d iPhone4,1 -r "$minimum" launch local.charon.backports.matterapp >"$out/launch.log" 2>&1
launch_status=$?
xmake emulate -d iPhone4,1 -r "$minimum" log >"$out/emulate.log" 2>&1
set -e
cat "$out/launch.log"
echo "run folder: $out (launch status $launch_status)"
# The verdict is read from this run's own launch log only: the device's log keeps the lines of earlier runs.
if ! grep -q "^matter: $expect " "$out/launch.log"; then
    echo "the verdict is not '$expect': no 'matter: $expect' line in this run's $out/launch.log" >&2
    exit 1
fi
# The application's own exit is the device's verdict.json (named by launch.log), not the launch status: the emulator reports
# an application that ends as its budget is reached as a failed launch (reason "reached"), with the exit status it had.
device=$(sed -n 's|.*emulator log is \(/[^ ]*\)/emulator\.log.*|\1|p' "$out/launch.log" | tail -1)
exit_record=$(sed -n 's/.*"exit":{\([^}]*\)}.*/\1/p' "$device/verdict.json")
app_status=$(echo "$exit_record" | sed -n 's/.*"status":\([0-9]*\).*/\1/p')
app_signal=$(echo "$exit_record" | sed -n 's/.*"signal":\([0-9]*\).*/\1/p')
if [ -z "$app_status" ] || [ -z "$app_signal" ]; then
    echo "no exit record in $device/verdict.json: the application's exit is not known" >&2
    exit 1
fi
if [ "$expect" = PASS ] && { [ "$app_status" != 0 ] || [ "$app_signal" != 0 ]; }; then
    echo "the verdict is PASS but the application exited $app_status (signal $app_signal): $device/verdict.json" >&2
    exit 1
fi
if [ "$expect" = FAIL ]; then
    if [ "$app_status" = 0 ] && [ "$app_signal" = 0 ]; then
        echo "the red path printed FAIL but the application exited 0: the failure does not reach the exit status" >&2
        exit 1
    fi
    echo "red path: FAIL printed and the application exited $app_status (signal $app_signal), as the red build must"
fi
echo "application exit: status $app_status, signal $app_signal ($device/verdict.json)"
echo "matter: $expect as expected"
