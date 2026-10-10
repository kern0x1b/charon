#!/bin/sh
# Differential test of the CoreMIDI translation (packages/a/apple-backports/CoreMIDI) against macOS CoreMIDI:
# every answer macOS gave the oracle (oracle/batch-up.txt and oracle/batch-down.txt, from oracle/batch.m) and the probes in
# differential.m. The API files are compiled too, with their functions renamed, so a file that stops compiling
# stops this run instead of hiding in the library.
#
# The host-probe rule (prefs-bracket.sh states it): the differential makes process-lifetime virtual endpoints and connects
# ports to them, and nothing that persists. The whole run is bracketed by a read-only digest of the persistent MIDI
# preferences (the ByHost com.apple.MIDI plist and ~/Library/Audio/MIDI Configurations); the run fails when the digest differs,
# and the check proves first that it can fail (selftest).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
if [ -z "${COREMIDI_BRACKETED:-}" ]; then
    sh "$here/prefs-bracket.sh" selftest
    COREMIDI_BRACKETED=1 exec sh "$here/prefs-bracket.sh" run sh "$here/run.sh" "$@"
fi
CORE=${COREMIDI:-$here/../../../../packages/a/apple-backports/CoreMIDI}
# The build folder is a run folder of this checkout (.agent-work/runs), never the system temp directory.
build=${COREMIDI_BUILD:-$here/../../../../.agent-work/runs/coremidi-host}
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
    xcrun clang $sanitize -fobjc-arc -fvisibility=hidden -Wall -Werror -I"$CORE" $renames -c "$path" -o "$build/$source.o"
done
xcrun clang $sanitize -c -Wall -Werror -I"$CORE" "$CORE/CharonCoreMIDI.c" -o "$build/CharonCoreMIDI.o"
# differential-ports.m is compiled without the renames: it calls the release's own MIDISendEventList and friends as the oracle.
xcrun clang $sanitize -fobjc-arc -Wall -Wno-deprecated-declarations -I"$CORE" -c \
    "$here/differential-ports.m" -o "$build/differential-ports.o"
xcrun clang $sanitize -fobjc-arc -Wall -Wno-deprecated-declarations -I"$CORE" -I"$here" -I"$here/oracle" $renames \
    "$here/differential.m" "$here/differential-ump.m" "$build/differential-ports.o" "$build/CharonCoreMIDI.o" "$build"/*.m.o -framework Foundation -framework CoreMIDI -framework CoreBluetooth -o "$build/differential"
"$build/differential" "$here/oracle" > "$build/log" 2>&1 && result=0 || result=$?
awk '!/^ok /' "$build/log"
echo "log=$build/log"
# The request of MIDISendUMPSysex, against a release that completes the send before it returns (ownership.m): the
# MIDISendSysex of MIDISysex17.m is renamed to the stand-in, and nothing is linked from the release for it.
xcrun clang $sanitize -fobjc-arc -Wall -Wno-deprecated-declarations \
    -DMIDISendSysex=charon_test_MIDISendSysex -I"$CORE" -I"$here" "$here/ownership.m" "$CORE/MIDISysex17.m" \
    "$build/CharonCoreMIDI.o" "$build/CharonMIDIPorts.m.o" -framework Foundation -framework CoreMIDI -o "$build/ownership"
"$build/ownership" > "$build/ownership.log" 2>&1 && owner=0 || owner=$?
cat "$build/ownership.log"
# MIDIDeviceNewEntity against stand-ins for the three release calls it makes (entity.m): the host forbids a real entity, and the
# release cannot be made to refuse the protocol. MIDIDevice14.m is compiled again here with those calls renamed.
xcrun clang $sanitize -fobjc-arc -Wall -Wno-deprecated-declarations \
    -DMIDIDeviceNewEntity=charon_test_MIDIDeviceNewEntity -DMIDIDeviceAddEntity=charon_test_MIDIDeviceAddEntity \
    -DMIDIObjectSetIntegerProperty=charon_test_MIDIObjectSetIntegerProperty -DMIDIDeviceRemoveEntity=charon_test_MIDIDeviceRemoveEntity \
    -I"$CORE" -I"$here" "$here/entity.m" "$CORE/MIDIDevice14.m" -framework Foundation -framework CoreMIDI -o "$build/entity"
"$build/entity" > "$build/entity.log" 2>&1 && entity=0 || entity=$?
cat "$build/entity.log"
# The rows of CharonMIDIPorts.m against a release that gives a disposed reference to a new object (staleness.m): the three
# release calls the rows make (the read of an object's property, the write of the library's stamp and the creation of a virtual
# destination) are renamed to stand-ins,
# in the file and in the test.
xcrun clang $sanitize -fobjc-arc -Wall -Wno-deprecated-declarations \
    -DMIDIObjectGetIntegerProperty=charon_test_MIDIObjectGetIntegerProperty \
    -DMIDIObjectSetIntegerProperty=charon_test_MIDIObjectSetIntegerProperty \
    -DMIDIDestinationCreate=charon_test_MIDIDestinationCreate -I"$CORE" -I"$here" \
    "$here/staleness.m" "$CORE/CharonMIDIPorts.m" "$build/CharonCoreMIDI.o" -framework Foundation -framework CoreMIDI -o "$build/staleness"
"$build/staleness" > "$build/staleness.log" 2>&1 && stale=0 || stale=$?
cat "$build/staleness.log"
for step in "$owner" "$entity" "$stale"; do
    if [ "$result" -eq 0 ]; then result=$step; fi
done
exit $result
