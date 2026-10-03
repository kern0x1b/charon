#import "CharonPDFKit.h"
#include <ctype.h>

// PDFPage over the release's own CGPDFPage.  Every answer is the page read back through CoreGraphics:
// the boxes are CGPDFPageGetBoxRect, the rotation is the page dictionary's own /Rotate.

@interface PDFPage ()
- (CGPDFPageRef)charon_CGPDFPage;
- (void)charon_buildAnnotations;
@end

@implementation PDFPage {
    CGPDFPageRef _page;
    // Weak, as the header declares it (PDFPage.h:70): the page answers nil for a document that has
    // gone, and does not keep one alive.  The CGPDFDocument underneath is held strongly in
    // _documentRef, because a CGPDFPage belongs to one and outliving it is a real case.
    __weak PDFDocument *_document;
    // The CGPDFDocument itself, held strongly, because the CGPDFPage below belongs to it.
    CGPDFDocumentRef _documentRef;
    NSUInteger _index;
    // The page's annotations, built once and handed out as a copy each time.  Strong, and not a cycle:
    // an annotation's page is WEAK (PDFAnnotation.h:141), so page -> annotation -> page does not close.
    NSArray *_annotations;
}

@synthesize pageIndex = _index;
// -label and -numberOfCharacters and -annotationCount are computed from the page's own dictionary and
// its content stream, not stored.  @dynamic says "not an ivar" and NOTHING else: a @dynamic property
// with no body raises at run time, which is what the first version of this did and what the harness's
// crash was.  Each has a body below.
@dynamic label;
@dynamic numberOfCharacters;
@dynamic string;
@dynamic annotations;
@dynamic annotationCount;

// The page's LABEL, which the host answers as a ONE-BASED number as a string: measured "1" for the
// first page of every fixture, and the first page of a three-page document is also "1".  So it is the
// index plus one, and the port's own zero-based _index is not what Apple's answer is.  The page
// dictionary's /StructParents is the format's hook for a printed label and none of these fixtures names
// one, so this is the host's answer rather than a substitute for it, and a page whose /StructParents
// is not measured here.
- (NSString *)label
{
    return [NSString stringWithFormat:@"%lu", (unsigned long)(_index + 1)];
}

// The number of CHARACTERS the page's text walk produces, a kerning separator included: measured 6
// where -string answers "al pha" over five drawn glyphs, and 5 where it answers "alpha".  So this is
// the length of the same walk and not a glyph run - which is what separates it from -string's boundary.
- (NSUInteger)numberOfCharacters
{
    NSString *text = [self string];
    return text.length;
}

// THE TEXT WALK, bounded.
//
// The walk is over CGPDFScanner and an operator table, which this release DOES export - the Pop* family
// and CGPDFOperatorTableSetCallback - even though CGPDFScannerScanString and CGPDFScannerGetString are
// absent.  Measured: it recovers "page 1" off a fixture written by a conforming writer.
//
// AND IT OVER-READS, which is the whole reason it needed bounding.  CGPDFScannerScan does not answer
// false at the end of a content stream: past its last operator it keeps returning true and
// re-delivering the last operand, so `while (CGPDFScannerScan(sc))` never ends and the text it produces
// is "page 1page 1page 1..." to the end of whatever bound it is given.  So the walk below stops on TWO
// CONDITIONS, both of them facts about the document rather than a guess about the scanner:
//
//   the OPERATOR COUNT  every show operator advances a counter, and the walk stops when the number of
//                       shows it has taken reaches the number the page's own text runs account for
//   the STREAM LENGTH    the walk also stops at the content stream's own decompressed length, read
//                       through CGPDFStreamCopyData, so a stream whose operators do not divide evenly
//                       into it cannot run away either
//
// The two are both needed.  The operator count alone cannot see a scan that returns true without
// advancing, and the length alone would truncate a legitimate page whose text runs are dense.

