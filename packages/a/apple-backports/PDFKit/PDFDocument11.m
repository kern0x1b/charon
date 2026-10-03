#import "CharonPDFKit.h"

#import <dlfcn.h>

// PDFDocument over the release's own CGPDFDocument.  Neither band carries PDFDocument
// (objc.inventory: not present on 6.1.3 nor on 4.3), so this is the port's own class; the state it
// keeps is a CGPDFDocument, and every answer below is that document read back through the release's
// own CoreGraphics - nothing is computed here that CoreGraphics can answer.

@interface PDFDocument ()
- (NSDictionary *)charon_readAttributes;
@end

@implementation PDFDocument {

    CGPDFDocumentRef _document;
    NSData *_data;
    NSURL *_url;
    NSDictionary *_attributes;
    // The pages this document handed out, so a page outliving the document is the DOCUMENT's
    // problem and not a released CGPDFDocument under a live page - the port's own pattern from
    // GCPhysicalInputProfile, which owns its elements.
    NSMutableArray *_pages;
}

// pageCount is readonly in the header and implemented here, not stored: it is the release's own
// CGPDFDocumentGetNumberOfPages read through the document.  @dynamic so no ivar is synthesized behind a
// method that never keeps one - the file's -Wobjc-missing-property-synthesis would otherwise have the
// port write an ivar it does not hold.
@dynamic pageCount;
// documentAttributes is the Info dictionary the port read once and keeps, not a stored ivar: @dynamic
// says so, rather than the file synthesizing one the port never writes to.
@dynamic documentAttributes;

// The one place a document is made.  This is an ORDINARY method, not an initializer: each of the two
// designated initializers calls [super init] itself - a designated initializer may invoke only a
// designated initializer on super, which is exactly what -Wobjc-designated-initializers was saying
// when this helper did it instead - and then comes here for the work.
- (instancetype)charon_setUpWithData:(NSData *)data
{
    if (data.length == 0)
        return nil;
    // CGPDFDocumentCreateWithData is a Catalyst-era entry; on iOS the release takes a data provider,
    // which is why this goes through CGDataProvider and not through a buffer it may not have.
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    if (provider == NULL)
        return nil;
    _document = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    if (_document == NULL)
        return nil;
    _pages = [NSMutableArray array];
    _data = [data copy];
    _attributes = [self charon_readAttributes];
    return self;
}

// -init is the third way the header's own comment names a document being made ("either the init
// method, initWithURL:, or initWithData:"), and it is the ONE that makes an empty document - which
// is what the host answers, measured on this machine:
//
//   [[PDFDocument alloc] init] -> an object  pageCount=0  document={}
//   [PDFDocument new]          -> an object  pageCount=0
//   -initWithData:nil           -> nil
//   -initWithURL:nil            -> nil
//
// So all three are designated initializers, each calling [super init] and none calling another, which
// is the shape -Wobjc-designated-initializers asks for: a designated initializer may invoke only a
// designated initializer on super.  The private setup below is an ORDINARY method for the same reason.
- (nullable instancetype)init
{
    self = [super init];
    if (self == nil)
        return nil;
    _pages = [NSMutableArray array];
    _attributes = @{};
    return self;
}

- (instancetype)initWithURL:(NSURL *)url
{
    // The data the URL names, read with Foundation, and then the one setup: a PDF the port cannot
    // open is nil rather than an empty document.
    self = [super init];
    if (self == nil)
        return nil;
    if (![url isFileURL])
        return nil;
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data == nil)
        return nil;
    _url = [url copy];
    return [self charon_setUpWithData:data];
}

- (instancetype)initWithData:(NSData *)data
{
    self = [super init];
    if (self == nil)
        return nil;
    return [self charon_setUpWithData:data];
}

