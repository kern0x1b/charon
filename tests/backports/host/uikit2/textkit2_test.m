// The range layer of TextKit 2 beside the host's own UIKit, in one process: the backport's classes are renamed by
// uikit2/run.sh, so each case asks the port and the system the same question and holds the answers to each other.
// What is compared is what facts/UIKit/NSTextRange15.md records.
#import <UIKit/UIKit.h>
#import "check.h"

#define NAMED(...) ([NSString stringWithFormat:__VA_ARGS__].UTF8String)

// A location over an offset, which is all NSTextLocation asks for, once for each side. The two classes are the
// same class under two names, because the harness renames the port's classes and not the test's own.
@interface RangeLayerLocation : NSObject <NSTextLocation>
@property (nonatomic, readonly) NSInteger rangeOffset;
- (instancetype)initWithRangeOffset:(NSInteger)offset;
@end

@implementation RangeLayerLocation

@synthesize rangeOffset = _rangeOffset;

- (instancetype)initWithRangeOffset:(NSInteger)offset
{
    if ((self = [super init]))
        _rangeOffset = offset;
    return self;
}

- (NSComparisonResult)compare:(id<NSTextLocation>)location
{
    NSInteger other = [location respondsToSelector:@selector(rangeOffset)] ? [(RangeLayerLocation *)location rangeOffset] : 0;
    return _rangeOffset == other ? NSOrderedSame : (_rangeOffset < other ? NSOrderedAscending : NSOrderedDescending);
}

- (BOOL)isEqual:(id)object
{
    return object == self || ([object isKindOfClass:[RangeLayerLocation class]] && [object rangeOffset] == _rangeOffset);
}

- (NSUInteger)hash { return (NSUInteger)_rangeOffset; }
- (NSString *)description { return [NSString stringWithFormat:@"%ld", (long)_rangeOffset]; }

@end

static id<NSTextLocation> at(NSInteger offset)
{
    return [[RangeLayerLocation alloc] initWithRangeOffset:offset];
}

// The port's classes, as run.sh renames them, and the range of one side built out of that side's own classes.
// The port's classes as run.sh renames them, with the members the cases ask of them: the harness renames a
// class but not a declaration in this file, so the two sides are two types and a case that forgets which is
// which would not compile.
@interface CharonHostNSTextRange : NSObject
- (instancetype)initWithLocation:(id<NSTextLocation>)location;
- (instancetype)initWithLocation:(id<NSTextLocation>)location endLocation:(id<NSTextLocation>)endLocation;
@property (readonly, getter=isEmpty) BOOL empty;
@property (strong, readonly) id<NSTextLocation> location;
@property (strong, readonly) id<NSTextLocation> endLocation;
- (BOOL)isEqualToTextRange:(NSTextRange *)textRange;
- (BOOL)containsLocation:(id<NSTextLocation>)location;
- (BOOL)containsRange:(NSTextRange *)textRange;
- (BOOL)intersectsWithTextRange:(NSTextRange *)textRange;
- (instancetype)textRangeByIntersectingWithTextRange:(NSTextRange *)textRange;
- (instancetype)textRangeByFormingUnionWithTextRange:(NSTextRange *)textRange;
@end

@interface CharonHostNSTextSelection : NSObject
- (instancetype)initWithRange:(NSTextRange *)range
                     affinity:(NSTextSelectionAffinity)affinity
                  granularity:(NSTextSelectionGranularity)granularity;
- (instancetype)initWithRanges:(NSArray *)textRanges
                      affinity:(NSTextSelectionAffinity)affinity
                   granularity:(NSTextSelectionGranularity)granularity;
- (instancetype)initWithLocation:(id<NSTextLocation>)location affinity:(NSTextSelectionAffinity)affinity;
@property (copy, readonly) NSArray *textRanges;
@property (readonly) NSTextSelectionGranularity granularity;
@property (readonly) NSTextSelectionAffinity affinity;
@property (readonly, getter=isTransient) BOOL transient;
@property CGFloat anchorPositionOffset;
@property (getter=isLogical) BOOL logical;
@property (strong, nullable) id<NSTextLocation> secondarySelectionLocation;
@property (copy) NSDictionary *typingAttributes;
- (NSTextSelection *)textSelectionWithTextRanges:(NSArray *)textRanges;
+ (BOOL)supportsSecureCoding;
@end

