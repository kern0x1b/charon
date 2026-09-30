// UIKit27_0.m - the 27.0 band's one member.
//
// ONE OBJECT, ONE RELEASE: 27.0, on its own, and it is the newest name in the queue.  The SDK 26.2
// surface does not declare it either, which is consistent: a 26.2 surface cannot contain a 27.0 name.

#import "CharonUIKit26.h"
#import <objc/runtime.h>

// UIBarAppearance.overrideUserInterfaceStyle: storage, on a class the release DOES have - UIBarAppearance
// has been a class since iOS 13.  So unlike the twenty-one classes in UIKit26_0.m, this name needs no
// declaration: only the member is new.  The row is OWED, for the same reason as the 26.4 one and stated
// once: the 26.2 surface does not declare it, so nothing here measures the declaration, and the row says
// so rather than the port carrying a signature nobody read.
@implementation UIBarAppearance (CharonUIKit27_0)

static char CharonBarAppearanceOverrideUserInterfaceStyleKey;

- (UIUserInterfaceStyle)overrideUserInterfaceStyle
{
    return (UIUserInterfaceStyle)
        [(NSNumber *)objc_getAssociatedObject(self, &CharonBarAppearanceOverrideUserInterfaceStyleKey)
            integerValue];
}
- (void)setOverrideUserInterfaceStyle:(UIUserInterfaceStyle)style
{
    objc_setAssociatedObject(self, &CharonBarAppearanceOverrideUserInterfaceStyleKey,
                             [NSNumber numberWithInteger:style], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end