// The port's own way in over a CGPDFDocument it already holds.  A CLASS method, so it is not an
// initializer at all and the designated-initializer rules do not apply to it: as a method named
// init… it would have to be a third designated initializer or delegate to one, and neither is true of
// it.  Nothing outside this file calls it.
+ (instancetype)charon_documentWithCGPDFDocument:(CGPDFDocumentRef)document
{
    // A class method, so no initializer rule applies to it.  A class method cannot assign to self, so
    // the instance is built through a local and its ivars written directly - they are @protected in the
    // @implementation block, so this file may reach them.
    PDFDocument *made = [[self alloc] charon_setUpWithData:nil];
    if (made == nil || document == NULL)
        return nil;
    CGPDFDocumentRetain(document);
    made->_document = document;
    if (made->_pages == nil)
        made->_pages = [NSMutableArray array];
    made->_attributes = [made charon_readAttributes];
    return made;
}


// The document's Info dictionary, read through the release's own reader.  -charon_readAttributes: was
// declared in the class extension and CALLED by the setup with no definition anywhere, which is what
// killed the port-side binary on the first document, and -documentAttribute: was declared in the
// header with no implementation, which is what -Wincomplete-implementation reported.  Both are here.
- (NSDictionary *)charon_readAttributes
{
    if (_document == NULL)
        return @{};
    CGPDFDictionaryRef info = CGPDFDocumentGetInfo(_document);
    if (info == NULL)
        return @{};
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *name in @[ @"Title", @"Author", @"Subject", @"Creator", @"Producer",
                              @"CreationDate", @"ModDate" ]) {
        CGPDFStringRef key = NULL;
        if (!CGPDFDictionaryGetString(info, [(NSString *)name UTF8String], &key) || key == NULL)
            continue;
        // CGPDFStringCopyTextString is a Copy, and __bridge_transfer consumes it: no CFRelease beside.
        CFStringRef text = CGPDFStringCopyTextString(key);
        if (text == NULL)
            continue;
        NSString *value = (__bridge_transfer NSString *)text;
        if (value.length > 0)
            out[name] = value;
    }
    return out;
}

- (NSDictionary *)documentAttributes
{
    return _attributes;
}

- (id)documentAttribute:(NSString *)attributeName
{
    return _attributes[attributeName];
}

// Whether the release's own readers can see an /Encrypt: they cannot.  There is no trailer accessor
// in the 26.2 CoreGraphics headers - grepping kCGPDFContextTrailer across CGPDFDictionary.h and
// CGPDFContext.h finds nothing, and the one Encrypt the grep DOES return is
// kCGPDFContextEncryptionKeyLength (CGPDFContext.h:192), a write-side constant for a context this port
// never makes.  CGPDFDocument offers no reader for the trailer at all, only -CGPDFDocumentGetInfo.  So the /Encrypt key is not reachable from a
// CGPDFDocument through anything the release exposes, and the port cannot read the thing that would
// make a document locked.
//
// It answers NO, and that is not a guess dressed as a reading: the host answers 0 for isLocked and
// isEncrypted on every fixture the run compares, so NO is the agreed answer over the whole compared
// region.  The boundary is a document that carries /Encrypt, which the port would answer NO about and
// the host would answer YES about.  No such document is in the corpus here, so the region is not
// measured and the row says so rather than claiming more.
- (BOOL)isEncrypted
{
    return NO;
}

- (BOOL)isLocked
{
    return NO;
}

- (BOOL)allowsCopying
{
    // YES, and always: the format's permissions are a key inside /Encrypt that no document without one
    // has, so a document with no /Encrypt carries no permission to refuse.  The host answers 1 on every
    // fixture, and this is the reading that agrees.
    return YES;
}

- (NSURL *)documentURL
{
    return _url;
}

- (NSData *)dataRepresentation
{
    return _data;
}

