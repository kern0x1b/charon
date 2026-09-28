#!/bin/sh
# run.sh — the drop-routing order test on an emulated device: the test as a command-line program
# (an app started by xmake emulate never reaches its launch callback), built for armv7 against the
# port's own objects, run on 6.1.3 through the fast lane of heavy.sh. It prints the guest's own
# MATCH lines for the two views, and leaves the boot log beside it.
#
#     $HOME/Git/projects/ios/coordination/heavy.sh sh tests/backports/host/dragdroprouting/run.sh
#
# DDR_ROOT names the port's checkout; the sources are taken from it by path, so the port is never
# installed as the addon (charon/AGENTS.md, Traps).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=${DDR_ROOT:-$here/../../../..}
build=${DDR_BUILD:-${TMPDIR:-/tmp}/charon-ddr-device}
device=${DDR_DEVICE:-iPhone4,1}
releases=${DDR_RELEASES:-"6.1.3"}
export DDR_ROOT=$root
rm -rf "$build"
mkdir -p "$build"
cp "$here/xmake.lua" "$here/control" "$build/"
cd "$build"
xmake f -p iphoneos -a armv7 -y > configure.log 2>&1
xmake build -y > build.log 2>&1
failed=0
for release in $releases; do
    DDR_ROOT=$root xmake emulate -d "$device" -r "$release" install > "install-$release.log" 2>&1
    set +e
    DDR_ROOT=$root xmake emulate -d "$device" -r "$release" -k run /usr/libexec/dragdroprouting > "$release.log" 2>&1
    status=$?
    set -e
    # 137 is SIGKILL, and a memory-starved machine kills things: that is a host that never got to
    # the guest, not a verdict on the test, and it is reported as neither a pass nor a fail.
    if [ "$status" -eq 137 ]; then
        echo "$release: killed (status 137) before the guest ran -- the machine was out of memory, not a verdict"
        failed=1
    elif [ "$status" -eq 0 ] && grep -Eq 'pass.{0,12} on iPhone' "$release.log"; then
        echo "$release: pass"
    else
        echo "$release: not a pass (status $status)"
        grep -aE '^FAIL|fail|crash|timeout|blocked|RED' "$release.log" || true
        failed=1
    fi
    # The guest's own log: what it was asked, in what order, and its verdict on the two sequences.
    # The runner carries the program's stdout only in its own log file, so the checks' own lines --
    # "ok <name>" and "FAIL <name>" -- are read back out of the image, which -k kept.
    DDR_ROOT=$root xmake emulate -d "$device" -r "$release" log > "guest-$release.log" 2>&1 || true
    grep -aE 'MATCH|RED|^FAIL|^asked|^ok ' "guest-$release.log" || true
done
exit $failed
