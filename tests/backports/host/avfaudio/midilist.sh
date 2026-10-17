#!/bin/sh
# The list form of the MIDI send against the host's own sends: midilist.m, with midilist-record.c interposed on
# MusicDeviceMIDIEvent. The port's CharonMIDIEventList.h is the header both the port's method and the probe use.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../../common/runs.sh" "$here"
build=${AVFAUDIO_MIDILIST_BUILD:-$(runs_folder charon-avfaudio-midilist)}
rm -rf "$build"
mkdir -p "$build"

xcrun clang -dynamiclib -w -framework AudioToolbox "$here/midilist-record.c" -o "$build/librecord.dylib"
xcrun clang -fobjc-arc -Wall -Wno-deprecated-declarations "$here/midilist.m" \
    -framework Foundation -framework AVFoundation -framework AudioToolbox -framework CoreMIDI \
    "$build/librecord.dylib" -o "$build/midilist" 2> "$build/build.err" || { echo "FAIL building midilist"; head -10 "$build/build.err"; exit 1; }
DYLD_INSERT_LIBRARIES="$build/librecord.dylib" "$build/midilist" > "$build/log" 2>&1 && result=0 || result=$?
cat "$build/log"
echo "log=$build/log"
exit "$result"
