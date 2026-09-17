#import <Foundation/Foundation.h>
#import "CharonDimension.h"

@implementation NSUnitConverterReciprocal {
@private
    double _reciprocalValue;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithReciprocalValue:(double)reciprocal
{
    if ((self = [super init]))
        _reciprocalValue = reciprocal;
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!coder.allowsKeyedCoding) {
        [NSException raise:NSInvalidArgumentException format:@"NSUnitConverterReciprocal cannot be decoded by non-keyed archivers"];
        return nil;
    }
    return [self initWithReciprocalValue:[coder decodeDoubleForKey:@"NS.reciprocalValue"]];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    if (!coder.allowsKeyedCoding) {
        [NSException raise:NSInvalidArgumentException format:@"NSUnitConverterReciprocal encoder does not allow non-keyed coding!"];
        return;
    }
    [coder encodeDouble:_reciprocalValue forKey:@"NS.reciprocalValue"];
}

- (double)reciprocalValue
{
    return _reciprocalValue;
}

- (double)baseUnitValueFromValue:(double)value
{
    return _reciprocalValue / value;
}

- (double)valueFromBaseUnitValue:(double)baseUnitValue
{
    return _reciprocalValue / baseUnitValue;
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

- (BOOL)isEqual:(id)object
{
    if (object == self)
        return YES;
    if (![object isKindOfClass:[NSUnitConverterReciprocal class]])
        return NO;
    return _reciprocalValue == [object reciprocalValue];
}

- (NSString *)description
{
    return [[super description] stringByAppendingString:[NSString stringWithFormat:@" reciprocalValue = %f", _reciprocalValue]];
}

@end
