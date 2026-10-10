#!/bin/sh
# Differential test of the CoreMIDI translation (packages/a/apple-backports/CoreMIDI) against macOS CoreMIDI:
# the answers macOS gave the oracle (coremidi-expectations.h, from oracle/batch.m) and the probes in
# differential.m. The API files are compiled too, with their functions renamed, so a file that stops compiling
# stops this run instead of hiding in the library.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
CORE=${COREMIDI:-$here/../../../../packages/a/apple-backports/CoreMIDI}
build=${COREMIDI_BUILD:-${TMPDIR:-/tmp}/charon-coremidi-host}
# COREMIDI_SANITIZE=address builds the library and the differential with AddressSanitizer: the buffer overruns of the
# packet readers (MIDISysex17.m) are found by that build, not by the answers.
sanitize=""
if [ -n "${COREMIDI_SANITIZE:-}" ]; then sanitize="-fsanitize=$COREMIDI_SANITIZE -g"; fi
rm -rf "$build"
mkdir -p "$build"
renames=""
for name in MIDIEventListInit MIDIEventListAdd MIDIClientCreateWithBlock MIDIInputPortCreateWithBlock \
    MIDIDestinationCreateWithBlock MIDIInputPortCreateWithProtocol MIDIDestinationCreateWithProtocol \
    MIDISourceCreateWithProtocol MIDISendEventList MIDIReceivedEventList \
    MIDIEventListForEachEvent MIDIEventPacketSysexBytesForGroup MIDIDeviceNewEntity \
    MIDI2DeviceInfo MIDIUMPFunctionBlock MIDIUMPMutableFunctionBlock MIDIUMPEndpoint MIDIUMPMutableEndpoint \
    MIDIUMPEndpointManager MIDICIDevice MIDIUMPCIProfile MIDICIDeviceManager \
    MIDICIDeviceInfo MIDICIProfile MIDICIProfileState MIDICISession MIDICIDiscoveredNode MIDICIDiscoveryManager \
    MIDICIResponder \
    MIDISendUMPSysex MIDISendUMPSysex8 \
    kMIDIPropertyUMPActiveGroupBitmap kMIDIPropertyUMPCanTransmitGroupless kMIDIPropertyAssociatedEndpoint \
    MIDICIDeviceObjectKey MIDICIProfileObjectKey MIDIUMPEndpointObjectKey MIDIUMPFunctionBlockObjectKey \
    MIDICIDeviceWasAddedNotification MIDICIDeviceWasRemovedNotification MIDICIProfileWasRemovedNotification \
    MIDICIProfileWasUpdatedNotification MIDIUMPEndpointWasAddedNotification MIDIUMPEndpointWasRemovedNotification \
    MIDIUMPEndpointWasUpdatedNotification MIDIUMPFunctionBlockWasUpdatedNotification; do
    renames="$renames -D$name=charon_host_$name"
done
for path in "$CORE"/*.m; do
    source=$(basename "$path")
    xcrun clang $sanitize -fobjc-arc -fvisibility=hidden -w -I"$CORE" -DCHARON_HOST_HAS_UMP_SYSEX=1 $renames -c "$path" -o "$build/$source.o"
done
xcrun clang $sanitize -c -w -I"$CORE" -DCHARON_HOST_HAS_UMP_SYSEX=1 "$CORE/CharonCoreMIDI.c" -o "$build/CharonCoreMIDI.o"
xcrun clang $sanitize -fobjc-arc -Wall -Wno-deprecated-declarations -DCHARON_HOST_HAS_UMP_SYSEX=1 -I"$CORE" -I"$here" $renames \
    "$here/differential.m" "$here/differential-ump.m" "$build/CharonCoreMIDI.o" "$build"/*.m.o -framework Foundation -framework CoreMIDI -framework CoreBluetooth -o "$build/differential"
"$build/differential" > "$build/log" 2>&1 && result=0 || result=$?
grep -v '^ok ' "$build/log" || true
echo "log=$build/log"
exit $result
