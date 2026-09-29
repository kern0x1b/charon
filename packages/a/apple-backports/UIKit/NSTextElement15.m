// NSTextElement and NSTextParagraph: the smallest unit of a document's contents, and the paragraph that is the
// one the rest of the range layer is written against. What the headers declare is in NSTextElement.h of SDK
// 26.2; what the host's own UIKit answers is in facts/UIKit/NSTextRange15.md.
//
// An element is a range in a document plus the manager that owns it and, for a subclass, whatever the subclass
// means by the contents of that range. A paragraph's contents are an attributed string, and its two derived
// ranges come out of that string: the content is everything but the trailing newline that ends the paragraph, and
// the separator is that newline, so that the two together are the paragraph's whole range in the document. A
// string with no trailing newline has a content range and an empty separator, which is the case the derived
// ranges have to get right: the content is then the whole string.

#import <UIKit/UIKit.h>
#import "CharonTextLocation.h"

@implementation NSTextElement

@synthesize textContentManager = _textContentManager;
@synthesize elementRange = _elementRange;

- (instancetype)initWithTextContentManager:(NSTextContentManager *)textContentManager
{
    if ((self = [super init]))
        _textContentManager = textContentManager;
    return self;
}

- (NSArray<__kindof NSTextElement *> *)childElements
{
    return @[];
}

- (NSTextElement *)parentElement
{
    return nil;
}

- (BOOL)isRepresentedElement
{
    // Every element is one the document enumerates, the base class included: the host answers YES for a plain
    // NSTextElement and there is nothing abstract about a property the answer cannot vary (M4).
    return YES;
}

// The host's own text, which is the class and the address and nothing else.
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p>", [self class], self];
}

@end

@implementation NSTextParagraph

@synthesize attributedString = _attributedString;

// A paragraph's two derived ranges are in the document its element range names, so the range is read through
// the property the header declares rather than through the superclass's storage, which is private to the file
// the superclass is in.
- (NSTextRange *)charon_element_range
{
    return self.elementRange;
}

- (instancetype)initWithAttributedString:(NSAttributedString *)attributedString
{
    if ((self = [super initWithTextContentManager:nil]))
        _attributedString = attributedString;
    return self;
}

- (NSTextRange *)paragraphContentRange
{
    // The header's own derivation, and what decides it: the ranges come out of the element's range *and* the
    // attributed string, so a paragraph that has no range in a document has no content range either, whatever
    // its string is. The host answers nil for every string until -elementRange is set (M4).
    if (![self charon_element_range] || !_attributedString.length)
        return nil;
    // The paragraph separator is the last character when it is a line feed or a carriage return, and a paragraph
    // whose contents do not end in one has no separator: the content range is then the whole string.
    NSUInteger length = _attributedString.length;
    unichar last = [[_attributedString string] characterAtIndex:length - 1];
    BOOL endsWithSeparator = last == 10 || last == 13;
    NSUInteger content = endsWithSeparator ? length - 1 : length;
    // The two ranges are in the document, so they start where the element's range does and are as long as the
    // string is: the content is the string without its trailing newline, the separator is that newline.
    id<NSTextLocation> elementStart = [self charon_element_range].location;
    NSInteger base = [elementStart respondsToSelector:@selector(offset)] ? [(CharonTextLocation *)elementStart offset] : 0;
    return [[NSTextRange alloc] initWithLocation:[[CharonTextLocation alloc] initWithOffset:base]
                                     endLocation:[[CharonTextLocation alloc] initWithOffset:base + (NSInteger)content]];
}

- (NSTextRange *)paragraphSeparatorRange
{
    if (![self charon_element_range] || !_attributedString.length)
        return nil;
    NSUInteger length = _attributedString.length;
    unichar last = [[_attributedString string] characterAtIndex:length - 1];
    if (last != 10 && last != 13)
        return nil;
    // A separator range covers the last character, and a trailing carriage return before a line feed is both of
    // them: the paragraph's own string ends with the pair, and the separator is the pair.
    NSUInteger start = length - 1;
    if (last == 10 && start > 0 && [[_attributedString string] characterAtIndex:start - 1] == 13)
        start--;
    id<NSTextLocation> elementStart = [self charon_element_range].location;
    NSInteger base = [elementStart respondsToSelector:@selector(offset)] ? [(CharonTextLocation *)elementStart offset] : 0;
    return [[NSTextRange alloc] initWithLocation:[[CharonTextLocation alloc] initWithOffset:base + (NSInteger)start]
                                     endLocation:[[CharonTextLocation alloc] initWithOffset:base + (NSInteger)length]];
}

- (BOOL)isRepresentedElement
{
    return YES;
}

// The host's own text, which adds the string a paragraph holds and an element's description does not.
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p>", [self class], self];
}

@end
