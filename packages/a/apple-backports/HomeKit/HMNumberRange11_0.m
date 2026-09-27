// HMNumberRange, of iOS 11.0: the range a threshold event fires on, which is a value object with no
// identifier of its own. -init is NS_UNAVAILABLE in the release's own header, so the port makes the
// range the way the release makes it, through +numberRangeWithMinValue:maxValue:.
//
// One release's API per object file, which is what the band machinery needs.
#import "CharonHomeKitInternal.h"

@implementation HMNumberRange
@synthesize charon_minValue = _charon_minValue, charon_maxValue = _charon_maxValue;

+ (instancetype)numberRangeWithMinValue:(NSNumber *)minValue maxValue:(NSNumber *)maxValue
{
    HMNumberRange *range = [super new];
    range.charon_minValue = minValue;
    range.charon_maxValue = maxValue;
    return range;
}

- (NSNumber *)minValue
{
    return [self.charon_minValue copy];
}

- (NSNumber *)maxValue
{
    return [self.charon_maxValue copy];
}

@end

HMNumberRange *CharonHomeKitNumberRange(NSNumber *minimum, NSNumber *maximum)
{
    return [HMNumberRange numberRangeWithMinValue:minimum maxValue:maximum];
}
