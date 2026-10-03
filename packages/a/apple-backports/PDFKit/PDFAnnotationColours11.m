#import "CharonPDFKit.h"

// PDFAnnotation's three colours and its font, and the file they are in.
//
// WHY THIS IS AN OBJECT OF ITS OWN: all four members return UIColor or UIFont, which are the classes the
// 26.2 header calls PDFKitPlatformColor and PDFKitPlatformFont, and there is no Foundation class for
// either on iOS.  The harness's macOS port side builds every other object of this library and has no
// UIKit at all, so a UIKit import anywhere else in PDFKit stops that build dead - which is what happened
// the first time these four sat at the foot of PDFAnnotation11.m.  Here it is the ONLY import, so the one
// binary that has UIKit (Mac Catalyst, tests/backports/host/pdfkit-document/color.m) links this object
// and the one that does not leaves it out.  PDFAnnotation11.m declares none of it and shares no function
// with this file: every helper below is static, so there is no C symbol one file needs from the other -
// which is the trap a file that exports API and lends a C function to a sibling walks into, where the
// sibling is left out of a later band and the link fails only there.
//
// Every reading here is keyed by the annotation's own /NM rather than by its position, over
// annotation-colours.pdf, which is why the fixture carries one: the host drops one annotation of the ones
// it writes, and a list read by index is one annotation out of step from that point on.  The table and the
// readings it retracts are in facts/PDFKit/Annotation11.md.

// UIKit, for the two classes the header calls the platform's colour and font.  Both arrived with the
// release's first UIKit, so nothing here is later than the library's minimum.
#import <UIKit/UIKit.h>

// The four are COMPUTED from the annotation dictionary on every call, so @dynamic says "not an ivar" - and
// all four are BUILT rather than read out of a cache: a colour is a value of no identity and a font of
// none either, so there is nothing to memoise and nothing an identity could mean.
@implementation PDFAnnotation (PDFAnnotationColours)
@dynamic backgroundColor;
@dynamic interiorColor;
@dynamic font;

// ---- the three colours and the font, keyed by the annotation's own dictionary --------------------
//
// Everything below reads one key out of the annotation dictionary and nothing else.  The measurements
// are over annotation-colours.pdf, whose 48 annotations all carry a /NM and are read through it: the
// first version of that fixture was read by INDEX, the host drops one annotation of the 27 it wrote, and
// every reading after the sixth was therefore a reading of the wrong annotation.  facts/PDFKit/
// Annotation11.md carries the table and the retracted readings.

// One component of a PDF colour array, as a double, or false when it is not a number at all.
//
// BOTH OBJECT TYPES, and that is the whole of it.  A PDF colour array is written with its components as
// bare numbers, and CoreGraphics types a bare `1' as kCGPDFObjectTypeInteger and a `0.5' as
// kCGPDFObjectTypeReal - so [1 0 0] is three integers and [0.25] is one real, and CGPDFArrayGetNumber,
// which reads only the real kind, is false for every one of the integers a file actually writes.  That
// is how this member answered nil for bg-rgb, bg-btn, bg-bc-beside and for every /IC of three integers
// on the first run of this file, while the host answered all of them - and it is why the two cases are
// written out rather than one reader asked for a double.
static BOOL charon_pdfNumber(CGPDFArrayRef array, size_t index, double *out)
{
    CGPDFObjectRef component = NULL;
    if (!CGPDFArrayGetObject(array, index, &component) || component == NULL)
        return NO;
    switch (CGPDFObjectGetType(component)) {
    case kCGPDFObjectTypeInteger: {
        long integer = 0;
        if (!CGPDFObjectGetValue(component, kCGPDFObjectTypeInteger, &integer))
            return NO;
        *out = (double)integer;
        return YES;
    }
    case kCGPDFObjectTypeReal: {
        double real = 0;
        if (!CGPDFObjectGetValue(component, kCGPDFObjectTypeReal, &real))
            return NO;
        *out = real;
        return YES;
    }
    default:
        // a name, a string, an array, a dictionary or a stream is not a colour component
        return NO;
    }
}