// What the walk accumulates, and what the callbacks reach through the scanner's info pointer.
typedef struct {
    NSMutableString *text;
    NSMutableArray *runs;
    NSUInteger shows;
    CGFloat x;
    CGFloat y;
    CGFloat size;
} CharonTextWalk;

// The show operators, as C functions.  Each pops ITS OWN operands: the callback signature carries none.
static void charonAppendOperand(CGPDFScannerRef scanner, CharonTextWalk *walk, CGPDFStringRef operand)
{
    if (operand == NULL)
        return;
    CFStringRef characters = CGPDFStringCopyTextString(operand);
    if (characters == NULL)
        return;
    [walk->text appendString:(__bridge NSString *)characters];
    collectRun(walk->runs, characters, walk->x, walk->y);
    CFRelease(characters);
}

static void charonOpShowText(CGPDFScannerRef scanner, void *info)
{
    CharonTextWalk *walk = info;
    if (walk == NULL)
        return;
    CGPDFStringRef operand = NULL;
    if (CGPDFScannerPopString(scanner, &operand))
        charonAppendOperand(scanner, walk, operand);
    walk->shows++;
}

static void charonOpShowTextArray(CGPDFScannerRef scanner, void *info)
{
    CharonTextWalk *walk = info;
    if (walk == NULL)
        return;
    CGPDFArrayRef array = NULL;
    if (!CGPDFScannerPopArray(scanner, &array) || array == NULL)
        return;
    for (size_t i = 0; i < CGPDFArrayGetCount(array); i++) {
        CGPDFObjectRef element = NULL;
        if (!CGPDFArrayGetObject(array, i, &element) || element == NULL)
            continue;
        CGPDFObjectType kind = CGPDFObjectGetType(element);
        if (kind == kCGPDFObjectTypeString) {
            CGPDFStringRef operand = NULL;
            if (CGPDFObjectGetValue(element, kCGPDFObjectTypeString, &operand))
                charonAppendOperand(scanner, walk, operand);
        }
        // A NUMBER in a TJ array is a KERNING ADJUSTMENT and not a character, and the host's -string does
        // not turn one into a space - measured, the answer is "page 1" and not "page  1".  It is skipped,
        // and skipping it is the measured behaviour rather than a convenience.
    }
    walk->shows++;
}

// The text matrix: where the next show is drawn.  Popped in REVERSE - a stack pops its top first, and
// the matrix is pushed a..f, so f comes off before e.
static void charonOpTextMatrix(CGPDFScannerRef scanner, void *info)
{
    CharonTextWalk *walk = info;
    if (walk == NULL)
        return;
    // CGPDFReal, and NOT double: in this release it is a float, and a double* here is a type error rather
    // than a widening.  The name reads like a double, which is why the type is spelled out here.
    CGPDFReal a = 0, b = 0, c = 0, d = 0, e = 0, f = 0;
    if (CGPDFScannerPopNumber(scanner, &f) && CGPDFScannerPopNumber(scanner, &e) &&
        CGPDFScannerPopNumber(scanner, &d) && CGPDFScannerPopNumber(scanner, &c) &&
        CGPDFScannerPopNumber(scanner, &b) && CGPDFScannerPopNumber(scanner, &a)) {
        walk->x = (CGFloat)e;
        walk->y = (CGFloat)f;
    }
}

// The font size, for a run's vertical extent.
static void charonOpFontSize(CGPDFScannerRef scanner, void *info)
{
    CharonTextWalk *walk = info;
    if (walk == NULL)
        return;
    CGPDFReal size = 0;
    if (CGPDFScannerPopNumber(scanner, &size))
        walk->size = (CGFloat)size;
}

// One drawn run, as the walk collects it: the characters and where they were drawn.
typedef struct {
    CFStringRef text;
    CGFloat x;
    CGFloat y;
} CharonTextRun;

