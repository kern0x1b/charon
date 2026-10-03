#import "CharonGC.h"
#import "CharonGCSnapshot.h"

// The two snapshot classes whose symbols the ladder first exports at 9.0, and the one -saveSnapshot
// that shares their release. The plain game's snapshot and its own -saveSnapshot are in GCSnapshots7.m
// with the 7.0 structures; the four current encoding functions and the two version constants are in
// GCSnapshots16.m. What is here is the part the release ladder puts at 9.0.
//
// GCExtendedGamepadSnapshot.h:24 and GCMicroGamepadSnapshot.h:25 mark both classes
// API_DEPRECATED("... has been deprecated, use [GCController controllerWithExtendedGamepad] instead",
// ios(9.0, 13.0)), and the two structures they serialise carry the same mark on their typedefs. That
// mark needs no suppression here, and the reason is worth writing down because three files of this
// library used to carry one for it and it suppressed nothing. A deprecation is diagnosed only where it
// has begun: this port's floor is 6.0, the deprecation starts at 9.0, and so for a binary that deploys
// at 6.0 the API is current and the compiler has nothing to say. Measured with the suppression removed
// and this file compiled the way modules/apple/backports.lua compiles it - zero deprecation
// diagnostics, at the port's own target and at a 14.0 one. The classes are carried from 9.0 and
// stopped at 13.0, which is the header's own chronology and not a choice here.
//
// What a snapshot is, is the header's own: a profile of the game's own elements that holds the values
// it was saved from and answers them again. So the two classes below hold the data and push it through
// the same accessors a live game uses, and the encoding is the structure the header documents - a
// packed layout whose first four bytes are a version and a size.
//
// The oracle is the host's own encoder, not the port's round trip: the `snapshot objects` group of
// tests/backports/host/gamecontroller saves a matrix of values through the port's -saveSnapshot and
// through the host's NSDataFromGCExtendedGamepadSnapshotData / NSDataFromGCMicroGamepadSnapshotData
// for the same values, and compares the encoded bytes. A field read from the wrong element moves a
// byte. The one answer that can be had from the host's own -saveSnapshot is the untouched controller,
// which measures 63 bytes beginning 0101 3f00; facts/GameController/Snapshots.md names both.
//
// What these two classes do NOT do is carry the extended game's own -saveSnapshot, which the SDK
// declares at 7.0 (GCExtendedGamepad.h:65) returning a class that first appears at 9.0: a method's
// implementation emits an objc-class-ref for its return type, and the 6.1.3 band has no 9.0 object to
// satisfy it. That is measured and recorded in coordination/api-queue.md, and the row stays absent.

@implementation GCExtendedGamepadSnapshot {
    NSData *_snapshotData;
}

// The header's own property, at its own ownership: `atomic, copy`. @synthesize rather than
// @dynamic, because the port's build runs with -Werror=objc-missing-property-synthesis and a property
// with no accessor of its own is refused there.
@synthesize snapshotData = _snapshotData;

