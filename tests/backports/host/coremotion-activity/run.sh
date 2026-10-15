#!/bin/sh
# run.sh - the port's CoreMotion activity classes against the host's own CoreMotion, case by case, in two processes.
#
#   1. differential.m is COMPILED against the host's CoreMotion (Catalyst, the macOS 27.0 SDK) and run once per case
#   2. the same source is COMPILED against the port's CMMotionActivity.m and CMMotionActivityManager.m, with the test-only
#      CMLogItem stub, and run once per case
#   3. the two outputs of each case are compared; a case where the host dies on a signal is named as such and is not
#      counted as agreement
#   4. two plants on a scratch copy of the port's manager - an availability answer flipped, and an authorization flipped -
#      each must turn case 0 red
#
# Two processes, not one, because both sides define the same classes.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
appledir=${APPLEDIR:-$here/../../../../packages/a/apple-backports}
build=${BUILD:-$here/../../../../.agent-work/runs/coremotion-activity}
mkdir -p "$build"
sdk=$(xcrun --sdk macosx --show-sdk-path)
target=arm64-apple-ios17.0-macabi
cases="0 1 2 3 4 5 6 7"

xcrun clang -fobjc-arc -w -target "$target" -isysroot "$sdk" -framework Foundation -framework CoreMotion \
    "$here/differential.m" -o "$build/host"
xcrun clang -fobjc-arc -w -target "$target" -isysroot "$sdk" -DPORT -framework Foundation \
    "$here/differential.m" "$appledir/CoreMotion/CMMotionActivity.m" "$appledir/CoreMotion/CMMotionActivityManager.m" \
    "$here/cmlogitem-stub.m" -o "$build/port"

differs=0
crashed=0
compare() {
    # compare <label> <port-binary> <case...>
    label=$1; port=$2; shift 2
    for n in "$@"; do
        set +e
        "$build/host" "$n" > "$build/host.$n.out" 2>/dev/null; hs=$?
        "$port" "$n" > "$build/port.$n.out" 2>/dev/null; ps=$?
        set -e
        if [ "$hs" -ge 128 ]; then
            crashed=$((crashed + 1))
            echo "case $n: HOST CRASHED (signal $((hs - 128))), not comparable; port exit $ps: $(head -1 "$build/port.$n.out")"
            continue
        fi
        if [ "$ps" -ne 0 ] || [ "$hs" -ne 0 ]; then
            differs=$((differs + 1))
            echo "case $n: DIFFERS ($label): host exit $hs, port exit $ps"
            continue
        fi
        if cmp -s "$build/host.$n.out" "$build/port.$n.out"; then
            echo "case $n: EQUAL"
        else
            differs=$((differs + 1))
            echo "case $n: DIFFERS ($label)"
            diff "$build/host.$n.out" "$build/port.$n.out" | sed 's/^/    /' || true
        fi
    done
}

echo "--- the clean run"
compare clean "$build/port" $cases

# A plant is a copy of the port's manager with one change; each must make case 0 differ. Each is written into its own
# directory so a harness that copied only one file would fail to build rather than measure nothing.
plant() {
    label=$1; expr=$2
    rm -rf "$build/mutant"; mkdir -p "$build/mutant"
    sed "$expr" "$appledir/CoreMotion/CMMotionActivityManager.m" > "$build/mutant/CMMotionActivityManager.m"
    if cmp -s "$appledir/CoreMotion/CMMotionActivityManager.m" "$build/mutant/CMMotionActivityManager.m"; then
        echo "MUTATION DID NOT APPLY: $label"
        differs=$((differs + 1000))
        return
    fi
    xcrun clang -fobjc-arc -w -target "$target" -isysroot "$sdk" -DPORT -framework Foundation \
        "$here/differential.m" "$appledir/CoreMotion/CMMotionActivity.m" "$build/mutant/CMMotionActivityManager.m" \
        "$here/cmlogitem-stub.m" -o "$build/port-mutant"
    set +e
    "$build/port-mutant" 0 > "$build/port-mutant.0.out" 2>/dev/null
    set -e
    if cmp -s "$build/host.0.out" "$build/port-mutant.0.out"; then
        echo "MUTANT SURVIVED: $label"
        differs=$((differs + 1000))
    else
        echo "  caught: $label"
    fi
}

echo "--- the plants"
plant "availability NO flipped to YES" 's/    return NO;/    return YES;/'
plant "authorization NotDetermined flipped to Denied" 's/CMAuthorizationStatusNotDetermined;/CMAuthorizationStatusDenied;/'

echo "--- verdict: $differs difference(s) among comparable cases, $crashed host crash(es) not comparable"
[ "$differs" -eq 0 ]
