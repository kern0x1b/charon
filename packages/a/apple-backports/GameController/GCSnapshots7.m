#import "CharonGCSnapshot.h"

// The two V100 structures of iOS 7.0: the plain game's and the extended game's. They are one object
// because both symbols of each pair are first exported by the same release - release-split reads the
// built object and says so - and the extended game's V100 structure arrives with the plain game's.
//
// facts/GameController/Snapshots.md holds the measurements: a zeroed structure encodes as 36 bytes
// whose first four are 0001 2400 for the plain game and 60 bytes beginning 0001 3c00 for the extended
// one, and the two readers differ as the table there sets out.

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

NSData *NSDataFromGCGamepadSnapShotDataV100(GCGamepadSnapShotDataV100 *snapshotData)
{
    return charon_gc_snapshot_data(snapshotData, sizeof(GCGamepadSnapShotDataV100), CHARON_GCGAMEPAD_SNAPSHOT_VERSION_V100);
}

BOOL GCGamepadSnapShotDataV100FromNSData(GCGamepadSnapShotDataV100 *snapshotData, NSData *data)
{
    return charon_gc_snapshot_read(snapshotData, data, sizeof(GCGamepadSnapShotDataV100), charon_gc_accept_whole_structure);
}

NSData *NSDataFromGCExtendedGamepadSnapShotDataV100(GCExtendedGamepadSnapShotDataV100 *snapshotData)
{
    return charon_gc_snapshot_data(snapshotData, sizeof(GCExtendedGamepadSnapShotDataV100), GCExtendedGamepadSnapshotDataVersion1);
}

BOOL GCExtendedGamepadSnapShotDataV100FromNSData(GCExtendedGamepadSnapShotDataV100 *snapshotData, NSData *data)
{
    return charon_gc_snapshot_read(snapshotData, data, sizeof(GCExtendedGamepadSnapShotDataV100), charon_gc_accept_declared_size);
}
