#!/bin/sh
# run.sh -- AVSpeechUtterance and its three rate constants, the port against the host, in one binary.
#
# The port's two objects (AVFoundation/AVSpeechUtterance7.m, AVFoundation/AVSpeechConstants7.m) are compiled
# with every name they define renamed to a charon_host_ spelling, and linked beside checks.m, which asks the
# host's own AVSpeechUtterance and the port's the same questions and prints both answers in one process.
#
# Two controls keep the check honest:
#   * checks.m's first line asks the host for its default rate; a probe that is not reading the host fails there;
#   * AVSPEECH_MUTANT=pitch plants a wrong floor for pitchMultiplier in a COPY of the port source and the run
#     must go red. A plant that goes green means the check cannot see the thing it claims to see.
#
# Run directly, not through heavy.sh: two small compiles and one run.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../../common/runs.sh" "$here"
root=$(cd "$here/../../../.." && pwd)
avf=$root/packages/a/apple-backports/AVFoundation
build=$(runs_folder charon-avf-speech)
rm -rf "$build"
mkdir -p "$build/src"

cp "$avf/AVSpeechUtterance7.m" "$avf/AVSpeechConstants7.m" "$build/src/"
mutant=${AVSPEECH_MUTANT:-0}
if [ "$mutant" = pitch ]; then
    sed -i '' 's/pitchMultiplier >= 0.5f) ? pitchMultiplier : 0.5f/pitchMultiplier >= 0.25f) ? pitchMultiplier : 0.25f/' "$build/src/AVSpeechUtterance7.m"
    [ "$(grep -c '0.25f' "$build/src/AVSpeechUtterance7.m")" -eq 1 ] || { echo "FAIL: the planted pitch floor did not apply"; exit 1; }
    echo "planted: pitchMultiplier floor 0.25 in the copy (control: must go red)"
fi

renames="-DAVSpeechUtterance=charon_host_AVSpeechUtterance
-DAVSpeechUtteranceMinimumSpeechRate=charon_host_AVSpeechUtteranceMinimumSpeechRate
-DAVSpeechUtteranceMaximumSpeechRate=charon_host_AVSpeechUtteranceMaximumSpeechRate
-DAVSpeechUtteranceDefaultSpeechRate=charon_host_AVSpeechUtteranceDefaultSpeechRate"
# shellcheck disable=SC2086
for source in AVSpeechUtterance7.m AVSpeechConstants7.m; do
    xcrun clang -fobjc-arc -Wall -Wno-deprecated-declarations $renames -I"$avf" \
        -c "$build/src/$source" -o "$build/${source%.m}.o" 2> "$build/$source.err" || {
            echo "FAIL compiling the port's $source"; head -6 "$build/$source.err"; exit 1; }
done

xcrun clang -fobjc-arc -Wall -Wno-deprecated-declarations "$here/checks.m" \
    "$build/AVSpeechUtterance7.o" "$build/AVSpeechConstants7.o" \
    -framework Foundation -framework AVFAudio -o "$build/avf-speech" 2> "$build/link.err" || {
        echo "FAIL linking the differential"; head -10 "$build/link.err"; exit 1; }

set +e
"$build/avf-speech" > "$build/log" 2>&1
result=$?
set -e
grep -v '^ok ' "$build/log" || true
grep -q '^checks=' "$build/log" || { echo "FAIL: the run printed no checks= line, so nothing was checked"; exit 1; }
echo "log=$build/log"
exit "$result"
