#!/bin/sh
# avfaudio — the host behaviour check for the AVFAudio audio-unit family.
#
# Two halves. The first asks the *host's own* real AudioUnits the same questions the port asks its unit,
# so a difference is a difference in the port: the tail time a unit really has, the properties the
# header names, a description that names nothing, whether a narrow read of a Float64 property is
# accepted. The second is a source check over the port's own code, for the things only the port can get
# wrong - a wrong value type, a property invented, a fallback that substitutes a component.
#
# A run that instantiates no host unit fails rather than passing vacuously: the oracle has to be there.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
AVFAUDIO=${AVFAUDIO:-$here/../../../../packages/a/apple-backports/AVFAudio}
build=${AVFAUDIO_HOST_BUILD:-${TMPDIR:-/tmp}/charon-avfaudio-host}
rm -rf "$build"
mkdir -p "$build"
xcrun clang -fobjc-arc -Wall -Wno-deprecated-declarations \
    "$here/checks.m" \
    -framework Foundation -framework AudioToolbox -framework AVFAudio -framework CoreAudio \
    -o "$build/avfaudio-host"
set +e
"$build/avfaudio-host" > "$build/log" 2>&1
result=$?
set -e
grep -v '^ok ' "$build/log" || true
echo "--- the port's own source, for what only it can get wrong ---"
sh "$here/sources.sh" "$AVFAUDIO" | grep -v '^ok ' || true
source_result=${PIPESTATUS[0]:-0}
echo "log=$build/log"
[ "$result" -eq 0 ] || exit "$result"
