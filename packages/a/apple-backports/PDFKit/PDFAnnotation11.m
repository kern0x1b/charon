#import "CharonPDFKit.h"

// PDFAnnotation over the release's own CGPDFDictionary.  Every answer is the annotation dictionary
// read back through CoreGraphics, plus the two rules the host's measurements established about it:
// a /Text annotation is shown as a 24x24 note icon, and /F's Print bit is what -shouldPrint reads.
//
// What is NOT here is as deliberate as what is.  A member whose host answer depends on something
// this dictionary does not carry is left unimplemented and its row says why, rather than answered
// with a constant that the next fixture would break.

// The size a /Text annotation answers on BOTH axes, measured on rects of 200x50 and 490x70, which both
// answer 24x24 - so it is a constant of the host's answer and not a function of the rectangle.  Named,
// and commented with what was NOT measured about it, so it is read as the measurement it is.
static const CGFloat kTextAnnotationSize = 24.0;

@interface PDFAnnotation ()
- (nullable CGPDFDictionaryRef)charon_CGPDFAnnotation;
@end

@implementation PDFAnnotation {
    CGPDFDictionaryRef _annotation;
    // Weak, as the header declares it (PDFAnnotation.h:141): the page answers nil once the document
    // has gone, and the annotation does not keep a document alive.
    __weak PDFPage *_page;
    NSString *_type;
    NSString *_contents;
    NSString *_userName;
    NSDate *_modificationDate;
}

// The port's own constructor, over the dictionary CoreGraphics already parsed out of the page's
// /Annots, and over the page it was found on.  Not Apple's initializer: -initWithBounds:forType:
// builds an annotation and writes it back into a document, which is the write path and not this.
- (instancetype)initWithCharonDictionary:(CGPDFDictionaryRef)annotation onPage:(PDFPage *)page
{
    self = [super init];
    if (self == nil)
        return nil;
    // The CGPDFDictionary belongs to the CGPDFDocument, which PDFDocument holds, and this annotation
    // is only ever reachable from a page of that document - so the owner is above us in the graph
    // and the borrowed pointer is safe for the lifetime of this object.
    _annotation = annotation;
    _page = page;
    return self;
}

- (CGPDFDictionaryRef)charon_CGPDFAnnotation
{
    return _annotation;
}

// -type, -contents, -userName and -modificationDate are memoised in their own ivars, but -bounds and
// -shouldPrint are COMPUTED from the dictionary on every call, and @dynamic is what says that.  Left
// to auto-synthesis, clang invents an ivar for each of them and then warns that the accessor never
// touches it - the same trap PDFPage11.m records for -label and -numberOfCharacters.
@dynamic bounds;
@dynamic shouldPrint;

// The other five ARE ivar-backed, and each is bound to its own ivar explicitly.  The gate compiles with
// -Werror=objc-missing-property-synthesis, which fires on a property that has a hand-written accessor and
// no explicit @synthesize or @dynamic - not because auto-synthesis is wrong, but because an accessor this
// port wrote by hand is a claim that the compiler should not second-guess silently.  PDFPage11.m does the
// same for -pageIndex, and the failure was found by the gate rather than by this port's own build, which
// does not pass that flag.
@synthesize type = _type;
@synthesize contents = _contents;
@synthesize userName = _userName;
@synthesize modificationDate = _modificationDate;
@synthesize page = _page;

// The /SUBTYPE, as the name the header's PDFAnnotationSubtype is: "Text", "Link", "Square",
// "Highlight" - the dictionary's name object without its leading slash.
//
// This was recorded here first as five large negative integers, one per subtype, and that was wrong.
// The property is a NSString* const (PDFAnnotation.h:52) and the host answers an NSTaggedPointerString,
// which packs the characters INTO the pointer; reading it as a long therefore printed a tagged value
// rather than a type, and one that is stable across runs and distinct per subtype, which is exactly
// what made it look like a constant.  Measured with .agent-work/fin/typeof, built from the probe
// recorded in the facts file.
- (NSString *)type
{
    if (_type != nil)
        return _type;
    const char *name = NULL;
    if (!CGPDFDictionaryGetName(_annotation, "Subtype", &name) || name == NULL)
        return nil;
    // The name object carries no leading slash in the C string, so nothing is stripped here.
    _type = [[NSString alloc] initWithUTF8String:name];
    return _type;
}

