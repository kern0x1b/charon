#import "CharonGCSnapshot.h"

// The micro game's V100 structure of iOS 9.0, whose symbols the ladder first exports at 10.0.1 -
// GCMicroGamepad9.m is the tree's own object for the same reason - so this one carries the release
// it is named for and not the release its symbols arrive in.
//
// facts/GameController/Snapshots.md holds the measurements: a zeroed structure encodes as 20 bytes
// beginning 0001 1400, and the reader takes 20 bytes and refuses 21.

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

NSData *NSDataFromGCMicroGamepadSnapShotDataV100(GCMicroGamepadSnapShotDataV100 *snapshotData)
{
    return charon_gc_snapshot_data(snapshotData, sizeof(GCMicroGamepadSnapShotDataV100), GCMicroGamepadSnapshotDataVersion1);
}

BOOL GCMicroGamepadSnapShotDataV100FromNSData(GCMicroGamepadSnapShotDataV100 *snapshotData, NSData *data)
{
    return charon_gc_snapshot_read(snapshotData, data, sizeof(GCMicroGamepadSnapShotDataV100), charon_gc_accept_declared_size);
}
