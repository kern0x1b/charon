#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>
#import "check.h"

static NSString *image_of(Class cls)
{
    Dl_info info;
    return dladdr((__bridge const void *)cls, &info) ? @(info.dli_fname).lastPathComponent : @"?";
}

static BOOL close_enough(CGFloat actual, CGFloat expected)
{
    return fabs(actual - expected) <= 1e-5;
}

int main(void)
{
    @autoreleasepool {
        for (NSString *name in @[@"UICubicTimingParameters", @"UISpringTimingParameters", @"_UIViewCubicTimingFunction"])
            CHECK_EQUAL(image_of(NSClassFromString(name)), @"libUIKitBackports.dylib",
                        [name stringByAppendingString:@" comes from the backports library"].UTF8String);

        UICubicTimingParameters *plain = [[UICubicTimingParameters alloc] init];
        CHECK(plain.timingCurveType == UITimingCurveTypeBuiltin, "a plain cubic curve is a builtin one");
        CHECK(plain.cubicTimingParameters == plain, "a cubic curve is its own cubic parameters");
        CHECK(plain.springTimingParameters == nil, "a cubic curve has no spring parameters");

        UICubicTimingParameters *easeInOut =
            [[UICubicTimingParameters alloc] initWithAnimationCurve:UIViewAnimationCurveEaseInOut];
        CHECK(easeInOut.animationCurve == UIViewAnimationCurveEaseInOut, "the animation curve is kept");
        CHECK(close_enough(easeInOut.controlPoint1.x, 0.42) && close_enough(easeInOut.controlPoint1.y, 0),
              "ease in out resolves to its first control point");
        CHECK(close_enough(easeInOut.controlPoint2.x, 0.58) && close_enough(easeInOut.controlPoint2.y, 1),
              "ease in out resolves to its second control point");

        UICubicTimingParameters *linear =
            [[UICubicTimingParameters alloc] initWithAnimationCurve:UIViewAnimationCurveLinear];
        CHECK(close_enough(linear.controlPoint1.x, 0) && close_enough(linear.controlPoint2.x, 1),
              "the linear curve runs corner to corner");

        UICubicTimingParameters *points =
            [[UICubicTimingParameters alloc] initWithControlPoint1:CGPointMake(0.1, 0.2)
                                                    controlPoint2:CGPointMake(0.8, 0.9)];
        CHECK(points.timingCurveType == UITimingCurveTypeCubic, "control points make a cubic curve");
        CHECK(close_enough(points.controlPoint1.y, 0.2) && close_enough(points.controlPoint2.x, 0.8),
              "the control points are kept");
        UICubicTimingParameters *pointsBack =
            [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:points]];
        CHECK(close_enough(pointsBack.controlPoint1.x, 0.1) && close_enough(pointsBack.controlPoint2.y, 0.9),
              "the control points survive an archive");
        CHECK(pointsBack.timingCurveType == UITimingCurveTypeCubic, "the curve keeps its type through an archive");

        @try {
            UICubicTimingParameters *broken = [[UICubicTimingParameters alloc] initWithAnimationCurve:(UIViewAnimationCurve)99];
            (void)broken;
            CHECK(NO, "an unknown animation curve raises");
        } @catch (NSException *exception) {
            CHECK([exception.reason hasPrefix:@"Unknown/Unsupported UIViewAnimationCurve type"],
                  "an unknown animation curve raises");
        }

        UISpringTimingParameters *spring = [[UISpringTimingParameters alloc] init];
        CHECK(spring.timingCurveType == UITimingCurveTypeSpring, "a spring is a spring curve");
        CHECK(spring.springTimingParameters == spring, "a spring is its own spring parameters");
        CHECK(spring.cubicTimingParameters == nil, "a spring has no cubic parameters");
        CHECK([spring.description rangeOfString:@"mass=3.000"].location != NSNotFound,
              "the default spring has a mass of three");
        CHECK([spring.description rangeOfString:@"stiffness=1000.000"].location != NSNotFound,
              "the default spring has a stiffness of a thousand");
        CHECK([spring.description rangeOfString:@"damping=500.000"].location != NSNotFound,
              "the default spring has a damping of five hundred");

        UISpringTimingParameters *ratio =
            [[UISpringTimingParameters alloc] initWithDampingRatio:0.5 initialVelocity:CGVectorMake(1, -2)];
        CHECK(ratio.initialVelocity.dx == 1 && ratio.initialVelocity.dy == -2, "the initial velocity is kept");
        CHECK([ratio.description rangeOfString:@"dampingRatio=0.500"].location != NSNotFound,
              "a spring made from a ratio describes itself by that ratio");
        UISpringTimingParameters *ratioBack =
            [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:ratio]];
        CHECK([ratioBack.description isEqual:ratio.description], "a spring survives an archive");
        CHECK([[ratio copy] description] != nil && [[[ratio copy] description] isEqual:ratio.description],
              "a spring survives a copy");

        printf("%d checks, %d failures\n", charon_checks, charon_failures);
        return charon_failures;
    }
}
