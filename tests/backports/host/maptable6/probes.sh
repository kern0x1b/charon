#!/bin/sh
# The two probes the facts cite, as device binaries under xmake emulate (one heavy job):
#     $HOME/Git/projects/ios/coordination/heavy.sh sh tests/backports/host/maptable6/probes.sh
# enumprobe (probes/enum.m): the owner enumerating keys while others drop keys and values, on 5.1.1 (clean) and 4.3 (SIGSEGV).
# weakprobe (probes/weak.m): __weak to the classes that keep their own retain count, on 5.0, 5.1.1, 6.0 and 4.3 (aborts there).
# The verdicts are read, not asserted: a crash on 4.3 is what the facts say. Logs in $MAPTABLE6_BUILD.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
export MAPTABLE6_ROOT=$(cd "$here/../../../.." && pwd)
export MAPTABLE6_PROBES=1
build=${MAPTABLE6_BUILD:-${TMPDIR:-/tmp}/charon-maptable6-probes}
device=${MAPTABLE6_DEVICE:-iPhone2,1}
rm -rf "$build"
mkdir -p "$build"
cp "$here/emulate/xmake.lua" "$here/emulate/control" "$here/emulate/control-enum" "$here/emulate/control-weak" "$build/"
cd "$build"
xmake f -p iphoneos -a armv7 -y > configure.log 2>&1
xmake build -y > build.log 2>&1
for release in 5.0 5.1.1 6.0 4.3; do
    xmake emulate -d "$device" -r "$release" install > "install-$release.log" 2>&1
    for probe in enumprobe weakprobe; do
        [ "$probe" = enumprobe ] && [ "$release" != 5.1.1 ] && [ "$release" != 4.3 ] && continue
        xmake emulate -d "$device" -r "$release" run /usr/libexec/$probe > "$probe-$release.log" 2>&1 || true
        echo "== $probe $release"; sed 's/\x1b\[[0-9;]*m//g' "$probe-$release.log" | grep -E '^[A-Za-z]+: |checks,|pass|crash|fail|Cannot|cannot' | cut -c1-200
    done
done
echo "logs=$build"
