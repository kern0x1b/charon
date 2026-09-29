// The range layer of TextKit 2: a range between two locations, a selection over ranges, an element of the
// document, a paragraph, and the navigation that answers what a selection moved does. Five classes, and what each
// of them is came from the 26.2 headers of NSTextRange.h, NSTextSelection.h, NSTextSelectionNavigation.h and
// NSTextElement.h; what the host's own UIKit answers is in facts/UIKit/NSTextRange15.md.
//
// An NSTextLocation is a protocol with one method, a comparison, and a range is two of them. Every question a
// range is asked - does it contain this location, does it contain that range, do they intersect, what is the
// intersection, what is the union - is a comparison of the two locations the ranges are made of, so that is all
// this file has to know about a location, and it is why a range works over any document type at all: the
// content manager's own location, the paragraph's, a test's. CharonTextLocation is the port's own concrete
// location over an offset, which is what the tests and a content manager without a private location use.

#import <UIKit/UIKit.h>
#import "CharonTextLocation.h"

#pragma clang diagnostic ignored "-Wobjc-protocol-qualifiers"

@implementation NSTextRange

@synthesize location = _location;
@synthesize endLocation = _endLocation;

- (instancetype)initWithLocation:(id<NSTextLocation>)location endLocation:(id<NSTextLocation>)endLocation
{
    // A range whose end is nil is empty at its start, which is what the header for the two-argument initializer
    // says, and which is the one thing an end location of nil has to mean: a range with no end has no contents.
    if ((self = [super init]))
        _location = location;
    // A range with no end of its own has the start as its end, which is what the host answers and what makes
    // the end of a range exclusive in the only way that works: nothing is in a range whose end is its start.
    _endLocation = endLocation ? endLocation : location;
    return self;
}

- (instancetype)initWithLocation:(id<NSTextLocation>)location
{
    return [self initWithLocation:location endLocation:nil];
}

- (BOOL)isEmpty
{
    return _endLocation == _location;
}

- (BOOL)isEqualToTextRange:(NSTextRange *)textRange
{
    if (!textRange)
        return NO;
    return [_location isEqual:textRange.location] && [_endLocation isEqual:textRange.endLocation];
}

- (BOOL)containsLocation:(id<NSTextLocation>)location
{
    if (!location)
        return NO;
    // The header's own rule, which is what makes a range's end exclusive: (location <= l) && (l < endLocation).
    // An empty range has its end at its start, so nothing is in it, itself included.
    if ([location compare:_location] == NSOrderedAscending)
        return NO;
    return [location compare:_endLocation] == NSOrderedAscending;
}

- (BOOL)containsRange:(NSTextRange *)textRange
{
    if (!textRange)
        return NO;
    if (![self containsLocation:textRange.location])
        return NO;
    return [self containsLocation:textRange.endLocation];
}

- (BOOL)intersectsWithTextRange:(NSTextRange *)textRange
{
    if (!textRange)
        return NO;
    // Two empty ranges share no contents, so they do not intersect, and an empty range is in none.
    if ([self isEmpty] || [textRange isEmpty])
        return NO;
    if ([textRange.location compare:_location] == NSOrderedAscending)
        return [textRange.location compare:_endLocation] == NSOrderedAscending;
    return [_location compare:textRange.endLocation] == NSOrderedAscending;
}

- (instancetype)textRangeByIntersectingWithTextRange:(NSTextRange *)textRange
{
    if (![self intersectsWithTextRange:textRange])
        return nil;
    id<NSTextLocation> start = [textRange.location compare:_location] == NSOrderedAscending ? textRange.location : _location;
    id<NSTextLocation> end = [_endLocation compare:textRange.endLocation] == NSOrderedAscending ? _endLocation : textRange.endLocation;
    return [[[self class] alloc] initWithLocation:start endLocation:end];
}

- (instancetype)textRangeByFormingUnionWithTextRange:(NSTextRange *)textRange
{
    if (!textRange)
        return self;
    if ([self isEmpty] && [textRange isEmpty])
        return self;
    id<NSTextLocation> start = [textRange.location compare:_location] == NSOrderedAscending ? _location : textRange.location;
    id<NSTextLocation> end = [_endLocation compare:textRange.endLocation] == NSOrderedAscending ? textRange.endLocation : _endLocation;
    return [[[self class] alloc] initWithLocation:start endLocation:end];
}

// The host's own text for a range, which is its two locations and nothing else: "0...10", and "3...3" for a
// range that is empty at 3. There is no class and no address, so a range printed in a log names the part of the
// document it is in and nothing else.
- (NSString *)description
{
    return [NSString stringWithFormat:@"%@...%@", _location, _endLocation];
}

- (BOOL)isEqual:(id)object
{
    if (object == self)
        return YES;
    if (![object isKindOfClass:[NSTextRange class]])
        return NO;
    return [self isEqualToTextRange:object];
}

- (NSUInteger)hash
{
    // The two locations' own hashes, combined. The host's own hash is not a function of the range's value - two
    // equal ranges measured with different hashes, M2 - and a hash that disagrees with equality breaks every
    // dictionary and set the range goes into, so this one is by value and the divergence is recorded rather than
    // copied.
    return _location.hash ^ _endLocation.hash * 31;
}

@end
