#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

CALayerCornerCurve const kCACornerCurveCircular = @"circular";
CALayerCornerCurve const kCACornerCurveContinuous = @"continuous";

static const char CharonCornerCurveKey;

static void charon_say_once(NSString *key, NSString *text)
{
    static NSMutableSet *said;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        said = [[NSMutableSet alloc] init];
    });
    @synchronized (said) {
        if ([said containsObject:key])
            return;
        [said addObject:key];
    }
    NSLog(@"%@", text);
}

@implementation CALayer (CharonCornerCurve)

- (CALayerCornerCurve)cornerCurve
{
    return objc_getAssociatedObject(self, &CharonCornerCurveKey) ?: kCACornerCurveCircular;
}

- (void)setCornerCurve:(CALayerCornerCurve)cornerCurve
{
    BOOL continuous = [cornerCurve isEqual:kCACornerCurveContinuous];
    objc_setAssociatedObject(self, &CharonCornerCurveKey, continuous ? kCACornerCurveContinuous : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (continuous)
        charon_say_once(@"cornerCurve", [NSString stringWithFormat:@"CALayer cornerCurve: iOS %@ rounds a corner with a circular arc only, so a continuous corner is kept and drawn circular", [UIDevice currentDevice].systemVersion]);
}

@end
