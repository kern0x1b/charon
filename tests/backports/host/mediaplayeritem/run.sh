#!/bin/sh
# Build and run the probe, and never run anything but what was just built: a compile that fails must not
# leave the previous binary on screen to be read as this one's output, which is how two earlier runs of this
# probe reported numbers its source had never produced.
#
#     sh run.sh /path/to/iPhoneOS26.2.sdk/.../MediaPlayer.framework/Headers/MPMediaItem.h
set -eu
here=$(cd "$(dirname "$0")" && pwd)
bin=${TMPDIR:-/tmp}/mpitem-probe-$$
rm -f "$bin"
xcrun clang -fobjc-arc -framework Foundation -framework MediaPlayer -o "$bin" "$here/probe.m"
"$bin" "$@"
status=$?
rm -f "$bin"
exit $status