// A colour in one of the three DEVICE spaces, from a PDF colour array.  PDF 1.7 Table 8.40 defines the
// shapes: no component is no colour, one is gray, three is RGB and four is CMYK.  The components are the
// ARRAY'S OWN - the host's answer for [1 0 0] is kCGColorSpaceDeviceRGB carrying 1, 0, 0, 1, and an
// earlier version of these facts that printed it as 0.986, 0, 0.027 had converted it to sRGB in its own
// probe, which is a reading of the probe and not of the host.  Nothing here converts.
static UIColor *charon_deviceColour(CGPDFArrayRef array)
{
    if (array == NULL)
        return nil;
    size_t components = CGPDFArrayGetCount(array);
    CGColorSpaceRef space = NULL;
    if (components == 1)
        space = CGColorSpaceCreateDeviceGray();
    else if (components == 3)
        space = CGColorSpaceCreateDeviceRGB();
    else if (components == 4)
        space = CGColorSpaceCreateDeviceCMYK();
    // no component, or a shape Table 8.40 does not define: not a colour
    if (space == NULL)
        return nil;
    CGFloat values[4] = {0, 0, 0, 0};
    for (size_t i = 0; i < components; i++) {
        double component = 0;
        if (!charon_pdfNumber(array, i + 1, &component)) {
            CGColorSpaceRelease(space);
            return nil;
        }
        values[i] = (CGFloat)component;
    }
    CGColorRef colour = CGColorCreate(space, values);
    CGColorSpaceRelease(space);
    if (colour == NULL)
        return nil;
    UIColor *answer = [UIColor colorWithCGColor:colour];
    CGColorRelease(colour);
    return answer;
}

// The colour off a PDF colour ARRAY or name key, which is nil when the annotation does not carry it.
static UIColor *charon_colourForKey(CGPDFDictionaryRef annotation, const char *key, BOOL appearance)
{
    if (annotation == NULL)
        return nil;
    CGPDFObjectRef found = NULL;
    if (appearance) {
        // one level down: /MK is a DICTIONARY and /BG is inside it, which is the whole difference between
        // this and the annotation's own /IC and the reason an earlier batch wrote /MK /BC
        CGPDFObjectRef mark = NULL;
        if (!CGPDFDictionaryGetObject(annotation, "MK", &mark) || mark == NULL
            || CGPDFObjectGetType(mark) != kCGPDFObjectTypeDictionary)
            return nil;
        CGPDFDictionaryRef appearanceDictionary = NULL;
        if (!CGPDFObjectGetValue(mark, kCGPDFObjectTypeDictionary, &appearanceDictionary)
            || appearanceDictionary == NULL)
            return nil;
        CGPDFArrayRef array = NULL;
        if (!CGPDFDictionaryGetArray(appearanceDictionary, key, &array) || array == NULL)
            return nil;
        return charon_deviceColour(array);
    }
    if (!CGPDFDictionaryGetObject(annotation, key, &found) || found == NULL
        || CGPDFObjectGetType(found) != kCGPDFObjectTypeArray)
        return nil;
    CGPDFArrayRef array = NULL;
    if (!CGPDFObjectGetValue(found, kCGPDFObjectTypeArray, &array) || array == NULL)
        return nil;
    return charon_deviceColour(array);
}

- (UIColor *)backgroundColor
{
    // /MK's /BG, and NOT /BC: /BC is the border colour of Table 8.40 and is the key -border reads, and
    // bg-bc-beside carries both and answers the /BG - measured, keyed by /NM.
    return charon_colourForKey([self charon_CGPDFDictionary], "BG", YES);
}

- (UIColor *)interiorColor
{
    // the annotation's OWN /IC, which is not an /MK key, and which the host reads on more subtypes than
    // the header names - ic-link and ic-widget answer it beside ic-square-rgb and ic-circle-cmyk.
    return charon_colourForKey([self charon_CGPDFDictionary], "IC", NO);
}

