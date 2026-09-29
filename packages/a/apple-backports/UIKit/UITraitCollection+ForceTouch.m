#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static char charon_force_touch_key;

@implementation UITraitCollection (CharonForceTouch)

+ (UITraitCollection *)traitCollectionWithForceTouchCapability:(UIForceTouchCapability)capability
{
    UITraitCollection *collection = [[self alloc] init];
    objc_setAssociatedObject(collection, &charon_force_touch_key, @(capability), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return collection;
}

- (UIForceTouchCapability)forceTouchCapability
{
    NSNumber *capability = objc_getAssociatedObject(self, &charon_force_touch_key);
    return capability ? (UIForceTouchCapability)capability.integerValue : UIForceTouchCapabilityUnavailable;
}

void charon_set_trait_force_touch(UITraitCollection *collection, UIForceTouchCapability capability)
{
    // The one place this trait's storage is written besides the constructor above, so a collection made by the
    // traits of iOS 17 carries the capability the same way and the two compare equal.
    objc_setAssociatedObject(collection, &charon_force_touch_key, capability ? @(capability) : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
