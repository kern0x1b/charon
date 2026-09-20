#import <QuartzCore/QuartzCore.h>
#import "check.h"

extern NSString *const CharonHostkCACornerCurveCircular, *const CharonHostkCACornerCurveContinuous;

@interface CALayer (CharonHostCornerCurve)
- (NSString *)charonHostCornerCurve;
- (void)setCharonHostCornerCurve:(NSString *)cornerCurve;
@end

int main(void)
{
    @autoreleasepool {
        CHECK_EQUAL(CharonHostkCACornerCurveCircular, kCACornerCurveCircular, "the circular constant");
        CHECK_EQUAL(CharonHostkCACornerCurveContinuous, kCACornerCurveContinuous, "the continuous constant");
        for (id value in @[kCACornerCurveContinuous, kCACornerCurveCircular, @"bogus", [NSNull null], @"", @"Continuous"]) {
            CALayer *ours = [CALayer layer], *theirs = [CALayer layer];
            CHECK_EQUAL([ours charonHostCornerCurve], theirs.cornerCurve, "a fresh layer starts as the system's");
            id given = [value isKindOfClass:[NSNull class]] ? nil : value;
            [ours setCharonHostCornerCurve:given];
            theirs.cornerCurve = given;
            NSString *first = [NSString stringWithFormat:@"a layer set to %@", value];
            CHECK_EQUAL([ours charonHostCornerCurve], theirs.cornerCurve, first.UTF8String);
            [ours setCharonHostCornerCurve:kCACornerCurveContinuous];
            theirs.cornerCurve = kCACornerCurveContinuous;
            [ours setCharonHostCornerCurve:given];
            theirs.cornerCurve = given;
            NSString *second = [NSString stringWithFormat:@"a continuous layer then set to %@", value];
            CHECK_EQUAL([ours charonHostCornerCurve], theirs.cornerCurve, second.UTF8String);
        }
    }
    printf("checks=%d failures=%d\n", charon_checks, charon_failures);
    return charon_failures;
}
