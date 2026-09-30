#import "CharonPDFKit.h"

// PDFPage over the release's own CGPDFPage.  Every answer is the page read back through CoreGraphics:
// the boxes are CGPDFPageGetBoxRect, the rotation is the page dictionary's own /Rotate.

@interface PDFPage ()
- (CGPDFPageRef)charon_CGPDFPage;
@end

@implementation PDFPage {
    CGPDFPageRef _page;
    // Weak, as the header declares it: the document owns the CGPDFDocument this page's page came
    // from, and a strong reference here would be a use-after-free once the document goes.
    // Weak, as the header declares it (PDFPage.h:70) - the page answers nil for a document that has
    // gone, and does not keep one alive.
    __weak PDFDocument *_document;
    // The CGPDFDocument itself, held strongly, because the CGPDFPage below belongs to it.
    CGPDFDocumentRef _documentRef;
    NSUInteger _index;
    NSString *_string;
}

@synthesize pageIndex = _index;

- (instancetype)initWithCGPDFPage:(CGPDFPageRef)page document:(CGPDFDocumentRef)documentRef index:(NSUInteger)index
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
    if (documentRef != NULL)
        CGPDFDocumentRetain(documentRef);
    _page = page;
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
    // The format counts counter-clockwise and Apple's API counts clockwise.
    return degrees == 0 ? 0 : (360 - (degrees % 360)) % 360;
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