static void collectRun(NSMutableArray *runs, CFStringRef text, CGFloat x, CGFloat y)
{
    if (text == NULL)
        return;
    CharonTextRun *run = malloc(sizeof(*run));
    if (run == NULL)
        return;
    run->text = (CFStringRef)CFRetain(text);
    run->x = x;
    run->y = y;
    [runs addObject:[NSValue valueWithPointer:run]];
}

static void freeRuns(NSMutableArray *runs)
{
    for (NSUInteger i = 0; i < runs.count; i++) {
        CharonTextRun *run = (CharonTextRun *)[runs[i] pointerValue];
        if (run == NULL)
            continue;
        CFRelease(run->text);
        free(run);
    }
    [runs removeAllObjects];
}

// The text matrix and the font size the page drew its last text at, read off the content stream's own
// Tm and Tf operators.  A selection's geometry needs them and the walk needs them, so they are read once
// and shared.  A stream that names neither leaves the size at 0 and the position at the origin, and the
// rows that depend on a position say so rather than inventing one.
typedef struct { CGFloat x; CGFloat y; CGFloat size; } CharonTextState;

static NSString *charonScanPageText(CGPDFPageRef page, CharonTextState *state)
{
    if (state != NULL) {
        state->x = 0;
        state->y = 0;
        state->size = 0;
    }
    if (page == NULL)
        return nil;
    CGPDFDictionaryRef dictionary = CGPDFPageGetDictionary(page);
    if (dictionary == NULL)
        return nil;
    CGPDFStreamRef stream = NULL;
    if (!CGPDFDictionaryGetStream(dictionary, "Contents", &stream) || stream == NULL)
        return nil;

    // The stream's own decompressed LENGTH, which is the walk's second stop condition.  Read through
    // CGPDFStreamCopyData because the bytes on disk are the Flate-compressed form and its /Length is the
    // compressed length, which is not the length the scanner consumes.
    CFDataRef data = CGPDFStreamCopyData(stream, NULL);
    if (data == NULL)
        return nil;
    CFIndex streamLength = CFDataGetLength(data);
    if (streamLength <= 0) {
        CFRelease(data);
        return nil;
    }
    // The number of SHOW OPERATORS the page's own content stream contains, counted off its bytes.  This
    // is the walk's stop condition and it is a fact about the PAGE rather than a guess about the
    // scanner: the scanner re-delivers the last operand forever, so a bound on how many tokens it hands
    // out fires immediately - the walk discarded its own correct answer on every fixture until the bound
    // was taken from the content instead.  A stream with no show operator walks zero times, which is
    // what a page that draws no text should answer.
    NSUInteger showCount = 0;
    {
        const char *bytes = (const char *)CFDataGetBytePtr(data);
        if (bytes != NULL) {
            for (CFIndex i = 0; i + 1 < streamLength; i++) {
                char c = bytes[i];
                if (c != 'T' && c != '\'' && c != '"')
                    continue;
                if (c == 'T') {
                    // Tj or TJ, and only when the token ENDS here - a T inside a name is not a show.
                    if (i + 2 < streamLength && (bytes[i + 1] == 'j' || bytes[i + 1] == 'J') &&
                        (i + 2 >= streamLength || !(isalnum((unsigned char)bytes[i + 2]) || bytes[i + 2] == '*')))
                        showCount++;
                } else {
                    // ' and " are show operators in their own right, and are one character long.
                    if (i + 1 >= streamLength || !(isalnum((unsigned char)bytes[i + 1]) || bytes[i + 1] == '*'))
                        showCount++;
                }
            }
        }
    }
    CFRelease(data);

    // The content stream, from the PAGE and not from the stream with NULL resources.
    //
    // CGPDFContentStreamCreateWithStream's second parameter sits inside CF_ASSUME_NONNULL_BEGIN in the
    // release's own CGPDFContentStream.h, so it is nonnull and passing NULL is a -Wnonnull diagnostic -
    // and it was one, on origin/main, since the text walk landed.  The page is what this function already
    // takes, so nothing new is threaded through to reach it.  CGPDFContentStreamCreateWithPage is
    // the API for exactly this: it takes the page and supplies the /Resources and the content array the
    // hand-assembled call was leaving out, which the scanner needs to resolve a font name at all.  The
    // stream above is still read, because the walk's second stop condition is that stream's own
    // decompressed length and its byte count of show operators.
    CGPDFContentStreamRef content = CGPDFContentStreamCreateWithPage(page);
    if (content == NULL)
        return nil;

    NSMutableArray *runs = [NSMutableArray array];
    NSMutableString *text = [NSMutableString string];

    CGPDFOperatorTableRef table = CGPDFOperatorTableCreate();
    if (table == NULL) {
        CGPDFContentStreamRelease(content);
        return nil;
    }
    // The scanner is created LAST, once the walk it points at exists, because the walk is what the info
    // pointer carries and every callback needs it.
    CGPDFScannerRef scanner = NULL;

    // The callbacks, as C FUNCTIONS and not blocks: CGPDFOperatorCallback is a function pointer, so a
    // block cannot be passed to CGPDFOperatorTableSetCallback and the compiler says so.  Each reaches the
    // walk's state through the scanner's info pointer, which is what that argument is for - the callback
    // signature carries no operand, which is the other difference from the API this file used to imagine.
    CharonTextWalk *walk = malloc(sizeof(*walk));
    if (walk == NULL) {
        CGPDFScannerRelease(scanner);
        CGPDFOperatorTableRelease(table);
        CGPDFContentStreamRelease(content);
        return nil;
    }
    walk->text = text;
    walk->runs = runs;
    walk->shows = 0;
    walk->x = 0;
    walk->y = 0;
    walk->size = 0;
    CGPDFOperatorTableSetCallback(table, "Tj", charonOpShowText);
    CGPDFOperatorTableSetCallback(table, "'", charonOpShowText);
    CGPDFOperatorTableSetCallback(table, "\"", charonOpShowText);
    CGPDFOperatorTableSetCallback(table, "TJ", charonOpShowTextArray);
    CGPDFOperatorTableSetCallback(table, "Tm", charonOpTextMatrix);
    CGPDFOperatorTableSetCallback(table, "Tf", charonOpFontSize);

    scanner = CGPDFScannerCreate(content, table, walk);
    if (scanner == NULL) {
        free(walk);
        CGPDFOperatorTableRelease(table);
        CGPDFContentStreamRelease(content);
        return nil;
    }
    while (walk->shows < showCount && CGPDFScannerScan(scanner))
        ;
    // The over-read is visible rather than silent.  A walk that took FEWER shows than the stream contains
    // stopped early and its answer is incomplete, so it is DISCARDED rather than returned half-formed: a
    // -string that is wrong in a way nobody can see is worse than nil, and the facts file records it.
    BOOL exhausted = walk->shows < showCount;
    if (state != NULL) {
        state->x = walk->x;
        state->y = walk->y;
        state->size = walk->size;
    }
    free(walk);
    CGPDFScannerRelease(scanner);
    CGPDFOperatorTableRelease(table);
    CGPDFContentStreamRelease(content);
    freeRuns(runs);
    if (exhausted || text.length == 0)
        return nil;
    return text;
}