@interface CharonHostNSTextElement : NSObject
- (instancetype)initWithTextContentManager:(id)textContentManager;
@property (nullable, weak) id textContentManager;
@property (nullable, strong) NSTextRange *elementRange;
@property (readonly, copy) NSArray *childElements;
@property (nullable, readonly, weak) NSTextElement *parentElement;
@property (readonly) BOOL isRepresentedElement;
@end

@interface CharonHostNSTextParagraph : CharonHostNSTextElement
- (instancetype)initWithAttributedString:(NSAttributedString *)attributedString;
@property (strong, readonly) NSAttributedString *attributedString;
@property (nullable, strong, readonly) NSTextRange *paragraphContentRange;
@property (nullable, strong, readonly) NSTextRange *paragraphSeparatorRange;
@end

static Class port_range_class(void) { return NSClassFromString(@"CharonHostNSTextRange"); }
static Class port_selection_class(void) { return NSClassFromString(@"CharonHostNSTextSelection"); }
static Class port_element_class(void) { return NSClassFromString(@"CharonHostNSTextElement"); }
static Class port_paragraph_class(void) { return NSClassFromString(@"CharonHostNSTextParagraph"); }

static CharonHostNSTextRange *port_range(NSInteger from, NSInteger to)
{
    if (to < 0)
        return [[CharonHostNSTextRange alloc] initWithLocation:at(from)];
    return [[CharonHostNSTextRange alloc] initWithLocation:at(from) endLocation:at(to)];
}

static NSTextRange *system_range(NSInteger from, NSInteger to)
{
    if (to < 0)
        return [[NSTextRange alloc] initWithLocation:at(from)];
    return [[NSTextRange alloc] initWithLocation:at(from) endLocation:at(to)];
}

static void compare_text(NSString *left, NSString *right, const char *name)
{
    charon_check([left isEqualToString:right], name, [NSString stringWithFormat:@"port %@ != system %@", left, right]);
}

static NSString *described(id range)
{
    return range ? [range description] : @"(nil)";
}