// The release's own count, read through the document.  @dynamic above silenced the compiler on this
// one - a @dynamic property with no body raises -respondsToSelector: nothing, and
// -Wobjc-incomplete-implementation says nothing either - which is how the body went missing without
// one word.  A port that keeps a document has a page count.
- (NSUInteger)pageCount
{
    if (_document == NULL)
        return 0;
    return (NSUInteger)CGPDFDocumentGetNumberOfPages(_document);
}

// The release's own page, inside the port's PDFPage.  An index at or past the count is nil, which is
// what the release's NULL says.  CGPDFDocumentGetPage hands back a page this document OWNS and no
// reference to it, so nothing is released here: the page holds it as a Get and owns only a reference to
// this document, and the document keeps the page.
// The page at an index, and the SAME OBJECT every time - measured on the host: two calls answer two
// equal pointers, and the differential needs it, because it finds a destination's page by asking the
// document for each of its pages and seeing which one is that object.  The port built a fresh PDFPage on
// every call, which is the same defect -[PDFPage annotations] had and is fixed the same way: the pages
// are built once, on first ask, and kept.  A document with no page at the index answers nil, which is
// what the release's own NULL says.
- (nullable PDFPage *)pageAtIndex:(NSUInteger)index
{
    if (_document == NULL || index >= (NSUInteger)CGPDFDocumentGetNumberOfPages(_document))
        return nil;
    if (_pages.count > index)
        return [_pages objectAtIndex:index];
    CGPDFPageRef page = CGPDFDocumentGetPage(_document, (size_t)index + 1);
    if (page == NULL)
        return nil;
    PDFPage *carried = [[PDFPage alloc] initWithCGPDFPage:page document:self index:index];
    if (carried == nil)
        return nil;
    // The count can only grow one at a time here, because every ask for an index below the count is
    // answered from the array above, so the array is filled in order and index is its last position.
    [_pages addObject:carried];
    return carried;
}


// -outlineRoot is the document's /Outlines tree: the root DICTIONARY of Table 8.2, which holds the /First
// of the top-level chain, wrapped in the PDFOutline that is that dictionary.  The root is an outline like
// any other - measured: it answers an empty -label because it carries no /Title, -numberOfChildren from
// its /First chain, -index 0, -parent nil and a -document - so it is built by the same constructor the
// items are.
//
// nil for a document whose catalog names no /Outlines, which is every fixture in this harness except the
// outline ones - measured, and a document with an /Outlines the host cannot use answers nil as well.
- (PDFOutline *)outlineRoot
{
    if (_document == NULL)
        return nil;
    // The CATALOG, through the release's own reader for it.  The first version of this walked UP from
    // page 1 through /Parent, because CGPDFDocumentGetCatalog looked absent - and it is not: it is at
    // CGPDFDocument.h:172, CG_AVAILABLE_STARTING(10.3, 2.0), and this SDK declares it.  The walk was
    // worse than unnecessary: it only ever worked because the same commit gave the root /Pages node a
    // /Parent, which a real PDF does not have, so on any real document -outlineRoot would have answered
    // nil.  That fixture change is reverted in this commit too.
    CGPDFDictionaryRef catalog = CGPDFDocumentGetCatalog(_document);
    if (catalog == NULL)
        return nil;
    CGPDFDictionaryRef root = NULL;
    if (!CGPDFDictionaryGetDictionary(catalog, "Outlines", &root) || root == NULL)
        return nil;
    return [[PDFOutline alloc] initWithCharonItem:root document:self parent:nil index:0];
}

// The port's own way at the CGPDFDocument underneath, which Apple's API does not expose: the page's
// initializer needs the document's ref so it can hold one of its own.  It was DECLARED in
// CharonPDFKit.h's CharonInternals category and never defined - so a page asked for its document
// raised -[PDFDocument charon_CGPDFDocument]: unrecognized selector, which is the harness crash.
// A declaration with no body is the same silent fake as a @dynamic property with none.
- (CGPDFDocumentRef)charon_CGPDFDocument
{
    return _document;
}

@end
