#import "CharonGC.h"

@implementation CharonGCTables

+ (NSArray *)extendedSpecs
{
    static NSArray *specs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        specs = @[
            @{@"kind": @"dpad", @"aliases": @[@"Direction Pad"], @"local": @"Direction Pad", @"unmappedLocal": @"Direction Pad", @"sf": @"dpad", @"unmappedSf": @"dpad", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @0},
            @{@"kind": @"dpad", @"aliases": @[@"Left Thumbstick"], @"local": @"Left Thumbstick", @"unmappedLocal": @"Left Thumbstick", @"sf": @"l.joystick", @"unmappedSf": @"l.joystick", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @1},
            @{@"kind": @"dpad", @"aliases": @[@"Right Thumbstick"], @"local": @"Right Thumbstick", @"unmappedLocal": @"Right Thumbstick", @"sf": @"r.joystick", @"unmappedSf": @"r.joystick", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @2},
            @{@"kind": @"button", @"aliases": @[@"Button Menu"], @"local": @"Menu Button", @"unmappedLocal": @"Menu Button", @"sf": @"line.horizontal.3.circle", @"unmappedSf": @"line.horizontal.3.circle", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @3},
            @{@"kind": @"button", @"aliases": @[@"Button Home"], @"local": @"Home Button", @"unmappedLocal": @"Home Button", @"sf": @"house.circle", @"unmappedSf": @"house.circle", @"analog": @1, @"system": @1, @"collection": [NSNull null], @"order": @4},
            @{@"kind": @"button", @"aliases": @[@"Button A"], @"local": @"A Button", @"unmappedLocal": @"A Button", @"sf": @"a.circle", @"unmappedSf": @"a.circle", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @5},
            @{@"kind": @"button", @"aliases": @[@"Button B"], @"local": @"B Button", @"unmappedLocal": @"B Button", @"sf": @"b.circle", @"unmappedSf": @"b.circle", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @6},
            @{@"kind": @"button", @"aliases": @[@"Button X"], @"local": @"X Button", @"unmappedLocal": @"X Button", @"sf": @"x.circle", @"unmappedSf": @"x.circle", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @7},
            @{@"kind": @"button", @"aliases": @[@"Button Y"], @"local": @"Y Button", @"unmappedLocal": @"Y Button", @"sf": @"y.circle", @"unmappedSf": @"y.circle", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @8},
            @{@"kind": @"button", @"aliases": @[@"Left Shoulder"], @"local": @"L1 Button", @"unmappedLocal": @"L1 Button", @"sf": @"l1.rectangle.roundedbottom", @"unmappedSf": @"l1.rectangle.roundedbottom", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @9},
            @{@"kind": @"button", @"aliases": @[@"Right Shoulder"], @"local": @"R1 Button", @"unmappedLocal": @"R1 Button", @"sf": @"r1.rectangle.roundedbottom", @"unmappedSf": @"r1.rectangle.roundedbottom", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @10},
            @{@"kind": @"button", @"aliases": @[@"Left Trigger"], @"local": @"L2 Button", @"unmappedLocal": @"L2 Button", @"sf": @"l2.rectangle.roundedtop", @"unmappedSf": @"l2.rectangle.roundedtop", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @11},
            @{@"kind": @"button", @"aliases": @[@"Right Trigger"], @"local": @"R2 Button", @"unmappedLocal": @"R2 Button", @"sf": @"r2.rectangle.roundedtop", @"unmappedSf": @"r2.rectangle.roundedtop", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @12},
            @{@"kind": @"button", @"aliases": @[@"Left Thumbstick Button"], @"local": @"Left Thumbstick Button", @"unmappedLocal": @"Left Thumbstick Button", @"sf": @"l.joystick.down", @"unmappedSf": @"l.joystick.down", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @13},
            @{@"kind": @"button", @"aliases": @[@"Right Thumbstick Button"], @"local": @"Right Thumbstick Button", @"unmappedLocal": @"Right Thumbstick Button", @"sf": @"r.joystick.press.down", @"unmappedSf": @"r.joystick.press.down", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @14},
            @{@"kind": @"button", @"aliases": @[@"Left Bumper"], @"local": @"L4 Button", @"unmappedLocal": @"L4 Button", @"sf": @"l4.button.horizontal", @"unmappedSf": @"l4.button.horizontal", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @15},
            @{@"kind": @"button", @"aliases": @[@"Right Bumper"], @"local": @"R4 Button", @"unmappedLocal": @"R4 Button", @"sf": @"r4.button.horizontal", @"unmappedSf": @"r4.button.horizontal", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @16},
            @{@"kind": @"button", @"aliases": @[@"Back Left Button 0", @"Paddle 3"], @"local": @"M2 Button", @"unmappedLocal": @"M2 Button", @"sf": @"m2.button.horizontal", @"unmappedSf": @"m2.button.horizontal", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @17},
            @{@"kind": @"button", @"aliases": @[@"Back Left Button 1", @"Paddle 4"], @"local": @"M4 Button", @"unmappedLocal": @"M4 Button", @"sf": @"m4.button.horizontal", @"unmappedSf": @"m4.button.horizontal", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @18},
            @{@"kind": @"button", @"aliases": @[@"Back Right Button 0", @"Paddle 1"], @"local": @"M1 Button", @"unmappedLocal": @"M1 Button", @"sf": @"m1.button.horizontal", @"unmappedSf": @"m1.button.horizontal", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @19},
            @{@"kind": @"button", @"aliases": @[@"Back Right Button 1", @"Paddle 2"], @"local": @"M3 Button", @"unmappedLocal": @"M3 Button", @"sf": @"m3.button.horizontal", @"unmappedSf": @"m3.button.horizontal", @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @20},
            @{@"kind": @"button", @"aliases": @[@"Button Options"], @"local": @"Options Button", @"unmappedLocal": @"Options Button", @"sf": @"ellipsis.circle", @"unmappedSf": @"ellipsis.circle", @"analog": @1, @"system": @1, @"collection": [NSNull null], @"order": @21},
            @{@"kind": @"axis", @"aliases": @[@"Direction Pad X Axis"], @"local": @"Direction Pad (Horizontal)", @"unmappedLocal": @"Direction Pad (Horizontal)", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": @"Direction Pad", @"order": @-1},
            @{@"kind": @"axis", @"aliases": @[@"Direction Pad Y Axis"], @"local": @"Direction Pad (Vertical)", @"unmappedLocal": @"Direction Pad (Vertical)", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": @"Direction Pad", @"order": @-1},
            @{@"kind": @"axis", @"aliases": @[@"Left Thumbstick X Axis"], @"local": @"Left Thumbstick (Horizontal)", @"unmappedLocal": @"Left Thumbstick (Horizontal)", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": @"Left Thumbstick", @"order": @-1},
            @{@"kind": @"axis", @"aliases": @[@"Left Thumbstick Y Axis"], @"local": @"Left Thumbstick (Vertical)", @"unmappedLocal": @"Left Thumbstick (Vertical)", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": @"Left Thumbstick", @"order": @-1},
            @{@"kind": @"axis", @"aliases": @[@"Right Thumbstick X Axis"], @"local": @"Right Thumbstick (Horizontal)", @"unmappedLocal": @"Right Thumbstick (Horizontal)", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": @"Right Thumbstick", @"order": @-1},
            @{@"kind": @"axis", @"aliases": @[@"Right Thumbstick Y Axis"], @"local": @"Right Thumbstick (Vertical)", @"unmappedLocal": @"Right Thumbstick (Vertical)", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": @"Right Thumbstick", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Direction Pad Down"], @"local": @"Direction Pad (Down)", @"unmappedLocal": @"Direction Pad (Down)", @"sf": @"dpad.down.fill", @"unmappedSf": @"dpad.down.fill", @"analog": @1, @"system": @0, @"collection": @"Direction Pad", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Direction Pad Left"], @"local": @"Direction Pad (Left)", @"unmappedLocal": @"Direction Pad (Left)", @"sf": @"dpad.left.fill", @"unmappedSf": @"dpad.left.fill", @"analog": @1, @"system": @0, @"collection": @"Direction Pad", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Direction Pad Right"], @"local": @"Direction Pad (Right)", @"unmappedLocal": @"Direction Pad (Right)", @"sf": @"dpad.right.fill", @"unmappedSf": @"dpad.right.fill", @"analog": @1, @"system": @0, @"collection": @"Direction Pad", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Direction Pad Up"], @"local": @"Direction Pad (Up)", @"unmappedLocal": @"Direction Pad (Up)", @"sf": @"dpad.up.fill", @"unmappedSf": @"dpad.up.fill", @"analog": @1, @"system": @0, @"collection": @"Direction Pad", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Left Thumbstick Down"], @"local": @"Left Thumbstick (Down)", @"unmappedLocal": @"Left Thumbstick (Down)", @"sf": @"l.joystick.tilt.down", @"unmappedSf": @"l.joystick.tilt.down", @"analog": @1, @"system": @0, @"collection": @"Left Thumbstick", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Left Thumbstick Left"], @"local": @"Left Thumbstick (Left)", @"unmappedLocal": @"Left Thumbstick (Left)", @"sf": @"l.joystick.tilt.left", @"unmappedSf": @"l.joystick.tilt.left", @"analog": @1, @"system": @0, @"collection": @"Left Thumbstick", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Left Thumbstick Right"], @"local": @"Left Thumbstick (Right)", @"unmappedLocal": @"Left Thumbstick (Right)", @"sf": @"l.joystick.tilt.right", @"unmappedSf": @"l.joystick.tilt.right", @"analog": @1, @"system": @0, @"collection": @"Left Thumbstick", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Left Thumbstick Up"], @"local": @"Left Thumbstick (Up)", @"unmappedLocal": @"Left Thumbstick (Up)", @"sf": @"l.joystick.tilt.up", @"unmappedSf": @"l.joystick.tilt.up", @"analog": @1, @"system": @0, @"collection": @"Left Thumbstick", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Right Thumbstick Down"], @"local": @"Right Thumbstick (Down)", @"unmappedLocal": @"Right Thumbstick (Down)", @"sf": @"r.joystick.tilt.down", @"unmappedSf": @"r.joystick.tilt.down", @"analog": @1, @"system": @0, @"collection": @"Right Thumbstick", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Right Thumbstick Left"], @"local": @"Right Thumbstick (Left)", @"unmappedLocal": @"Right Thumbstick (Left)", @"sf": @"r.joystick.tilt.left", @"unmappedSf": @"r.joystick.tilt.left", @"analog": @1, @"system": @0, @"collection": @"Right Thumbstick", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Right Thumbstick Right"], @"local": @"Right Thumbstick (Right)", @"unmappedLocal": @"Right Thumbstick (Right)", @"sf": @"r.joystick.tilt.right", @"unmappedSf": @"r.joystick.tilt.right", @"analog": @1, @"system": @0, @"collection": @"Right Thumbstick", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Right Thumbstick Up"], @"local": @"Right Thumbstick (Up)", @"unmappedLocal": @"Right Thumbstick (Up)", @"sf": @"r.joystick.tilt.up", @"unmappedSf": @"r.joystick.tilt.up", @"analog": @1, @"system": @0, @"collection": @"Right Thumbstick", @"order": @-1}
        ];
    });
    return specs;
}