static void compare_ranges(void)
{
    NSTextRange *systemEmpty = system_range(3, -1);
    CharonHostNSTextRange *portEmpty = port_range(3, -1);
    charon_check([systemEmpty isEmpty] == [portEmpty isEmpty], "a range with no end is empty on both sides",
                 @"one side is not empty");
    charon_check([systemEmpty.endLocation isEqual:systemEmpty.location] == [portEmpty.endLocation isEqual:portEmpty.location],
                 "a range with no end answers its start as its end", @"one side does not");
    compare_text(described(systemEmpty), described(portEmpty), "an empty range, described");

    NSTextRange *systemA = system_range(0, 10);
    CharonHostNSTextRange *portA = port_range(0, 10);
    NSTextRange *systemB = system_range(5, 15);
    CharonHostNSTextRange *portB = port_range(5, 15);
    NSTextRange *systemC = system_range(20, 25);
    CharonHostNSTextRange *portC = port_range(20, 25);
    NSTextRange *systemD = system_range(0, 5);
    CharonHostNSTextRange *portD = port_range(0, 5);
    compare_text(described(systemA), described(portA), "a range, described");

    for (NSInteger where = 0; where <= 11; where++) {
        charon_check([systemA containsLocation:at(where)] == [portA containsLocation:at(where)],
                     NAMED(@"0...10 contains %ld", (long)where), @"the two sides disagree");
    }
    charon_check([systemEmpty containsLocation:at(3)] == [portEmpty containsLocation:at(3)],
                 @"an empty range contains its own start, or neither does", @"the two sides disagree");
    for (NSArray *pair in @[ @[ systemD, portD ], @[ systemC, portC ], @[ systemA, portA ], @[ systemEmpty, portEmpty ] ]) {
        NSTextRange *system = pair[0];
        CharonHostNSTextRange *port = pair[1];
        charon_check([systemA containsRange:system] == [portA containsRange:port],
                     NAMED(@"0...10 contains %@", described(system)), @"the two sides disagree");
    }
    for (NSArray *pair in @[ @[ systemB, portB ], @[ systemC, portC ], @[ systemD, portD ], @[ systemEmpty, portEmpty ] ]) {
        NSTextRange *system = pair[0];
        CharonHostNSTextRange *port = pair[1];
        charon_check([systemA intersectsWithTextRange:system] == [portA intersectsWithTextRange:port],
                     NAMED(@"0...10 intersects %@", described(system)), @"the two sides disagree");
    }
    compare_text(described([systemA textRangeByIntersectingWithTextRange:systemB]),
                 described([portA textRangeByIntersectingWithTextRange:portB]), "0...10 with 5...15, intersected");
    charon_check([systemA textRangeByIntersectingWithTextRange:systemC] == nil ==
                     [portA textRangeByIntersectingWithTextRange:portC] == nil,
                 @"0...10 with 20...25 has no intersection on either side", @"one side has one");
    compare_text(described([systemA textRangeByFormingUnionWithTextRange:systemB]),
                 described([portA textRangeByFormingUnionWithTextRange:portB]), "0...10 with 5...15, unioned");
    compare_text(described([systemA textRangeByFormingUnionWithTextRange:systemC]),
                 described([portA textRangeByFormingUnionWithTextRange:portC]), "0...10 with 20...25, unioned");
    compare_text(described([systemA textRangeByFormingUnionWithTextRange:systemEmpty]),
                 described([portA textRangeByFormingUnionWithTextRange:portEmpty]), "0...10 with an empty range, unioned");
    compare_text(described([systemEmpty textRangeByFormingUnionWithTextRange:systemA]),
                 described([portEmpty textRangeByFormingUnionWithTextRange:portA]), "an empty range with 0...10, unioned");
    compare_text(described([systemEmpty textRangeByFormingUnionWithTextRange:systemEmpty]),
                 described([portEmpty textRangeByFormingUnionWithTextRange:portEmpty]), "two empty ranges, unioned");
    for (NSArray *pair in @[ @[ systemA, portA ], @[ systemB, portB ] ]) {
        NSTextRange *system = pair[0];
        CharonHostNSTextRange *port = pair[1];
        charon_check([systemA isEqualToTextRange:system] == [portA isEqualToTextRange:port],
                     NAMED(@"0...10 isEqualToTextRange %@", described(system)), @"the two sides disagree");
    }
    charon_check([systemA isEqualToTextRange:nil] == [portA isEqualToTextRange:nil],
                 @"isEqualToTextRange: nil is NO on both sides", @"one side says YES");
    charon_check([systemA isEqual:systemA] == [portA isEqual:portA], @"a range is equal to itself",
                 @"one side is not");
    charon_check([systemA isEqual:system_range(0, 10)] == [portA isEqual:port_range(0, 10)],
                 @"two ranges over the same locations are equal", @"one side is not");
    charon_check([systemA respondsToSelector:@selector(copyWithZone:)] == [portA respondsToSelector:@selector(copyWithZone:)],
                 @"neither side copies a range", @"one side has a copyWithZone:");
    charon_check([systemA isKindOfClass:[NSTextRange class]] && [portA isKindOfClass:port_range_class()],
                 @"both sides are an NSTextRange", @"one side is not");
    // The host's own hash is not a function of the range's value: two equal ranges measured with different
    // hashes. The port's is, and the check fails if the host ever starts making it consistent, so the divergence
    // is noticed rather than copied.
    charon_check([systemA hash] != [system_range(0, 10) hash],
                 @"the host still hashes two equal ranges differently", @"the host's hash is now by value");
    charon_check([portA hash] == [port_range(0, 10) hash], "the port hashes a range by its value",
                 @"two equal ranges on the port hash differently");
}

