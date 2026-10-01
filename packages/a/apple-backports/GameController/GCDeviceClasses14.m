#import <GameController/GameController.h>

#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

// An Xbox controller's profile is the extended gamepad with four paddle buttons the header declares
// nullable: the standard Bluetooth Xbox controller the profile describes has none, and the host's own
// GCXboxGamepad answers nil for all four (measured). They are therefore nil here too, and
// buttonShare - the Series X controller's share button, iOS 15 - is left out of this iOS 14 object
// entirely rather than answered here.
@implementation GCXboxGamepad
@end

@implementation GCDeviceCursor
@end
