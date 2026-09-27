#!/bin/sh
# tests/backports/device/<program>.m for the classes the backports carry below iOS 6, as device binaries linked with charon@apple-backports and run
# on emulated releases: the port's answers on 4.3 and 5.0 are held to the release's own on 6.0 (the `answer` lines), and each program's own
# checks must pass. One heavy job (the package's build and an emulated boot a release), so run it in a slot of the machine:
#     $HOME/Git/projects/ios/coordination/heavy.sh sh tests/backports/device/below6/run.sh nsuuid
# BELOW6_RELEASES lists the releases (default "6.0 4.3 5.0"; 6.0 first, the reference); BELOW6_DEVICE names the device (default iPhone2,1, the
# 3GS, which runs every release named here, and iPhone3,1 for 6.0); BELOW6_UIKIT=1 builds the package with UIKit, for a program that needs it;
# BELOW6_BUILD is where the build and the logs go. It needs the addon v0.8.12 in the shared xmake store and the firmware of each release.
# Exits 1 for a program that did not pass, an answer that differs from 6.0's, a run that left no report, and no program named.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
export BELOW6_ROOT=$(cd "$here/../../../.." && pwd)
[ $# -gt 0 ] || { echo "usage: run.sh PROGRAM..."; exit 1; }
releases=${BELOW6_RELEASES:-"6.0 4.3 5.0"}
build=${BELOW6_BUILD:-${TMPDIR:-/tmp}/charon-below6}
rm -rf "$build"
mkdir -p "$build"
cp "$here/xmake.lua" "$here/control" "$build/"
cd "$build"
xmake f -c -p iphoneos -a armv7 -y > configure.log 2>&1 || { echo "CONFIG-FAIL"; tail -5 configure.log; exit 1; }
xmake build -y "$@" > build.log 2>&1 || { echo "BUILD-FAIL"; sed 's/\x1b\[[0-9;]*m//g' build.log | grep -a 'error' | head -10; exit 1; }
failed=0
for program in "$@"; do
    for release in $releases; do
        device=${BELOW6_DEVICE:-iPhone2,1}
        [ -n "${BELOW6_DEVICE:-}" ] || [ "$release" != 6.0 ] || device=iPhone3,1
        xmake emulate -d "$device" -r "$release" install > "install-$release.log" 2>&1 || { echo "$program $release: INSTALL-FAIL"; failed=1; continue; }
        xmake emulate -d "$device" -r "$release" run "/usr/libexec/$program" > "$program-$release.log" 2>&1 || true
        sed 's/\x1b\[[0-9;]*m//g' "$program-$release.log" > "$program-$release.txt"
        # The verdict line names the run - pass, fail, crash, timeout or boot-blocked - between the colour codes.
        if ! grep -Eq "pass.{0,12} on iPhone" "$program-$release.txt" || grep -q '^FAIL' "$program-$release.txt"; then
            echo "$program $release: not a pass"; grep -aE '^FAIL|^fail|^crash|^timeout|^error|blocked' "$program-$release.txt" | head -20
            failed=1
        else
            echo "$program $release: $(grep -aE ": [0-9]+ checks, " "$program-$release.txt") ($(grep -a '^NSUUID comes from\|comes from' "$program-$release.txt" | head -1))"
        fi
        grep -a '^answer ' "$program-$release.txt" > "$program-$release.answers" || true
    done
    # The release's own answers on 6.0 are what the port must give where the release has none.
    for release in $releases; do
        [ "$release" = 6.0 ] && continue
        case " $releases " in *" 6.0 "*) ;; *) continue ;; esac
        if diff "$program-6.0.answers" "$program-$release.answers" > "$program-diff-$release.txt"; then
            echo "$program $release: the $(wc -l < "$program-$release.answers" | tr -d ' ') answers are 6.0's"
        else
            echo "$program $release: answers that are not 6.0's:"; cat "$program-diff-$release.txt"
            failed=1
        fi
    done
done
echo "logs=$build"
exit $failed
