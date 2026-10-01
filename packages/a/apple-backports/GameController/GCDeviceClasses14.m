#import <GameController/GameController.h>

#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

@implementation GCXboxGamepad

@dynamic paddleButton1, paddleButton2, paddleButton3, paddleButton4, buttonShare;

@end

@implementation GCDualShockGamepad

@dynamic touchpadButton, touchpadPrimary, touchpadSecondary;

@end

@implementation GCDeviceCursor
@end