+ (NSArray *)microSpecs
{
    static NSArray *specs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        specs = @[
            @{@"kind": @"dpad", @"aliases": @[@"Direction Pad"], @"local": @"Touch Surface", @"unmappedLocal": @"Touch Surface", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @0},
            @{@"kind": @"button", @"aliases": @[@"Button Menu"], @"local": @"Menu Button", @"unmappedLocal": @"Menu Button", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @0, @"system": @0, @"collection": [NSNull null], @"order": @1},
            @{@"kind": @"button", @"aliases": @[@"Button A"], @"local": @"Touch Surface Button", @"unmappedLocal": @"Touch Surface Button", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @0, @"system": @0, @"collection": [NSNull null], @"order": @2},
            @{@"kind": @"button", @"aliases": @[@"Button X"], @"local": @"Play/Pause Button", @"unmappedLocal": @"Play/Pause Button", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @0, @"system": @0, @"collection": [NSNull null], @"order": @3},
            @{@"kind": @"axis", @"aliases": @[@"Direction Pad X Axis"], @"local": @"Touch Surface (Horizontal)", @"unmappedLocal": @"Touch Surface (Horizontal)", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": @"Direction Pad", @"order": @-1},
            @{@"kind": @"axis", @"aliases": @[@"Direction Pad Y Axis"], @"local": @"Touch Surface (Vertical)", @"unmappedLocal": @"Touch Surface (Vertical)", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": @"Direction Pad", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Direction Pad Down"], @"local": @"Touch Surface (Down)", @"unmappedLocal": @"Touch Surface (Down)", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": @"Direction Pad", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Direction Pad Left"], @"local": @"Touch Surface (Left)", @"unmappedLocal": @"Touch Surface (Left)", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": @"Direction Pad", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Direction Pad Right"], @"local": @"Touch Surface (Right)", @"unmappedLocal": @"Touch Surface (Right)", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": @"Direction Pad", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Direction Pad Up"], @"local": @"Touch Surface (Up)", @"unmappedLocal": @"Touch Surface (Up)", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": @"Direction Pad", @"order": @-1}
        ];
    });
    return specs;
}