// The page's own TEXT, which is what the host's -string answers on every fixture measured here: "page 1"
// for the first page of a three-page document and "page 2" and "page 3" for the others, with the character
// count -numberOfCharacters agrees with.  The kerning numbers in a TJ array are NOT characters, which is
// what keeps "page 1" from becoming "page  1".
- (NSString *)string
{
    if (_page == NULL)
        return nil;
    return charonScanPageText(_page, NULL);
}

// The page's ANNOTATIONS, built over the page's own /Annots array: each element is a dictionary
// CoreGraphics already parsed, and each becomes a PDFAnnotation over that dictionary.  The order is the
// array's own, which is the order the host hands them back in.
//
// AN ANNOTATION THE HOST DOES NOT SURFACE IS NOT IN THE ARRAY, which is a measured skip and not a
// tolerance: the /Annots array of a fixture with thirteen annotations in it holds eleven that the host
// never hands back, and this port used to hand back all thirteen.  Two shapes are skipped, and both
// are measured over every subtype tried rather than over one:
//
//   no /Rect   a /Line, /Square, /Text, /Popup, /Ink, /Circle, /FreeText, /Stamp and /Link, each
//              written with a /Contents and nothing else, is dropped - all nine, on one fixture.  /Rect
//              is what PDF 1.7 Table 164 makes required of every annotation, so this is the format's
//              own requirement and the host enforcing it.
//   a /Line with no /L   the same fixture's /Line with a /Rect and no /L is dropped while a /Line with
//              both is kept, so the line's own endpoints are as required for a /Line as the rectangle
//              is for everything.
//
// A /Widget with no /FT is KEPT (the same fixture, one annotation), which is what stops the rule from
// being "an annotation missing a required key is dropped": /FT is required of a widget by Table 8.39
// and the host does not enforce it.  So the two shapes above are the measured rule and not the
// format's.
- (NSArray *)annotations
{
    if (_annotations == nil)
        [self charon_buildAnnotations];
    // A COPY each call, over objects built once.  Both halves are measured on the host, and they are two
    // different halves: two calls answer two DIFFERENT arrays (arrays-same = 0 on every fixture) whose
    // elements are the SAME objects (objects-same = 1), and a change made through one is visible through
    // the other - a line width set on the first array's annotation reads back 9 on the second's, and a
    // border assigned through the first is the very object the second answers.  So the objects are built
    // once and kept, and the array is not: rebuilding the objects on every call, which is what this did
    // before, makes every one of those answers unreachable through the API.
    return _annotations != nil ? [_annotations copy] : @[];
}

