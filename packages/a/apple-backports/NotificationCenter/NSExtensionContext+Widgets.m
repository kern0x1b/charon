#import <UIKit/UIKit.h>
#import <NotificationCenter/NotificationCenter.h>
#import "../CharonSayOnce.h"
#import <objc/runtime.h>

// The two display modes are the two heights a Today widget can be shown at, and the size a widget
// gets is the Notification Center's own geometry, which arrived with iOS 8. iOS 6 has no Notification
// Center, so there is no such geometry to report and none of these three answers a number the port
// would have to invent. What the application states is real though: the mode it declares available is
// kept and read back, and the active mode answers that same declared mode, because on a release that
// never shows a widget there is no other mode to be in.

@implementation NSExtensionContext (NCWidgetAdditions)

@dynamic widgetLargestAvailableDisplayMode;

- (NCWidgetDisplayMode)widgetLargestAvailableDisplayMode
{
    NSNumber *declared = objc_getAssociatedObject(self, @selector(widgetLargestAvailableDisplayMode));
    return declared ? (NCWidgetDisplayMode)declared.integerValue : NCWidgetDisplayModeCompact;
}

- (void)setWidgetLargestAvailableDisplayMode:(NCWidgetDisplayMode)widgetLargestAvailableDisplayMode
{
    objc_setAssociatedObject(self, @selector(widgetLargestAvailableDisplayMode),
                             @(widgetLargestAvailableDisplayMode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NCWidgetDisplayMode)widgetActiveDisplayMode
{
    charon_say_once_for(@"NSExtensionContext.widgetActiveDisplayMode",
                        @"CharonNotificationCenter: no widget is ever shown on this release, so there is no active display "
                        @"mode; the call answers the mode the extension declared available, Compact until it declares "
                        @"another.");
    return self.widgetLargestAvailableDisplayMode;
}

- (CGSize)widgetMaximumSizeForDisplayMode:(NCWidgetDisplayMode)displayMode
{
    charon_say_once_for(@"NSExtensionContext.widgetMaximumSizeForDisplayMode:",
                        @"CharonNotificationCenter: this release's Notification Center has no geometry, so no display mode "
                        @"has a maximum size and the call answers CGSizeZero rather than a number of the port's own.");
    // CGSizeMake and not CGSizeZero: the constant is an exported symbol in a modern CoreGraphics and
    // the release's own cache does not resolve it, which the gate found for CGRectZero in this
    // delivery's first run. The value is the same one CGSizeZero names.
    return CGSizeMake(0.0f, 0.0f);
}

@end