+ (NSArray *)mouseSpecs
{
    static NSArray *specs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        specs = @[
            @{@"kind": @"button", @"aliases": @[@"Left Button"], @"local": @"Left Button", @"unmappedLocal": @"Left Button", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @0, @"system": @0, @"collection": [NSNull null], @"order": @0},
            @{@"kind": @"button", @"aliases": @[@"Right Button"], @"local": @"Right Button", @"unmappedLocal": @"Right Button", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @0, @"system": @0, @"collection": [NSNull null], @"order": @1},
            @{@"kind": @"button", @"aliases": @[@"Middle Button"], @"local": @"Middle Button", @"unmappedLocal": @"Middle Button", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @0, @"system": @0, @"collection": [NSNull null], @"order": @2},
            @{@"kind": @"cursor", @"aliases": @[@"Scroll"], @"local": @"Scroll", @"unmappedLocal": @"Scroll", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": [NSNull null], @"order": @3},
            @{@"kind": @"axis", @"aliases": @[@"Scroll X Axis"], @"local": @"Scroll (Horizontal)", @"unmappedLocal": @"Scroll (Horizontal)", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": @"Scroll", @"order": @-1},
            @{@"kind": @"axis", @"aliases": @[@"Scroll Y Axis"], @"local": @"Scroll (Vertical)", @"unmappedLocal": @"Scroll (Vertical)", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": @"Scroll", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Scroll Down"], @"local": @"Scroll (Down)", @"unmappedLocal": @"Scroll (Down)", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": @"Scroll", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Scroll Left"], @"local": @"Scroll (Left)", @"unmappedLocal": @"Scroll (Left)", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": @"Scroll", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Scroll Right"], @"local": @"Scroll (Right)", @"unmappedLocal": @"Scroll (Right)", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": @"Scroll", @"order": @-1},
            @{@"kind": @"button", @"aliases": @[@"Scroll Up"], @"local": @"Scroll (Up)", @"unmappedLocal": @"Scroll (Up)", @"sf": [NSNull null], @"unmappedSf": [NSNull null], @"analog": @1, @"system": @0, @"collection": @"Scroll", @"order": @-1}
        ];
    });
    return specs;
}

@end