// The two answers a selection is asked that the host's own text for it is worth holding to, and the two the
// header's comment and the system disagree about.
static void compare_selections(void)
{
    NSTextSelection *systemOne = [[NSTextSelection alloc] initWithRange:system_range(0, 5)
                                                 affinity:NSTextSelectionAffinityDownstream
                                              granularity:NSTextSelectionGranularityCharacter];
    CharonHostNSTextSelection *portOne = [[CharonHostNSTextSelection alloc] initWithRange:port_range(0, 5)
                                                      affinity:NSTextSelectionAffinityDownstream
                                                   granularity:NSTextSelectionGranularityCharacter];
    compare_text(described(systemOne), described(portOne), "a selection, described");
    charon_check([[systemOne textRanges] count] == [[portOne textRanges] count], "one range either way",
                 @"the two sides disagree on the count");
    charon_check([systemOne affinity] == [portOne affinity] && [systemOne granularity] == [portOne granularity],
                 "the affinity and the granularity are kept", @"one side differs");
    charon_check([systemOne isTransient] == [portOne isTransient], "neither side is transient",
                 @"one side is");
    charon_check([systemOne isLogical] == [portOne isLogical], "neither side is logical to begin with",
                 @"one side is");
    charon_check([systemOne anchorPositionOffset] == [portOne anchorPositionOffset], "the anchor offset starts at zero",
                 @"one side does not");
    charon_check([[systemOne typingAttributes] count] == [[portOne typingAttributes] count] &&
                      [systemOne typingAttributes] != nil && [portOne typingAttributes] != nil,
                 "a selection with no typing attributes answers an empty dictionary, not nil", @"one side answers nil");

    // The header says ranges handed in out of order or overlapping are normalised. The host keeps them, in the
    // order it was given them, and the port does the same; the check fails if the host ever starts normalising.
    NSArray *messy = @[ system_range(20, 25), system_range(0, 10), system_range(5, 15) ];
    NSArray *portMessy = @[ port_range(20, 25), port_range(0, 10), port_range(5, 15) ];
    NSTextSelection *systemUntidy = [[NSTextSelection alloc] initWithRanges:messy
                                                      affinity:NSTextSelectionAffinityUpstream
                                                   granularity:NSTextSelectionGranularityWord];
    CharonHostNSTextSelection *portUntidy = [[CharonHostNSTextSelection alloc] initWithRanges:portMessy
                                                          affinity:NSTextSelectionAffinityUpstream
                                                       granularity:NSTextSelectionGranularityWord];
    compare_text(described(systemUntidy), described(portUntidy),
                 "a selection handed overlapping ranges out of order, described");
    NSMutableString *systemOrder = [NSMutableString string], *portOrder = [NSMutableString string];
    for (NSUInteger i = 0; i < [systemUntidy.textRanges count]; i++) {
        [systemOrder appendFormat:@"%@ ", [systemUntidy.textRanges[i] description]];
        [portOrder appendFormat:@"%@ ", [portUntidy.textRanges[i] description]];
    }
    compare_text(systemOrder, portOrder, "the order the ranges are held in");
    charon_check([systemUntidy.textRanges count] == [portUntidy.textRanges count] == (NSUInteger)3,
                 @"three ranges in, three ranges out", @"a side merged or dropped one");

    NSTextSelection *systemTouching = [[NSTextSelection alloc] initWithRanges:@[ system_range(0, 5), system_range(5, 10) ]
                                                       affinity:NSTextSelectionAffinityUpstream
                                                    granularity:NSTextSelectionGranularityWord];
    CharonHostNSTextSelection *portTouching = [[CharonHostNSTextSelection alloc] initWithRanges:@[ port_range(0, 5), port_range(5, 10) ]
                                                            affinity:NSTextSelectionAffinityUpstream
                                                         granularity:NSTextSelectionGranularityWord];
    compare_text(described(systemTouching), described(portTouching), "a selection handed two touching ranges, described");

    NSTextSelection *systemNone = [[NSTextSelection alloc] initWithRanges:@[]
                                                    affinity:NSTextSelectionAffinityDownstream
                                                 granularity:NSTextSelectionGranularityCharacter];
    CharonHostNSTextSelection *portNone = [[CharonHostNSTextSelection alloc] initWithRanges:@[]
                                                        affinity:NSTextSelectionAffinityDownstream
                                                     granularity:NSTextSelectionGranularityCharacter];
    charon_check(systemNone.textRanges.count == 0 && portNone.textRanges.count == 0, "a selection of no ranges is empty",
                 @"one side is not");

    NSTextSelection *systemCursor = [[NSTextSelection alloc] initWithLocation:at(4) affinity:NSTextSelectionAffinityDownstream];
    CharonHostNSTextSelection *portCursor = [[CharonHostNSTextSelection alloc] initWithLocation:at(4) affinity:NSTextSelectionAffinityDownstream];
    compare_text(described(systemCursor), described(portCursor), "a selection of one location, described");
    charon_check(systemCursor.granularity == [portCursor granularity], "a cursor is a character granularity",
                 @"one side differs");

    [systemOne setSecondarySelectionLocation:at(8)];
    [portOne setSecondarySelectionLocation:at(8)];
    charon_check([systemOne isLogical] == [portOne isLogical], "a secondary location makes a selection not logical",
                 @"one side is");
    charon_check(![systemOne isLogical] == ![portOne isLogical],
                 "and the header's side effect is the same on both sides", @"one side is logical");
    [systemOne setLogical:YES];
    [portOne setLogical:YES];
    charon_check([systemOne isLogical] == [portOne isLogical], "logical can be set back", @"one side cannot");

    NSTextSelection *systemOther = [systemOne textSelectionWithTextRanges:@[ system_range(1, 2) ]];
    CharonHostNSTextSelection *portOther = [portOne textSelectionWithTextRanges:@[ port_range(1, 2) ]];
    compare_text(described(systemOther), described(portOther), "a selection with new ranges, described");
    charon_check([systemOther affinity] == [portOther affinity] && [systemOther isLogical] == [portOther isLogical] &&
                      [[systemOther typingAttributes] count] == [[portOther typingAttributes] count],
                 "a copy keeps the affinity, the logical flag and the typing attributes", @"one side differs");
    compare_text(described(systemOne), described(portOne), "and the selection it was made from is unchanged");

    [systemOne setAnchorPositionOffset:1.5];
    [portOne setAnchorPositionOffset:1.5];
    [systemOne setTypingAttributes:@{ NSFontAttributeName : [UIFont systemFontOfSize:12] }];
    [portOne setTypingAttributes:@{ NSFontAttributeName : [UIFont systemFontOfSize:12] }];
    charon_check(systemOne.anchorPositionOffset == [portOne anchorPositionOffset], "the anchor offset is kept",
                 @"one side differs");
    charon_check([[systemOne typingAttributes] count] == [[portOne typingAttributes] count] &&
                      [[[systemOne typingAttributes] objectForKey:NSFontAttributeName] isEqual:
                          [[portOne typingAttributes] objectForKey:NSFontAttributeName]],
                 "the typing attributes are kept", @"one side differs");
    NSTextSelection *systemCopied = [systemOne textSelectionWithTextRanges:systemOne.textRanges];
    CharonHostNSTextSelection *portCopied = [portOne textSelectionWithTextRanges:portOne.textRanges];
    charon_check([[systemCopied typingAttributes] count] == [[portCopied typingAttributes] count] &&
                      systemCopied.anchorPositionOffset == [portCopied anchorPositionOffset],
                 "a copy carries the anchor offset and the typing attributes", @"one side differs");

    // The host takes anything in the ranges array, including something that is not a range at all.
    NSTextSelection *systemForeign = nil;
    CharonHostNSTextSelection *portForeign = nil;
    @try {
        systemForeign = [[NSTextSelection alloc] initWithRanges:(NSArray *)@[ @"not a range" ]
                                                         affinity:NSTextSelectionAffinityDownstream
                                                      granularity:NSTextSelectionGranularityCharacter];
    } @catch (NSException *exception) {
        charon_check(NO, "the host takes a range that is not an NSTextRange", [NSString stringWithUTF8String:[exception name].UTF8String]);
    }
    @try {
        portForeign = [[CharonHostNSTextSelection alloc] initWithRanges:(NSArray *)@[ @"not a range" ]
                                                            affinity:NSTextSelectionAffinityDownstream
                                                         granularity:NSTextSelectionGranularityCharacter];
    } @catch (NSException *exception) {
        charon_check(NO, "the port takes a range that is not an NSTextRange", [NSString stringWithUTF8String:[exception name].UTF8String]);
    }
    charon_check((systemForeign != nil) == (portForeign != nil), "both sides take a range that is not a range",
                 @"one side refuses it");
    charon_check([[NSTextSelection class] supportsSecureCoding] == [port_selection_class() supportsSecureCoding],
                 "both sides say they support secure coding", @"one side does not");
}

