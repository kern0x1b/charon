#!/bin/sh
# tests/backports/device/display-probe.m on an emulated release, built for every combination of the two things a build decides:
# the binary's apple_minimum (4.3, and the release's own where that is a different one) and charon@apple-backports linked or not
# (facts/UIKit/UIDynamicAnimator.md M3). One heavy job, so run it in a slot of the machine:
#     $HOME/Git/projects/ios/coordination/heavy.sh sh tests/backports/device/display-probe/run.sh 6.1.3
# DISPLAYPROBE_DEVICE names the emulated device (default iPhone3,1, and iPhone4,1 for 6.1.3: the device the release's other device
# programs use); the display the process finds depends on it as well as on the release (facts M3), so a run names both.
# DISPLAYPROBE_CELLS lists the `minimum:package` cells to build (default every one), e.g. "4.3:0 6.0:1".
# Arguments: the release (4.3, 5.1.1, 6.0 or 6.1.3), then optionally the modes to run, each in quotes, `screen view` and so on
# (default: "screen" "screen view" "screen window" "screen turn"; a mode may be named twice, to see whether a run repeats). Each mode is a run of its own, since a display link that
# faults ends the process. DISPLAYPROBE_BUILD is where the builds and the logs go (default a directory of the system temp path);
# copy what a fact cites out of it before it is wiped.
# It needs the addon v0.8.11 in the shared xmake store and the firmware of the release, as any port does.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
export DISPLAYPROBE_ROOT=$(cd "$here/../../../.." && pwd)
release=${1:?release}
shift
[ $# -gt 0 ] || set -- "screen" "screen view" "screen window" "screen turn"
device=${DISPLAYPROBE_DEVICE:-iPhone3,1}
[ -n "${DISPLAYPROBE_DEVICE:-}" ] || [ "$release" != 6.1.3 ] || device=iPhone4,1
build=${DISPLAYPROBE_BUILD:-${TMPDIR:-/tmp}/charon-display-probe}/$release-$device
failed=0
minimums=$release
[ "$release" = 4.3 ] || minimums="4.3 $release"
for minimum in $minimums; do
    for package in 0 1; do
        # Below 6.1.3 the package's weak imports are refused by the release, which the target waives; with the package linked
        # and the minimum 4.3, the binary asks for the libraries of the 4.3 band.
        case " ${DISPLAYPROBE_CELLS:-$minimum:$package} " in *" $minimum:$package "*) ;; *) continue ;; esac
        cell=$build/min-$minimum-pkg-$package
        rm -rf "$cell"
        mkdir -p "$cell"
        cp "$here/xmake.lua" "$here/control" "$cell/"
        (
            cd "$cell"
            export DISPLAYPROBE_MINIMUM=$minimum DISPLAYPROBE_PACKAGE=$package
            xmake f -c -p iphoneos -a armv7 -y > configure.log 2>&1 || { echo "min $minimum pkg $package: CONFIG-FAIL"; tail -5 configure.log; exit 1; }
            xmake build -y > build.log 2>&1 || { echo "min $minimum pkg $package: BUILD-FAIL"; tail -5 build.log; exit 1; }
            xmake emulate -d $device -r "$release" install > install.log 2>&1 || { echo "min $minimum pkg $package: INSTALL-FAIL"; exit 1; }
            n=0
            for mode in "$@"; do
                n=$((n + 1))
                name=$n-$(echo "$mode" | tr ' ' '-')
                # A run that faults exits non-zero and is the datum; its log says what happened.
                xmake emulate -d $device -r "$release" run /usr/libexec/display-probe $mode > "run-$name.log" 2>&1 || true
                echo "== $release on $device, apple_minimum $minimum, package $package, $mode: $(sed 's/\x1b\[[0-9;]*m//g' "run-$name.log" | grep -a '^UIScreen screens\|^display link\|^FAULT\|^a UI\|^a CAT\|^waited\|^pass\|^fail\|^crash\|^timeout\|^error' | tr '\n' '|')"
            done
        ) || failed=1
    done
done
echo "logs=$build"
exit $failed
