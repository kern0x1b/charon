#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>
#import "check.h"

int main(void)
{
    @autoreleasepool {
        Dl_info info;
        CHECK(dladdr(&kCACornerCurveContinuous, &info) && !strcmp(strrchr(info.dli_fname, '/') + 1, "libUIKitBackports.dylib"), "the corner curve constants come from the backports library");
        CHECK_EQUAL(kCACornerCurveCircular, @"circular", "the circular constant");
        CHECK_EQUAL(kCACornerCurveContinuous, @"continuous", "the continuous constant");
        CALayer *layer = [CALayer layer];
        CHECK_EQUAL(layer.cornerCurve, kCACornerCurveCircular, "a layer starts circular");
        layer.cornerCurve = kCACornerCurveContinuous;
        CHECK_EQUAL(layer.cornerCurve, kCACornerCurveContinuous, "and keeps continuous");
        CHECK_EQUAL([layer valueForKey:@"cornerCurve"], kCACornerCurveContinuous, "also through key-value coding");
        layer.cornerCurve = @"bogus";
        CHECK_EQUAL(layer.cornerCurve, kCACornerCurveCircular, "a value that is no curve makes it circular");
        layer.cornerCurve = kCACornerCurveContinuous;
        layer.cornerCurve = nil;
        CHECK_EQUAL(layer.cornerCurve, kCACornerCurveCircular, "and so does nil");
    }
    printf("checks=%d failures=%d\n", charon_checks, charon_failures);
    return charon_failures;
}