// The /DA as the tokens a reader can take off it: whitespace-separated words, in order, each either a
// name - written /x in the file, slash and all - or something else, which is a number.  An NSArray of
// NSString rather than a C array of object pointers under ARC, which cannot be written to through a plain
// `NSString **` at all; and one filter, because an EMPTY word between two spaces is not a token of a
// content stream.
static NSArray *charon_daTokens(NSString *text)
{
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSString *word in [text componentsSeparatedByCharactersInSet:
                            [NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
        if (word.length == 0)
            continue;
        // the slash is KEPT: a name and an operator are told apart by it, and the two callers below both
        // need to know which one a token is
        [tokens addObject:word];
    }
    return tokens;
}

// Whether a token is an OPERATOR - that is, an operator and not a name, which is what tells `/g' the name
// of a font from `g' the gray operator.  One token cannot be both: in a content stream a token written
// /x is a name and a token written x is a keyword or a number.
static BOOL charon_daIsOperator(NSString *token, NSString *wanted)
{
    return [token isEqualToString:wanted];
}

// The /DA's font NAME and SIZE.  Three clauses, and every one of them is pinned by a named fixture over
// annotation-colours.pdf:
//
//   1  the name AS WRITTEN, when the platform has a font of that name: font-courier-7 (/Courier) answers
//      Courier, and font-full-oblique (/Helvetica-Oblique) and font-full-roman (/Times-Roman) answer
//      themselves - the abbreviations below are a fallback and not the whole of the lookup.
//   2  an EXACT table of THREE abbreviations: Helv, HeBo and Cour.  That is the whole of what the host
//      resolves out of the standard fourteen's fourteen - font-abbrev-hebo answers Helvetica-Bold and
//      font-abbrev-cour answers Courier, while HeOb, HeBO, CoBo, CoOb, CBO, TiRo, TiBo, TiIt, TiBI,
//      Symb and ZaDb all answer Helvetica.  -[NSFont fontWithName:] is nil for every one of the fourteen
//      (measured on this Mac), so this is PDFKit's own table and not the platform's lookup.  It is EXACT
//      and case-SENSITIVE: font-case-upper (/HELV), font-case-mixed (/Hebo) and the three prefixes
//      font-prefix-h, font-prefix-co and font-prefix-ti (/H, /Co, /Ti) all answer Helvetica.
//   3  anything else is HELVETICA - font-unknown (/Nonexistent) and the eleven abbreviations of clause 2 -
//      with the SIZE KEPT, which is what /Nonexistent 9 answering Helvetica at 9 measures.
//
// The size is read independently of the name and defaults to 12: font-size-only (`12 Tf', no name)
// answers Helvetica 12, font-name-only (`/Helv Tf', no size) answers Helvetica 12, and an annotation with
// no /DA at all answers Helvetica 12 over every other member of the fixture.
- (UIFont *)font
{
    static NSString *const kDefaultName = @"Helvetica";
    static const CGFloat kDefaultSize = 12;
    CGPDFDictionaryRef annotation = [self charon_CGPDFDictionary];
    if (annotation == NULL)
        return [UIFont fontWithName:kDefaultName size:kDefaultSize];
    NSString *name = nil;
    CGFloat size = kDefaultSize;
    CGPDFObjectRef found = NULL;
    if (CGPDFDictionaryGetObject(annotation, "DA", &found) && found != NULL
        && CGPDFObjectGetType(found) == kCGPDFObjectTypeString) {
        CGPDFStringRef string = NULL;
        if (CGPDFObjectGetValue(found, kCGPDFObjectTypeString, &string) && string != NULL) {
            CFStringRef text = CGPDFStringCopyTextString(string);
            if (text != NULL) {
                NSArray *tokens = charon_daTokens((__bridge NSString *)text);
                for (NSUInteger i = 0; i < tokens.count; i++) {
                    if (!charon_daIsOperator(tokens[i], @"Tf") || i < 2)
                        continue;
                    // `/Name Size Tf': the NAME is a token written /x, so it is the one that came off the
                    // string with its slash, and the SIZE is the number in front of it.  font-size-only
                    // writes `12 Tf' with no name at all and answers Helvetica at 12, which is the default
                    // size rather than a name read - so the size is read on its own and never from a name.
                    NSString *sizeToken = tokens[i - 1];
                    if ([sizeToken hasPrefix:@"/"])
                        break;
                    if (i >= 2) {
                        NSString *nameToken = tokens[i - 2];
                        if ([nameToken hasPrefix:@"/"]) {
                            name = [nameToken substringFromIndex:1];
                            size = (CGFloat)[sizeToken doubleValue];
                        } else {
                            size = (CGFloat)[sizeToken doubleValue];
                        }
                    } else {
                        size = (CGFloat)[sizeToken doubleValue];
                    }
                    break;
                }
            }
        }
    }
    NSString *wanted = nil;
    if (name != nil) {
        // clause 1: the name as written, if the platform has it
        if ([UIFont fontWithName:name size:size] != nil)
            wanted = name;
        // clause 2: the three abbreviations, matched EXACTLY
        else if ([name isEqualToString:@"Helv"])
            wanted = @"Helvetica";
        else if ([name isEqualToString:@"HeBo"])
            wanted = @"Helvetica-Bold";
        else if ([name isEqualToString:@"Cour"])
            wanted = @"Courier";
    }
    // clause 3, and the no-/DA default: Helvetica at the size that IS there, or at 12 when none is
    UIFont *answer = [UIFont fontWithName:(wanted ?: kDefaultName) size:size];
    return answer != nil ? answer : [UIFont fontWithName:kDefaultName size:size];
}

@end