// The /RECT, except for a /Text annotation, which is a fixed square in the rect's top-left corner.
//
// Measured on the host, on a rect the rule was not fitted to: /Text with /Rect [10 20 500 90] answers
// {{10, 66}, {24, 24}}, so x is the rect's own minX, y is its maxY minus the size, and the size is 24.
// Every other subtype answers the rectangle it was written with: /Link [0 0 600 700] answers
// {{0, 0}, {600, 700}}, /Square [40 40 240 140] answers {{40, 40}, {200, 100}}, and /Highlight
// [0 0 200 30] answers {{0, 0}, {200, 30}}.  The rule is keyed on the subtype name and not on the /F
// flags or on the presence of an appearance stream.
//
// The size is a CONSTANT and not something derived from the rect: the two /Text fixtures have rects of
// 200x50 and 490x70 and both answer 24x24, so nothing about the rectangle produces it.  What the 24 IS
// - a note icon, a default annotation size, a minimum - was NOT measured, and this port does not claim
// it: the number is the host's answer on two rects and the facts file records the measurement.  Only
// /Text was asked, so a subtype that is neither /Text nor one of the four above is untested here and
// answers its own /Rect by the branch below.
- (CGRect)bounds
{
    if (_type == nil)
        [self type];
    CGPDFObjectRef object = NULL;
    if (!CGPDFDictionaryGetObject(_annotation, "Rect", &object) || object == NULL)
        return CGRectZero;
    // A /Rect is an ARRAY of four numbers in the format and this release has no rect object type at
    // all - CGPDFObjectType runs Null, Boolean, Integer, Real, Name, String, Array, Dictionary,
    // Stream - so it is read the way it is stored, one element at a time.
    if (CGPDFObjectGetType(object) != kCGPDFObjectTypeArray)
        return CGRectZero;
    CGPDFArrayRef array = NULL;
    if (!CGPDFObjectGetValue(object, kCGPDFObjectTypeArray, &array) || array == NULL)
        return CGRectZero;
    CGFloat number[4] = {0, 0, 0, 0};
    for (size_t i = 0; i < 4; i++) {
        CGPDFObjectRef element = NULL;
        if (!CGPDFArrayGetObject(array, i, &element) || element == NULL)
            return CGRectZero;
        // A PDF number is an integer or a real, and the format allows either for a coordinate, so both
        // are read; a coordinate written as 10 is the same coordinate as one written as 10.0.
        if (CGPDFObjectGetType(element) == kCGPDFObjectTypeInteger) {
            long integer = 0;
            if (!CGPDFObjectGetValue(element, kCGPDFObjectTypeInteger, &integer))
                return CGRectZero;
            number[i] = (CGFloat)integer;
        } else if (CGPDFObjectGetValue(element, kCGPDFObjectTypeReal, &number[i]) == false) {
            return CGRectZero;
        }
    }
    CGRect rect = CGRectMake(number[0], number[1], number[2] - number[0], number[3] - number[1]);
    if ([_type isEqualToString:@"Text"])
        return CGRectMake(CGRectGetMinX(rect), CGRectGetMaxY(rect) - kTextAnnotationSize,
                         kTextAnnotationSize, kTextAnnotationSize);
    return rect;
}

// The /CONTENTS, the annotation's own text.  Nil for an annotation that names none, which is measured
// on /Link and /Square and is a nil here because the key is absent and not because a default applies.

// The value of a key that this release holds as a PDF STRING object - /Contents, /T and /M all are.
// There is no CGPDFDictionaryGetData in this SDK and no CGPDFDataProvider to read bytes through, so the
// object is fetched and asked for its type, and a string is copied out of it.  A key that is absent,
// and a key that holds some other kind of object, both answer nil - which is the host's answer too
// for an annotation that names none.
- (NSString *)charon_stringForKey:(const char *)key
{
    if (_annotation == NULL)
        return nil;
    CGPDFObjectRef object = NULL;
    if (!CGPDFDictionaryGetObject(_annotation, key, &object) || object == NULL)
        return nil;
    CGPDFObjectType type = CGPDFObjectGetType(object);
    if (type != kCGPDFObjectTypeString)
        return nil;
    CGPDFStringRef string = NULL;
    if (!CGPDFObjectGetValue(object, kCGPDFObjectTypeString, &string) || string == NULL)
        return nil;
    CFStringRef text = CGPDFStringCopyTextString(string);
    if (text == NULL)
        return nil;
    NSString *answer = (__bridge_transfer NSString *)text;
    return answer;
}

- (NSString *)contents
{
    if (_contents != nil)
        return _contents;
    _contents = [self charon_stringForKey:"Contents"];
    return _contents;
}

// The /T, the annotation's title in the format and its author in the host's own words: measured "the
// annotator" for a /T of (the annotator), and nil for an annotation that names none.
- (NSString *)userName
{
    if (_userName != nil)
        return _userName;
    _userName = [self charon_stringForKey:"T"];
    return _userName;
}

