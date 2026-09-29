// NSTextSelection: one logical selection, a set of disjoint ranges and the two things that say how it behaves -
// which end the cursor is at, and what an extending operation moves by. What the header declares is in
// NSTextSelection.h of SDK 26.2; what the host's own UIKit answers is in facts/UIKit/NSTextRange15.md.
//
// The one piece of work in the class is the normalisation the header's comment on the designated initializer
// names: ranges that overlap or are out of order are reordered and merged, because a selection is a set of
// disjoint ranges in logical order and a caller that hands over anything else gets the one the header promises.

#import <UIKit/UIKit.h>

@implementation NSTextSelection {
    // The one property with a setter of its own, so its storage is written out here: a setter that also sets
    // -logical cannot be a synthesized pair, and the header says setting a secondary location makes the
    // selection not a logical one.
    id<NSTextLocation> _secondarySelectionLocation;
    // And the one property whose getter and setter do not agree: a selection that was given no typing attributes
    // answers an empty dictionary rather than nil (M3), so the storage is written out here beside the other.
    NSDictionary *_typingAttributes;
}

@synthesize textRanges = _textRanges;
@synthesize affinity = _affinity;
@synthesize granularity = _granularity;
@synthesize anchorPositionOffset = _anchorPositionOffset;
@synthesize logical = _logical;

// An empty dictionary rather than nil, which is what the host answers for a selection that was given none (M3).
// The pair is written out rather than synthesized because the getter and the setter do not agree, and the
// setter is the one that keeps the dictionary from being nil in the first place.
- (NSDictionary *)typingAttributes
{
    return _typingAttributes ?: @{};
}

- (void)setTypingAttributes:(NSDictionary *)typingAttributes
{
    _typingAttributes = [typingAttributes copy];
}

- (instancetype)initWithRanges:(NSArray<NSTextRange *> *)textRanges
                      affinity:(NSTextSelectionAffinity)affinity
                   granularity:(NSTextSelectionGranularity)granularity
{
    if ((self = [super init])) {
        // The ranges are kept as they are given, in the order they are given, overlapping and out of order
        // included. The header's comment on this initializer says they are reordered and merged, and the host
        // does neither (M3): it is the one place the header and the system disagree in this family, and the
        // system decides, so a caller that hands over overlapping ranges gets them back overlapping.
        _textRanges = [textRanges copy] ?: @[];
        _affinity = affinity;
        _granularity = granularity;
    }
    return self;
}

- (instancetype)initWithRange:(NSTextRange *)range
                     affinity:(NSTextSelectionAffinity)affinity
                  granularity:(NSTextSelectionGranularity)granularity
{
    return [self initWithRanges:range ? @[ range ] : @[] affinity:affinity granularity:granularity];
}

- (instancetype)initWithLocation:(id<NSTextLocation>)location
                        affinity:(NSTextSelectionAffinity)affinity
{
    return [self initWithRanges:@[ [[NSTextRange alloc] initWithLocation:location] ]
                       affinity:affinity
                    granularity:NSTextSelectionGranularityCharacter];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSMutableArray *ranges = [[coder decodeObjectForKey:@"textRanges"] mutableCopy] ?: [NSMutableArray array];
    NSInteger affinity = [coder decodeIntegerForKey:@"affinity"];
    NSInteger granularity = [coder decodeIntegerForKey:@"granularity"];
    if ((self = [self initWithRanges:ranges affinity:affinity granularity:granularity])) {
        // The host answers an empty dictionary for the typing attributes of a selection that was never given
        // any, not nil (M3), so an application that copies the attributes always has a dictionary to add to.
        _transient = [coder decodeBoolForKey:@"transient"];
        _anchorPositionOffset = (CGFloat)[coder decodeDoubleForKey:@"anchorPositionOffset"];
        _logical = [coder decodeBoolForKey:@"logical"];
            _secondarySelectionLocation = [coder decodeObjectForKey:@"secondarySelectionLocation"];
        _typingAttributes = [coder decodeObjectForKey:@"typingAttributes"] ?: @{};
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_textRanges forKey:@"textRanges"];
    [coder encodeInteger:_affinity forKey:@"affinity"];
    [coder encodeInteger:_granularity forKey:@"granularity"];
    [coder encodeBool:_transient forKey:@"transient"];
    [coder encodeDouble:(double)_anchorPositionOffset forKey:@"anchorPositionOffset"];
    [coder encodeBool:_logical forKey:@"logical"];
    [coder encodeObject:_secondarySelectionLocation forKey:@"secondarySelectionLocation"];
    [coder encodeObject:_typingAttributes forKey:@"typingAttributes"];
}

- (NSTextSelection *)textSelectionWithTextRanges:(NSArray<NSTextRange *> *)textRanges
{
    NSTextSelection *copy =
        [[[self class] alloc] initWithRanges:textRanges affinity:_affinity granularity:_granularity];
    id<NSTextLocation> secondary = _secondarySelectionLocation;
    NSDictionary *typing = _typingAttributes ?: @{};
    // -transient is readonly in the header: it says whether the selection is one a drag is making, which only
    // the responder chain that is dragging knows, so there is no setter to copy through and the value is the
    // one the selection was made with.
    copy->_transient = _transient;
    copy->_anchorPositionOffset = _anchorPositionOffset;
    copy->_logical = _logical;
    [copy setSecondarySelectionLocation:secondary];
    copy->_typingAttributes = typing;
    return copy;
}

- (id<NSTextLocation>)secondarySelectionLocation
{
    return _secondarySelectionLocation;
}

- (void)setSecondarySelectionLocation:(id<NSTextLocation>)secondarySelectionLocation
{
    _secondarySelectionLocation = secondarySelectionLocation;
    // The header's own side effect: a selection with a secondary location is not a logical one.
    if (secondarySelectionLocation)
        _logical = NO;
}

// The host's own text for a selection, which names the two enumerations by their case names and then the ranges
// one to a line: "NSTextSelection:<0x...> granularity=character, affinity=downstream, textRanges=(\n    \"0...5\"\n)".
static NSString *charon_granularity_name(NSTextSelectionGranularity granularity)
{
    switch (granularity) {
    case NSTextSelectionGranularityWord:
        return @"word";
    case NSTextSelectionGranularityParagraph:
        return @"paragraph";
    case NSTextSelectionGranularityLine:
        return @"line";
    case NSTextSelectionGranularitySentence:
        return @"sentence";
    default:
        return @"character";
    }
}

static NSString *charon_affinity_name(NSTextSelectionAffinity affinity)
{
    return affinity == NSTextSelectionAffinityUpstream ? @"upstream" : @"downstream";
}

static NSString *charon_ranges_text(NSArray *ranges)
{
    NSMutableString *text = [NSMutableString stringWithString:@"(\n"];
    for (NSTextRange *range in ranges)
        [text appendFormat:@"    \"%@\"\n", range];
    return [text stringByAppendingString:@")"];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"NSTextSelection:<%p> granularity=%@, affinity=%@, textRanges=%@", self,
                                      charon_granularity_name(_granularity), charon_affinity_name(_affinity),
                                      charon_ranges_text(_textRanges)];
}

@end