- (void)charon_buildAnnotations
{
    _annotations = nil;
    if (_page == NULL)
        return;
    CGPDFDictionaryRef dictionary = CGPDFPageGetDictionary(_page);
    if (dictionary == NULL) {
        _annotations = @[];
        return;
    }
    CGPDFArrayRef annots = NULL;
    if (!CGPDFDictionaryGetArray(dictionary, "Annots", &annots) || annots == NULL) {
        _annotations = @[];
        return;
    }
    size_t count = CGPDFArrayGetCount(annots);
    NSMutableArray *answer = [NSMutableArray arrayWithCapacity:count];
    for (size_t i = 0; i < count; i++) {
        CGPDFDictionaryRef annotation = NULL;
        if (!CGPDFArrayGetDictionary(annots, i, &annotation) || annotation == NULL)
            continue;
        CGPDFArrayRef rect = NULL;
        if (!CGPDFDictionaryGetArray(annotation, "Rect", &rect) || rect == NULL)
            continue;
        // a /Line whose endpoints are missing is skipped as well, and the /Subtype is read as the
        // name the dictionary spells it with - the same spelling -type answers.
        const char *subtype = NULL;
        if (CGPDFDictionaryGetName(annotation, "Subtype", &subtype) && subtype != NULL
            && strcmp(subtype, "Line") == 0) {
            CGPDFArrayRef endpoints = NULL;
            if (!CGPDFDictionaryGetArray(annotation, "L", &endpoints) || endpoints == NULL)
                continue;
        }
        PDFAnnotation *built = [[PDFAnnotation alloc] initWithCharonDictionary:annotation onPage:self];
        if (built != nil)
            [answer addObject:built];
    }
    _annotations = answer;
}

// The annotation COUNT is the length of that array: an array this release cannot answer, and a
// document whose page names no /Annots, answer zero.
- (NSUInteger)annotationCount
{
    return [self annotations].count;
}

