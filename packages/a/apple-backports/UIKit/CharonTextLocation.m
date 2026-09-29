#import "CharonTextLocation.h"

@implementation CharonTextLocation

@synthesize offset = _offset;

- (instancetype)initWithOffset:(NSInteger)offset
{
    if ((self = [super init]))
        _offset = offset;
    return self;
}

- (NSComparisonResult)compare:(id<NSTextLocation>)location
{
    NSInteger other = [location respondsToSelector:@selector(offset)] ? [(CharonTextLocation *)location offset] : 0;
    if (_offset == other)
        return NSOrderedSame;
    return _offset < other ? NSOrderedAscending : NSOrderedDescending;
}

- (BOOL)isEqual:(id)object
{
    if (object == self)
        return YES;
    if (![object isKindOfClass:[CharonTextLocation class]])
        return NO;
    return [(CharonTextLocation *)object offset] == _offset;
}

- (NSUInteger)hash
{
    return (NSUInteger)(_offset ^ (_offset >> 16));
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p; offset = %ld>", [self class], self, (long)_offset];
}

@end
