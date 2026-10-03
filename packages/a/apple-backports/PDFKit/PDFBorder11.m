#import "CharonPDFKit.h"

// PDFBorder over the annotation dictionary CoreGraphics already parsed.  A border in the format is
// two spellings in one annotation: the /Border ARRAY of PDF 1.7 Table 164, three numbers of which the
// host reads one, and the /BS DICTIONARY of Table 8.44, which carries the style and the dash pattern.
// Every rule below is measured on the host over fixtures whose dictionaries this harness wrote, and
// each names the fixture that fixes it.

// The /BS /S name to PDFBorderStyle, and it is a TABLE and not an ordinal: the enum's five values are
// solid, dashed, beveled, inset, underline in the header's order, and the format's five names are
// /S /D /B /I /U in the same order, so reading the name as its position would fit.  All five are
// measured - bs-s, bs-d, bs-b, bs-i and bs-u each answer the value the enum names - and so is a name
// the format does not list: bs-q carries /S /Q and answers kPDFBorderStyleSolid, not an out-of-range
// value.  So an unknown name is solid, and that is measured rather than assumed.
static PDFBorderStyle charonBorderStyleForName(const char *name)
{
    if (name == NULL)
        return kPDFBorderStyleSolid;
    if (strcmp(name, "S") == 0)
        return kPDFBorderStyleSolid;
    if (strcmp(name, "D") == 0)
        return kPDFBorderStyleDashed;
    if (strcmp(name, "B") == 0)
        return kPDFBorderStyleBeveled;
    if (strcmp(name, "I") == 0)
        return kPDFBorderStyleInset;
    if (strcmp(name, "U") == 0)
        return kPDFBorderStyleUnderline;
    return kPDFBorderStyleSolid;
}

// The dash pattern a DASHED border answers when its /D is not an array of numbers: [3 2], measured.
// bs-d carries /S /D and no /D at all and answers [3 2]; bs-dash-string carries /S /D and a /D that is
// a PDF string and answers the same [3 2]; and bs-dash-custom carries /S /D with /D [7 5] and answers
// [7 5], which is the fixture that shows the array is read at all and that [3 2] is a default rather
// than the only answer.
//
// A border that is not dashed answers nil for the pattern however its /D is written: bs-dash-solid
// carries /S /S with /D [4 1] and answers nil.
static NSArray *charonDefaultDashPattern(void)
{
    return [NSArray arrayWithObjects:[NSNumber numberWithDouble:3.0], [NSNumber numberWithDouble:2.0], nil];
}

@implementation PDFBorder {
    CGPDFDictionaryRef _annotation;
    // Memoised because -dashPattern reads -style and -borderKeyValues reads both members, and a
    // pattern is a copy rather than a walk of the dictionary each time.
    NSArray *_dashPattern;
}

// Each of the four members is COMPUTED from the dictionary on every call, so @dynamic says "not an
// ivar" and NOTHING else: a @dynamic property with no body raises at run time, which is what the first
// version of PDFPage's -label did and what the harness's crash was.  Each has a body below.
@dynamic style;
@dynamic lineWidth;
@dynamic dashPattern;
@dynamic borderKeyValues;

- (instancetype)initWithCharonAnnotationDictionary:(CGPDFDictionaryRef)annotation
{
    self = [super init];
    if (self == nil)
        return nil;
    // The dictionary belongs to the CGPDFDocument, which the PDFDocument holds, and a border is only
    // reachable from an annotation of that document - so the owner is above us in the graph and the
    // borrowed pointer is safe for as long as this object is.
    _annotation = annotation;
    return self;
}

// The /BS dictionary, or NULL.  It is looked up per call rather than cached, because the dictionary
// cannot change under this object and a cached pointer would be one more borrowed pointer to keep.
- (CGPDFDictionaryRef)charonBorderStyleDictionary
{
    if (_annotation == NULL)
        return NULL;
    CGPDFDictionaryRef style = NULL;
    if (!CGPDFDictionaryGetDictionary(_annotation, "BS", &style))
        return NULL;
    return style;
}

// -style reads /BS /S, and nothing else.  No fixture writes a style anywhere but /BS, and an
// annotation whose /Border names three numbers answers kPDFBorderStyleSolid on all of them
// (border-plain, border-radii, border-zero, border-negative, border-long), so the array carries no
// style at all.
- (PDFBorderStyle)style
{
    if (_annotation == NULL)
        return kPDFBorderStyleSolid;
    CGPDFDictionaryRef style = [self charonBorderStyleDictionary];
    if (style == NULL)
        return kPDFBorderStyleSolid;
    const char *name = NULL;
    if (!CGPDFDictionaryGetName(style, "S", &name))
        return kPDFBorderStyleSolid;
    return charonBorderStyleForName(name);
}

