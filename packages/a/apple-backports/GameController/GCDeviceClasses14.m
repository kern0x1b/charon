#import <GameController/GameController.h>

#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

@implementation GCXboxGamepad

@dynamic paddleButton1, paddleButton2, paddleButton3, paddleButton4, buttonShare;

@end

@implementation GCDualShockGamepad

@dynamic touchpadButton, touchpadPrimary, touchpadSecondary;

@end

@implementation GCControllerTouchpad

@dynamic button, touchDown, touchMoved, touchUp, touchSurface, touchState, reportsAbsoluteTouchSurfaceValues;

@end

@implementation GCDeviceBattery

@dynamic batteryLevel, batteryState;

@end

@implementation GCDeviceLight

@dynamic color;

@end

@implementation GCDeviceHaptics

@dynamic supportedLocalities;

@end

@implementation GCKeyboardInput

@dynamic keyChangedHandler, anyKeyPressed;

@end

@implementation GCMouseInput

@dynamic mouseMovedHandler, scroll, leftButton, rightButton, middleButton, auxiliaryButtons;

@end

@implementation GCDeviceCursor
@end
