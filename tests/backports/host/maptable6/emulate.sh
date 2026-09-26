#!/bin/sh
# tests/backports/host/maptable6 as a device binary under xmake emulate: the port against the release's own factories on
# 6.0, and the port alone on 4.3 and 5.1.1, whose answers to the weak scenarios must be 6.0's. One heavy job (a build and
# three emulated boots), so run it in a slot of the machine:
#     $HOME/Git/projects/ios/coordination/heavy.sh sh tests/backports/host/maptable6/emulate.sh
# MAPTABLE6_ROUNDS=n sets the rounds of the two-thread check (default 20000). It needs the addon v0.8.10 in the shared xmake store, as any port does, and the firmware of the releases named below.
# Leaves the logs in $MAPTABLE6_BUILD/<release>.log and exits 1 on a failed check or an answer that is not 6.0's.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
export MAPTABLE6_ROOT=$(cd "$here/../../../.." && pwd)
build=${MAPTABLE6_BUILD:-${TMPDIR:-/tmp}/charon-maptable6-device}
device=${MAPTABLE6_DEVICE:-iPhone2,1}
releases=${MAPTABLE6_RELEASES:-"6.0 4.3 5.1.1"}
rm -rf "$build"
mkdir -p "$build"
cp "$here/emulate/xmake.lua" "$here/emulate/control" "$build/"
cd "$build"
xmake f -p iphoneos -a armv7 -y > configure.log 2>&1
xmake build -y > build.log 2>&1
failed=0
for release in $releases; do
    xmake emulate -d "$device" -r "$release" install > "install-$release.log" 2>&1
    xmake emulate -d "$device" -r "$release" run /usr/libexec/maptable6 > "$release.log" 2>&1 || true
    # The verdict line names the run - pass, fail, crash, timeout or boot-blocked - between colour codes.
    if ! grep -Eq 'pass.{0,12} on iPhone' "$release.log" || grep -q '^FAIL' "$release.log"; then
        echo "$release: not a pass"; grep -E '^FAIL|fail|crash|timeout|blocked' "$release.log" || true
        failed=1
    else
        echo "$release: $(grep -E ' checks, ' "$release.log")"
    fi
done
# The release's own answers on 6.0 are what the port must give where the release has none.
for release in $releases; do
    [ "$release" = 6.0 ] && continue
    grep '^release ' 6.0.log | sed 's/^release /port /' > expected.txt
    grep '^port ' "$release.log" > answered.txt
    if diff expected.txt answered.txt > "diff-$release.txt"; then
        echo "$release: the port's $(wc -l < answered.txt | tr -d ' ') answers are 6.0's"
    else
        echo "$release: answers that are not 6.0's:"; cat "diff-$release.txt"
        failed=1
    fi
done
echo "logs=$build"
exit $failed