// -lineWidth is the /BS /W when the dictionary has one, and the THIRD number of the /Border array
// when it does not.  The two are told apart by bs-width-only, which writes /Border [0 0 7] beside a
// /BS whose only entry is /W 5 and answers 5 - so /W wins - and by border-plain, which writes
// /Border [0 0 3] and no /BS and answers 3.
//
// That it is the third element and not the last is border-long: /Border [1 2 3 4] answers 3, not 4.
// That the two corner radii are ignored is border-radii: /Border [5 7 2] answers 2.  That a negative
// number is a number is border-negative: /Border [0 0 -2.5] answers -2.5.  That a zero is a value
// rather than an absent one is border-zero: /Border [0 0 0] answers 0, not the default.
//
// The default is 1, and three fixtures fix it where the third element is missing: border-short
// (/Border [0 0]), border-radii-only (/Border [5 7]) and bs-no-width (a /BS with a style and no /W
// and no /Border) all answer 1.
//
// A /W that is not a number is REFUSED rather than coerced: bs-width-string writes /W (a PDF string)
// with a dashed /S and no /Border, and the width answers the default 1 while the STYLE answers
// dashed.  So the width and the style are read independently and one unreadable key does not lose
// the other.  CGPDFDictionaryGetNumber is the reader that answers both spellings of a PDF number, an
// integer and a real, so a /W written as 4 and one written as 4.0 are the same width.
- (CGFloat)lineWidth
{
    if (_annotation == NULL)
        return 1.0;
    CGPDFDictionaryRef style = [self charonBorderStyleDictionary];
    if (style != NULL) {
        // CGPDFReal and not double: it is CGFloat, which is a float on armv7 and a double on arm64,
        // and the release's reader writes through that pointer.  A double * would be a different type
        // on the band the port builds for.
        CGPDFReal width = 0;
        if (CGPDFDictionaryGetNumber(style, "W", &width))
            return (CGFloat)width;
    }
    CGPDFArrayRef array = NULL;
    if (!CGPDFDictionaryGetArray(_annotation, "Border", &array) || array == NULL)
        return 1.0;
    CGPDFReal width = 0;
    if (!CGPDFArrayGetNumber(array, 2, &width))
        return 1.0;
    return (CGFloat)width;
}

// -dashPattern answers the /BS /D when the style is DASHED, and nil for every other style.  The
// fixture for the second half is bs-dash-solid: /S /S beside /D [4 1] answers nil, so a pattern is not
// read from a border that is not dashed.
- (NSArray *)dashPattern
{
    if (_dashPattern != nil)
        return _dashPattern;
    if ([self style] != kPDFBorderStyleDashed)
        return nil;
    NSMutableArray *pattern = [NSMutableArray array];
    CGPDFDictionaryRef style = [self charonBorderStyleDictionary];
    if (style != NULL) {
        CGPDFArrayRef array = NULL;
        if (CGPDFDictionaryGetArray(style, "D", &array) && array != NULL) {
            size_t count = CGPDFArrayGetCount(array);
            for (size_t i = 0; i < count; i++) {
                CGPDFReal number = 0;
                if (!CGPDFArrayGetNumber(array, i, &number))
                    continue;
                [pattern addObject:[NSNumber numberWithDouble:(double)number]];
            }
        }
    }
    // An absent /D, a /D that is not an array, and a /D whose elements are not numbers all leave the
    // pattern empty, and an empty pattern is the measured default [3 2] rather than an empty answer.
    if (pattern.count == 0) {
        _dashPattern = charonDefaultDashPattern();
        return _dashPattern;
    }
    _dashPattern = pattern;
    return _dashPattern;
}

// The key values, which is the dictionary the three members above are read out of, in the header's own
// key names (PDFBorderKeyLineWidth is @"W", PDFBorderKeyStyle is @"S" and PDFBorderKeyDashPattern is
// @"D"): W and S are always there, because both members always answer a value, and D is there
// exactly when -dashPattern answers one.
//
// Measured: border-plain carries /Border [0 0 3] and no /BS and answers two keys, W and S;
// bs-dash-solid carries /S /S with /D [4 1] and also answers two, because the pattern is nil; bs-d and
// border-bs carry a dashed style and answer three.
- (NSDictionary *)borderKeyValues
{
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    [values setObject:[NSNumber numberWithInteger:(NSInteger)[self style]] forKey:PDFBorderKeyStyle];
    [values setObject:[NSNumber numberWithDouble:(double)[self lineWidth]] forKey:PDFBorderKeyLineWidth];
    NSArray *pattern = [self dashPattern];
    if (pattern != nil)
        [values setObject:pattern forKey:PDFBorderKeyDashPattern];
    return values;
}

@end