// The /M, the annotation's modification date, in the format's own D:YYYYMMDDHHmmSS spelling.
//
// This is the ONE date form measured - a /M of D:20260930000000 answers 2026-09-30 00:00:00 +0000 -
// and a partial date (D:2026, D:202609) and the trailing Z are NOT implemented, because nothing
// measured says what the host makes of them and a guessed UTC offset would be an answer, not a
// reading.  A partial date here answers nil, and the row says so.
- (NSDate *)modificationDate
{
    if (_modificationDate != nil)
        return _modificationDate;
    NSString *date = [self charon_stringForKey:"M"];
    if (date.length < 16 || ![date hasPrefix:@"D:"])
        return nil;
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyyMMddHHmmss"];
    [formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    _modificationDate = [formatter dateFromString:[date substringFromIndex:2]];
    return _modificationDate;
}

// -shouldPrint reads /F's PRINT bit when /F is there, and answers YES when it is NOT there.  Both
// halves are measured, and the fixtures that separate them are: /F 0 answers NO, /F 2 - Hidden alone,
// Print still clear - answers NO, /F 4 answers YES, and a /Link with NO /F answers YES.  Without that
// last one the rule "mirrors the bit" and the rule "any nonzero /F" both fit the other three, and the
// port's own first version - which read a missing integer as zero - answered NO for a /Link the host
// prints.  The differential named the two fixtures and the default is in the code because of it.
//
// -shouldDisplay is NOT the companion of that bit and is not implemented: /F 2 answers YES for it, so
// the format's Hidden bit is not what it reads, and it answered YES for every /F measured here (0, 2,
// 4) across nine fixtures.  What turns it off is not identified, and a constant YES would be a
// hard-coded answer that one more fixture could break.  The row names this boundary.
- (BOOL)shouldPrint
{
    if (_annotation == NULL)
        return NO;
    // An ABSENT /F answers YES, and the differential is what found that: the /Link fixtures write no
    // /F at all and the host answers shouldPrint=1 for them, so reading a missing integer as 0 and
    // testing its Print bit would answer NO where the host answers YES.  It is the same default
    // pattern as /C and /Border - a missing key is not always nil - so the key's PRESENCE is the
    // first question and its value the second.
    long flags = 0;
    if (!CGPDFDictionaryGetInteger(_annotation, "F", &flags))
        return YES;
    return (flags & 4) != 0;
}

// The PAGE the annotation was found on, which the host answers as an object for all nine fixtures.
// It is passed in rather than read from /P: the dictionary's /P is an indirect reference into the same
// document, and resolving it to a PDFPage would mean a page lookup by object number, which the port's
// page objects do not index by.  The answer is the page this annotation was created from, which is the
// same object the host hands back for a document that is still alive, and nil once that document has
// gone, which is what the weak reference is for.
- (PDFPage *)page
{
    return _page;
}

// Members that are measured and NOT implemented here, each with the boundary that keeps it out.  They
// are listed so the omission is a decision on the record and not an oversight, and their rows carry
// the same reasons.
//
//   -color             reads /C when written (measured: 1 0 0 -> "Device RGB colorspace 1 0 0 1"), but
//                      the ABSENT answer is subtype-dependent: /Highlight answers a default sRGB
//                      yellow (0.980392 0.803922 0.352941 1) where /Link and /Square answer nil.  A
//                      plain read of /C would answer nil for a highlight the host paints.
//   -border            the host answers a DEFAULT border for a /Square with no /Border (solid, 1.0)
//                      and nil for a /Link with none, so the absent answer is subtype-dependent here
//                      too, and PDFBorder is a class of its own with four more rows of its own.
//   -shouldDisplay     measured YES for /F 0, 2 and 4, and not the Hidden bit; see above.
//   -hasAppearanceStream, -isHighlighted  measured NO on all nine fixtures and nothing in the writer
//                      sets an /AP or a /H, so NO is the only answer measured and the keys that
//                      change it are not.
//   -popup, -action    PDFAnnotationPopup and PDFAction are classes of their own; nothing measured.
//   -annotationKeyValues and the five -setValue:/-valueForAnnotationKey: members  the annotation-key
//                      API is its own family, and -setValue: is a WRITE path this port does not have.
//   -drawWithBox:inContext:  draws, and a windowless host answers nothing to compare against.
//   -initWithBounds:forType:withProperties:, -initWithDictionary:forPage:, -initWithBounds:  write a
//                      new annotation into a document; the port reads annotations, and a constructor
//                      that cannot be read back would be untestable.
//   -toolTip, -mouseUpAction, -removeAllAppearanceStreams, -drawWithBox:  deprecated members of the
//                      same unwritten or undrawn surface.

@end