- (instancetype)initWithSnapshotData:(NSData *)data
{
    GCExtendedGamepadSnapshotData fields;
    memset(&fields, 0, sizeof(fields));
    if (!charon_gc_snapshot_read(&fields, data, sizeof(fields), charon_gc_accept_declared_size))
        return nil;
    self = [super init];
    if (self == nil)
        return nil;
    _snapshotData = [data copy];
    [self charon_applyExtended:&fields];
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

// The decoded values become the game's own elements, so a snapshot read back answers the same numbers
// the data holds. Every pad here writes through its own two axes - GCElements7.m gives a pad its xAxis
// and yAxis, and `charon_setValue:` is declared on GCControllerAxisInput, which a pad does not answer.
- (void)charon_applyExtended:(GCExtendedGamepadSnapshotData *)fields
{
    GCControllerDirectionPad *dpad = (GCControllerDirectionPad *)[self charon_elementNamed:@"Direction Pad"];
    if (dpad != nil) {
        [(GCControllerAxisInput *)dpad.xAxis charon_setValue:fields->dpadX];
        [(GCControllerAxisInput *)dpad.yAxis charon_setValue:fields->dpadY];
    }
    GCControllerDirectionPad *left = (GCControllerDirectionPad *)[self charon_elementNamed:@"Left Thumbstick"];
    if (left != nil) {
        [(GCControllerAxisInput *)left.xAxis charon_setValue:fields->leftThumbstickX];
        [(GCControllerAxisInput *)left.yAxis charon_setValue:fields->leftThumbstickY];
    }
    GCControllerDirectionPad *right = (GCControllerDirectionPad *)[self charon_elementNamed:@"Right Thumbstick"];
    if (right != nil) {
        [(GCControllerAxisInput *)right.xAxis charon_setValue:fields->rightThumbstickX];
        [(GCControllerAxisInput *)right.yAxis charon_setValue:fields->rightThumbstickY];
    }
    NSDictionary *buttons = @{@"Button A": @(fields->buttonA), @"Button B": @(fields->buttonB),
                              @"Button X": @(fields->buttonX), @"Button Y": @(fields->buttonY),
                              @"Left Shoulder": @(fields->leftShoulder),
                              @"Right Shoulder": @(fields->rightShoulder),
                              @"Left Trigger": @(fields->leftTrigger),
                              @"Right Trigger": @(fields->rightTrigger),
                              @"Left Thumbstick Button": @(fields->leftThumbstickButton),
                              @"Right Thumbstick Button": @(fields->rightThumbstickButton)};
    for (NSString *name in buttons)
        [(GCControllerButtonInput *)[self charon_elementNamed:name]
            charon_update:(float)[buttons[name] floatValue]];
}

@end

@implementation GCMicroGamepadSnapshot {
    NSData *_snapshotData;
}

@synthesize snapshotData = _snapshotData;

- (instancetype)initWithSnapshotData:(NSData *)data
{
    GCMicroGamepadSnapshotData fields;
    memset(&fields, 0, sizeof(fields));
    if (!charon_gc_snapshot_read(&fields, data, sizeof(fields), charon_gc_accept_declared_size))
        return nil;
    self = [super init];
    if (self == nil)
        return nil;
    _snapshotData = [data copy];
    [self charon_applyMicro:&fields];
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

// The micro structure has four fields and the micro profile has the four elements they name, so this
// is the direction pad's two axes and two buttons and nothing else.
- (void)charon_applyMicro:(GCMicroGamepadSnapshotData *)fields
{
    GCControllerDirectionPad *dpad = (GCControllerDirectionPad *)[self charon_elementNamed:@"Direction Pad"];
    if (dpad != nil) {
        [(GCControllerAxisInput *)dpad.xAxis charon_setValue:fields->dpadX];
        [(GCControllerAxisInput *)dpad.yAxis charon_setValue:fields->dpadY];
    }
    [(GCControllerButtonInput *)[self charon_elementNamed:@"Button A"] charon_update:fields->buttonA];
    [(GCControllerButtonInput *)[self charon_elementNamed:@"Button X"] charon_update:fields->buttonX];
}

@end

// -saveSnapshot is what the SDK calls on a live game, and it is the same two steps either way: read
// the current values into the structure, and hand the structure to the encoder this file's header
// holds. It is a category because the class itself is implemented in the 7.0 gamepad object
// (GCGamepads7.m) and this object holds only the 9.0 snapshot API.
//
// Only the micro game gets one here. The extended game's method is 7.0 and its return type is 9.0,
// which one object per release cannot hold; the file's header says so and coordination/api-queue.md
// carries the measurement.
@implementation GCMicroGamepad (CharonGCSnapshot9)

- (GCMicroGamepadSnapshot *)saveSnapshot
{
    GCMicroGamepadSnapshotData fields;
    memset(&fields, 0, sizeof(fields));
    GCControllerDirectionPad *dpad = (GCControllerDirectionPad *)[self charon_elementNamed:@"Direction Pad"];
    fields.dpadX = charon_gc_pad_axis(dpad, @selector(xAxis));
    fields.dpadY = charon_gc_pad_axis(dpad, @selector(yAxis));
    fields.buttonA = charon_gc_button_value([self charon_elementNamed:@"Button A"]);
    fields.buttonX = charon_gc_button_value([self charon_elementNamed:@"Button X"]);
    return [[GCMicroGamepadSnapshot alloc]
               initWithSnapshotData:charon_gc_snapshot_data(&fields, sizeof(fields),
                                                            GCMicroGamepadSnapshotDataVersion1)];
}

@end
