// kMIDIPropertyUMPActiveGroupBitmap and kMIDIPropertyUMPCanTransmitGroupless, of iOS 17: the two UMP properties of an
// endpoint, the groups it has active and whether it can send without a group. macOS CoreMIDI gives them the values
// below (oracle/constants.m reads them from the framework, measured 2026-10-09). The release has no UMP endpoint,
// so no endpoint of this port carries these properties from the release's side; the constants exist for the
// application that names them.
#import <CoreMIDI/CoreMIDI.h>

const CFStringRef kMIDIPropertyUMPActiveGroupBitmap = NULL;
const CFStringRef kMIDIPropertyUMPCanTransmitGroupless = NULL;
