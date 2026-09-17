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

@end
