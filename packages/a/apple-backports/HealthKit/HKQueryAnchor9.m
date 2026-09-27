// HKQueryAnchor: how far a query of this store has been answered.
//
// The class arrived in iOS 9.0, so it is a file of its own: one object carries the API of one
// release (COORDINATION section 5, "one release per object file, or check_registry fails").

#import <HealthKit/HealthKit.h>

#import "CharonHKStore.h"

@implementation HKQueryAnchor {
    NSInteger _sequence;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

+ (instancetype)charon_anchorWithSequence:(NSInteger)sequence
{
    HKQueryAnchor *anchor = [[HKQueryAnchor alloc] init];
    anchor->_sequence = sequence;
    return anchor;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self)
        _sequence = [coder decodeIntForKey:@"sequence"];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInt:_sequence forKey:@"sequence"];
}

- (id)copyWithZone:(NSZone *)zone
{
    return [HKQueryAnchor charon_anchorWithSequence:_sequence];
}

// How far this store's own write sequence has been answered. A position in the store is what the
// release's anchor is as well, and it is what lets an anchored query be asked again and be answered
// with only what came after it.
- (NSInteger)sequence
{
    return _sequence;
}

- (BOOL)isEqual:(id)other
{
    if (self == other)
        return YES;
    if (![other isKindOfClass:[HKQueryAnchor class]])
        return NO;
    return _sequence == ((HKQueryAnchor *)other).sequence;
}

- (NSUInteger)hash
{
    return (NSUInteger)_sequence;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"HKQueryAnchor at %ld", (long)_sequence];
}

@end