static void compare_elements(void)
{
    NSTextParagraph *systemPlain = [[NSTextParagraph alloc] initWithAttributedString:[[NSAttributedString alloc] initWithString:@"Hello"]];
    CharonHostNSTextParagraph *portPlain = [[CharonHostNSTextParagraph alloc] initWithAttributedString:[[NSAttributedString alloc] initWithString:@"Hello"]];
    charon_check(systemPlain.attributedString.length == [portPlain attributedString].length,
                 "a paragraph keeps the string it was given", @"one side does not");
    charon_check([systemPlain isRepresentedElement] == [portPlain isRepresentedElement],
                 "a paragraph is a represented element on both sides", @"one side is not");
    charon_check(systemPlain.childElements.count == [portPlain childElements].count,
                 "a paragraph has no children on either side", @"one side has some");
    charon_check(systemPlain.parentElement == nil && [portPlain parentElement] == nil,
                 "a paragraph has no parent on either side", @"one side has one");
    // The two derived ranges are nil until the element has a range in a document, which is what the header's own
    // derivation says and what the host answers.
    for (NSString *text in @[ @"Hello", @"Hello\n", @"Hello\r\n", @"\n", @"a\nb" ]) {
        NSTextParagraph *system = [[NSTextParagraph alloc] initWithAttributedString:[[NSAttributedString alloc] initWithString:text]];
        CharonHostNSTextParagraph *port = [[CharonHostNSTextParagraph alloc] initWithAttributedString:[[NSAttributedString alloc] initWithString:text]];
        charon_check((system.paragraphContentRange == nil) == ([port paragraphContentRange] == nil) &&
                          (system.paragraphSeparatorRange == nil) == ([port paragraphSeparatorRange] == nil),
                     NAMED(@"%@ derives no range without an element range", text), @"one side derives one");
    }
    // With a range set, both sides place the two ranges in the document, the content without the trailing
    // newline and the separator that newline.
    NSTextParagraph *systemWith = [[NSTextParagraph alloc] initWithAttributedString:[[NSAttributedString alloc] initWithString:@"Hello\n"]];
    [systemWith setElementRange:system_range(100, 106)];
    CharonHostNSTextParagraph *portWith = [[CharonHostNSTextParagraph alloc] initWithAttributedString:[[NSAttributedString alloc] initWithString:@"Hello\n"]];
    [portWith setElementRange:port_range(100, 106)];
    charon_check(systemWith.paragraphContentRange != nil && [portWith paragraphContentRange] != nil,
                 "with a range set the content range is there on both sides", @"one side has none");
    if (systemWith.paragraphContentRange && [portWith paragraphContentRange]) {
        compare_text(described(systemWith.paragraphContentRange), described([portWith paragraphContentRange]),
                     "the content range of Hello<LF> at 100");
        compare_text(described(systemWith.paragraphSeparatorRange), described([portWith paragraphSeparatorRange]),
                     "the separator range of Hello<LF> at 100");
    }
    NSTextParagraph *systemCrlf = [[NSTextParagraph alloc] initWithAttributedString:[[NSAttributedString alloc] initWithString:@"Hi\r\n"]];
    [systemCrlf setElementRange:system_range(0, 4)];
    CharonHostNSTextParagraph *portCrlf = [[CharonHostNSTextParagraph alloc] initWithAttributedString:[[NSAttributedString alloc] initWithString:@"Hi\r\n"]];
    [portCrlf setElementRange:port_range(0, 4)];
    if (systemCrlf.paragraphSeparatorRange && [portCrlf paragraphSeparatorRange])
        compare_text(described(systemCrlf.paragraphSeparatorRange), described([portCrlf paragraphSeparatorRange]),
                     "the separator range of Hi<CR><LF>");
    // The base element: a represented element on both sides, no children, no parent, and a range it keeps.
    NSTextElement *systemElement = [[NSTextElement alloc] initWithTextContentManager:nil];
    CharonHostNSTextElement *portElement = [[CharonHostNSTextElement alloc] initWithTextContentManager:nil];
    charon_check([systemElement isRepresentedElement] == [portElement isRepresentedElement],
                 "the base element is a represented element on both sides", @"one side is not");
    charon_check(systemElement.childElements.count == [portElement childElements].count,
                 "the base element has no children on either side", @"one side has some");
    [systemElement setElementRange:system_range(0, 6)];
    [portElement setElementRange:port_range(0, 6)];
    compare_text(described(systemElement.elementRange), described([portElement elementRange]),
                 "the range an element keeps");
    charon_check(systemElement.textContentManager == nil && [portElement textContentManager] == nil,
                 "an element with no manager keeps none on either side", @"one side has one");
    NSTextParagraph *systemEmpty = [[NSTextParagraph alloc] initWithAttributedString:nil];
    CharonHostNSTextParagraph *portEmpty = [[CharonHostNSTextParagraph alloc] initWithAttributedString:nil];
    charon_check(systemEmpty.attributedString == nil && [portEmpty attributedString] == nil,
                 "a paragraph made with no string keeps none on either side", @"one side has one");
}

int main(void)
{
    @autoreleasepool {
        compare_ranges();
        compare_selections();
        compare_elements();
    }
    return 0;
}