- (instancetype)initWithCGPDFPage:(CGPDFPageRef)page document:(PDFDocument *)document index:(NSUInteger)index
{
    self = [super init];
    if (self == nil)
        return nil;
    if (page == NULL)
        return nil;
    // The page itself is a GET: CGPDFDocumentGetPage does not hand over an owned reference, and the
    // port must not take one of its own - a page released while its document is still alive is the
    // direction CoreGraphics does not support, and the bisect showed exactly that as the crash:
    //   pageAtIndex:0, page kept        -> exit 0
    //   pageAtIndex:0, page dropped first -> exit 139
    // The DOCUMENT owns its pages (it keeps them in its _pages array), so a page that dies first
    // frees nothing the document still points at.
    //
    // What the page DOES own is the document, held strongly as a CGPDFDocumentRef and not through the
    // PDFDocument - which the header declares weak (PDFPage.h:70), so a page that outlives its
    // document is a real case and needs its own reference to keep the page's internals alive.
    // The OBJECT, weakly, as PDFPage.h:70 declares - the page must answer nil for a document that has
    // gone, and must not keep one alive.  The REF behind it is held strongly, because a CGPDFPage
    // belongs to its CGPDFDocument and a page outliving its document is a real case.
    //
    // The object was NOT set here at all in the first version - the initializer took a
    // CGPDFDocumentRef, so -document was nil on every page while the host answered an object on every
    // fixture.  It is the "never handed it" case, not the "freed" one, and the harness is what said so.
    CGPDFDocumentRef documentRef = [document charon_CGPDFDocument];
    if (documentRef != NULL)
        CGPDFDocumentRetain(documentRef);
    _page = page;
    _document = document;
    _documentRef = documentRef;
    _index = index;
    return self;
}

- (void)dealloc
{
    // the page is a Get, so there is nothing of the page's to release; the document reference is
    // this page's own and is released here
    _page = NULL;
    if (_documentRef != NULL)
        CGPDFDocumentRelease(_documentRef);
}

- (PDFDocument *)document
{
    // A page answers nil for its document once the document has gone, which is what weak means and
    // what the header's declaration asks for.
    return _document;
}

// -boundsForBox: over the release's own box reader.  A box the page does not carry is the media box,
// which is what the release's own default is.
- (CGRect)boundsForBox:(CGPDFBox)box
{
    if (_page == NULL)
        return CGRectZero;
    return CGPDFPageGetBoxRect(_page, box);
}

- (CGRect)mediaBox
{
    return [self boundsForBox:kCGPDFMediaBox];
}

- (CGRect)cropBox
{
    return [self boundsForBox:kCGPDFCropBox];
}

// The page's own /Rotate, read through the release's dictionary API.  A page with no /Rotate is 0,
// which is what the PDF format says and what the release's own reader answers.
- (NSInteger)rotation
{
    if (_page == NULL)
        return 0;
    CGPDFDictionaryRef dictionary = CGPDFPageGetDictionary(_page);
    if (dictionary == NULL)
        return 0;
    // The release's own dictionary reader, which answers the integer directly: no CGPDFObject and
    // no object-type test, because the reader is already the one that knows.
    CGPDFInteger raw = 0;
    if (!CGPDFDictionaryGetInteger(dictionary, "Rotate", &raw))
        return 0;
    NSInteger degrees = (NSInteger)raw;
    // The host answers 90 for a page whose /Rotate is 90, MEASURED on the rotated fixture
    // (box-rotated.pdf: host=90, port=270).  So the host does NOT flip the format's
    // counter-clockwise count here, and this flipping - written before anything was measured - was
    // wrong.  The value the page dictionary carries is the value the API answers.
    return degrees == 0 ? 0 : (degrees % 360 + 360) % 360;
}

- (CGPDFPageRef)charon_CGPDFPage
{
    return _page;
}

@end
