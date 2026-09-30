#import "CharonGCSnapshot.h"
#import "CharonGC.h"
#import <objc/message.h>

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

// GCGamepadSnapshot and the two saveSnapshot methods, all three first exported by iOS 7.0, so they are
// in this object and not in the 9.0 one. The extended method RETURNS GCExtendedGamepadSnapshot, which
// first appears at 9.0: the SDK's own GCExtendedGamepad.h declares the method at 7.0 with that return
// type, and the port reproduces the declaration rather than the chronology, so release-split is
// satisfied by the method's own first appearance at 7.0. GCExtendedGamepadSnapshot is forward-declared
// below for that reason and is not defined by this object.

@class GCExtendedGamepadSnapshot;

// The value a button reads, and an axis, on a machine where nothing is attached. There is no controller
// and no element, so every value is zero - and a zeroed structure is exactly what the encoder above
// was measured on: 36 bytes beginning 0001 2400 for the plain game and 60 beginning 0001 3c00 for the
// extended one. A nil element reads zero rather than being sent a message it cannot answer.
// The read is a typed send rather than [element value], because several classes the port declares answer
// a selector of that name with a different type and the compiler refuses to pick one. Asking the
// element whether it answers the selector first is what makes a missing element read zero.
static float CharonGCReadFloat(id element, SEL which);

static float CharonGCButtonValue(id element)
{
    return CharonGCReadFloat(element, @selector(value));
}

static float CharonGCReadFloat(id element, SEL which)
{
    if (element == nil || ![element respondsToSelector:which])
        return 0.0f;
    float (*read)(id, SEL) = (float (*)(id, SEL))objc_msgSend;
    return read(element, which);
}

@implementation GCGamepadSnapshot {
    NSData *_snapshotData;
}

@synthesize snapshotData = _snapshotData;

// The data is kept as given and the structure is decoded through the reader this object already ships,
// which is the one measured to refuse a whole-structure read of fewer than 36 bytes and a version of
// zero. Refusing that data is what the host does, so an init that cannot read it answers nil rather
// than building a snapshot whose values are not the ones in the data.
- (instancetype)initWithSnapshotData:(NSData *)data
{
    GCGamepadSnapShotDataV100 v100;
    memset(&v100, 0, sizeof(v100));
    if (!GCGamepadSnapShotDataV100FromNSData(&v100, data))
        return nil;
    self = [super init];
    if (self == nil)
        return nil;
    _snapshotData = [data copy];
    [self charon_applyV100:&v100];
    return self;
}

- (instancetype)initWithController:(GCController *)controller snapshotData:(NSData *)data
{
    self = [self initWithSnapshotData:data];
    if (self == nil)
        return nil;
    [self charon_setController:controller];
    return self;
}

// The decoded values become the gamepad's own elements, so a snapshot read back answers the same
// numbers the data holds.
- (void)charon_applyV100:(GCGamepadSnapShotDataV100 *)v100
{
    GCControllerDirectionPad *dpad = (GCControllerDirectionPad *)[self charon_elementNamed:@"Direction Pad"];
    if (dpad != nil) {
        [(GCControllerAxisInput *)dpad charon_setValue:v100->dpadX];
        [(GCControllerAxisInput *)dpad charon_setValue:v100->dpadY];
    }
    NSDictionary *buttons = @{@"Button A": @(v100->buttonA), @"Button B": @(v100->buttonB),
                              @"Button X": @(v100->buttonX), @"Button Y": @(v100->buttonY),
                              @"Left Shoulder": @(v100->leftShoulder),
                              @"Right Shoulder": @(v100->rightShoulder)};
    for (NSString *name in buttons)
        [(GCControllerButtonInput *)[self charon_elementNamed:name]
            charon_update:(float)[buttons[name] floatValue]];
}

@end

// -saveSnapshot is what the SDK calls on a live gamepad, and it is the same two steps either way: read
// the current values into the structure, and hand the structure to the encoder this object ships. It is
// a category because the class itself is implemented in the 7.0 gamepad object and this object holds
// only the snapshot API.
@implementation GCGamepad (CharonGCSnapshot7)

- (GCGamepadSnapshot *)saveSnapshot
{
    GCGamepadSnapShotDataV100 v100;
    memset(&v100, 0, sizeof(v100));
    v100.version = CHARON_GCGAMEPAD_SNAPSHOT_VERSION_V100;
    v100.size = (uint16_t)sizeof(v100);
    id dpad = [self charon_elementNamed:@"Direction Pad"];
    v100.dpadX = CharonGCReadFloat(dpad, @selector(xAxis));
    v100.dpadY = CharonGCReadFloat(dpad, @selector(yAxis));
    v100.buttonA = CharonGCButtonValue([self charon_elementNamed:@"Button A"]);
    v100.buttonB = CharonGCButtonValue([self charon_elementNamed:@"Button B"]);
    v100.buttonX = CharonGCButtonValue([self charon_elementNamed:@"Button X"]);
    v100.buttonY = CharonGCButtonValue([self charon_elementNamed:@"Button Y"]);
    v100.leftShoulder = CharonGCButtonValue([self charon_elementNamed:@"Left Shoulder"]);
    v100.rightShoulder = CharonGCButtonValue([self charon_elementNamed:@"Right Shoulder"]);
    return [[GCGamepadSnapshot alloc] initWithSnapshotData:NSDataFromGCGamepadSnapShotDataV100(&v100)];
}

@end

