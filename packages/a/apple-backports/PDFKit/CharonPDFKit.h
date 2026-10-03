#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// The port's PDFKit: PDFDocument and PDFPage over the RELEASE's own CGPDFDocument, which 6.1.3 and
// 4.3 both export (measured with the dyld export tables: CGPDFDocumentCreateWithURL,
// CGPDFDocumentGetNumberOfPages, CGPDFDocumentGetPage, CGPDFDocumentRelease, CGPDFPageGetBoxRect,
// CGPDFPageGetDictionary).  Neither release carries the PDFKit classes themselves - objc.inventory,
// an Objective-C class census, says PDFDocument and PDFPage are not there on either band - so these
// are the port's own classes, not categories.
//
// NOT carried, and not claimed: string extraction through CGPDFScanner.  The release exports
// CGPDFScannerCreate and does NOT export CGPDFScannerScanString or CGPDFScannerGetString, on either
// band, so a -string that scanned the page would be a claim the release cannot answer.  -string answers
// what the port can hold; the scanned extraction is owed and no row says otherwise.

NS_ASSUME_NONNULL_BEGIN

@class PDFPage;
@class PDFBorder;
@class UIColor;

// -init is the third way the header's own comment names a document being made ("either the init
// method, initWithURL:, or initWithData:"), so it is a convenience initializer here and it reaches
// the same private setup the other two do.  That is why -[super init] appears in it at all.
@interface PDFDocument : NSObject
- (nullable instancetype)init NS_DESIGNATED_INITIALIZER;
// The 26.2 header declares NO class factory: grep for documentWithURL in
// PDFDocument.h returns nothing, and its own comment says a document is made with "either the init
// method, initWithURL:, or initWithData:" - PDFDocument.h:138 and :139, both designated
// initializers.  An earlier version of this port added +documentWithURL: and +documentWithData:,
// which are not the API; they are gone and the initializers are what it answers.
- (nullable instancetype)initWithURL:(NSURL *)url NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithData:(NSData *)data NS_DESIGNATED_INITIALIZER;
@property (readonly) NSUInteger pageCount;
@property (readonly, nullable) NSDictionary<NSString *, id> *documentAttributes;
- (nullable id)documentAttribute:(NSString *)attributeName;
- (nullable PDFPage *)pageAtIndex:(NSUInteger)index;
// The four below were chosen from the host's own method list (182 instance methods, every one measured
// with no window open) and each is a reading of something the release hands over.
@property (readonly) BOOL isLocked;          // the trailer's /Encrypt
@property (readonly) BOOL isEncrypted;       // the same
@property (readonly) BOOL allowsCopying;     // YES: the release carries no permission of its own
@property (readonly, nullable) NSURL *documentURL;   // the URL this document was opened with
@property (readonly, nullable) NSData *dataRepresentation;
@end

// PDFView without a window, which is the whole of what this release can offer for it.  The defaults
// are the host's own, measured with no window and never shown; see PDFView11.m and
// facts/PDFKit/Document11.md.  Three members a plan named are NOT this API and are not declared:
// -pageCount, -canDisplayPage:, -usePageViewController: and -scaleToFit, none of which PDFView.h
// declares and none of which the host answers.
@interface PDFView : NSObject
@property (nonatomic, nullable) PDFDocument *document;
@property (nonatomic, readonly, nullable) PDFPage *currentPage;
@property (nonatomic) CGFloat scaleFactor;
@property (nonatomic, readonly) CGFloat minScaleFactor;
@property (nonatomic, readonly) CGFloat maxScaleFactor;
@property (nonatomic) BOOL autoScales;
@property (nonatomic) NSInteger displayMode;
@property (nonatomic) NSInteger displayDirection;
@property (nonatomic) NSInteger displayBox;      // a VALIDATING setter; see PDFView11.m
@property (nonatomic, setter=enablePageShadows:) BOOL pageShadowsEnabled;
- (void)goToPage:(nullable PDFPage *)page;       // the one windowful member; the current page is compared
@end

@interface PDFPage : NSObject
// The port's own initializer over the release's own page: neither release carries PDFPage, so the
// page object is made here rather than found.  Not Apple's API.
// The port's own initializer over the release's own page.  A page keeps the CGPDFDocument it came
// from alive by holding the CGPDFDocumentRef, NOT by holding the PDFDocument: the header declares
// that reference weak (PDFPage.h:70) and CGPDFPageGetDocument hands back a non-retained pointer, so a
// page that outlives its document would otherwise release a page belonging to a released document.
// A document that DOES outlive its pages is the far side of the same hazard: the port's own
// PDFDocument keeps its pages, as GCPhysicalInputProfile keeps its elements.
- (nullable instancetype)initWithCGPDFPage:(CGPDFPageRef)page
                                   document:(nullable PDFDocument *)document
                                      index:(NSUInteger)index;
// The 26.2 header declares this weak (PDFPage.h:70): a page does not keep its document alive.  A
// strong reference here is a use-after-free, because the document is what owns the CGPDFDocument
// the page's own CGPDFPage came from.
@property (readonly, nullable, weak) PDFDocument *document;
@property (readonly) NSUInteger pageIndex;
@property (readonly) CGRect cropBox;
@property (readonly) NSInteger rotation;
@property (readonly, copy, nullable) NSString *string;
// -boundsForBox: was implemented and NOT declared here, so nothing outside PDFPage11.m could call it.
// The header's own -mediaBox and -cropBox are what applications use; this is the general form, and it
// is the port's own initializer-agnostic accessor over CGPDFPageGetBoxRect.
- (CGRect)boundsForBox:(CGPDFBox)box;
@property (readonly) CGRect mediaBox;
// The three below were measured on the host (193 instance methods, no window open) and are a reading of
// the page's own dictionary, not a layout: -label is the page's index as a string, and
// -numberOfCharacters counts the characters of the text walk, a kerning separator included.
@property (readonly, copy, nullable) NSString *label;
@property (readonly) NSUInteger numberOfCharacters;
@property (readonly) NSUInteger annotationCount;
// -annotations is the array the count measures, in the page dictionary's own /Annots order.  The
// model is seven members deep, not the whole family: the members with a subtype-dependent absent
// answer (-color, -border), the measured-but-unidentified -shouldDisplay, and the write and draw
// paths are not in it, and PDFAnnotation11.m says which is which.
@property (readonly, copy) NSArray *annotations;
@end

// The port's own accessors, for its own object graph: the CGPDFDocument and the CGPDFPage underneath,
// which Apple's API does not expose.  Not part of any application-facing surface.
@interface PDFDocument (CharonInternals)
- (nullable CGPDFDocumentRef)charon_CGPDFDocument;
@end

@interface PDFPage (CharonInternals)
- (nullable CGPDFPageRef)charon_CGPDFPage;
@end

// PDFAnnotation, over the annotation dictionary CoreGraphics already parsed out of a page's /Annots.
// Only the members measured on the host are declared, and each is a reading of that dictionary rather
// than a substitute for it:
//
//   -type             the /Subtype NAME as a string - "Text", "Link", "Square" - NOT an integer.  The
//                     property is NSString* const (PDFAnnotation.h:52); the five large negative numbers
//                     recorded before this were NSTaggedPointerString values, which pack the characters
//                     into the pointer and read as nonsense when cast to a long.
//   -bounds           the /Rect, except for a /Text annotation, which is a fixed 24x24 square in the
//                     rect's top-left corner at (minX, maxY-24).  Measured on a rect the rule was not
//                     fitted to, and the 24 is a constant rather than derived - two rects of different
//                     sizes both answer 24x24.  What the 24 IS was not measured and is not claimed.
//   -contents, -userName  the /Contents and /T, nil when the key is absent.
//   -modificationDate the /M in the one form measured, D:YYYYMMDDHHmmSS, read as UTC.
//   -shouldPrint      /F's PRINT bit, measured on /F 0 (NO), 2 (NO) and 4 (YES).
//   -page             the page the annotation was found on, weak.
//
// NOT declared, each for a named reason its row repeats: -color and -border, whose absent answers are
// subtype-dependent (a /Highlight with no /C answers a default yellow; a /Square with no /Border
// answers a default 1.0 line, while a /Link answers nil for both); -shouldDisplay, which answered YES
// for every /F measured and is not the Hidden bit; -hasAppearanceStream and -highlighted, measured NO
// with nothing in the fixtures to change them; -popup and -action, classes of their own; the
// annotation-key API, which is its own family and whose setters are a write path; -drawWithBox:
// (inContext:), which draws into a context this port does not have; and the initializers, which write.
@interface PDFAnnotation : NSObject
@property (nonatomic, copy, nullable) NSString *type;
@property (nonatomic) CGRect bounds;
@property (nonatomic, copy, nullable) NSString *contents;
@property (nonatomic, copy, nullable) NSString *userName;
@property (nonatomic, copy, nullable) NSDate *modificationDate;
@property (nonatomic) BOOL shouldPrint;
@property (nonatomic, weak, nullable) PDFPage *page;
// The border, a PDFBorder of its own below, over this annotation's /Border array and its /BS
// dictionary.  nil is a measured answer and not a missing one: see the rule on -border in
// PDFAnnotation11.m, which is the whole of what the absent case is.
@property (nonatomic, readonly, nullable) PDFBorder *border;
@end

// The port's own constructor, over a dictionary already in the object graph.  Not Apple's
// -initWithBounds:forType:withProperties:, which builds a new annotation and writes it into a document.
@interface PDFAnnotation (CharonInternals)
- (nullable instancetype)initWithCharonDictionary:(CGPDFDictionaryRef)annotation
                                          onPage:(nullable PDFPage *)page;
@end

// ---- PDFBorder, and the two enumerations the port has to spell because the release has no header
// that declares them -------------------------------------------------------
//
// Neither band carries a PDFKit header at all - the port declares its own surface here, and
// PDFKitConstants11.m is the one file that imports the SDK's, because a constant's VALUE has to be
// the host's and its TYPE only has to compile.  So the two enumerations below are transcribed from
// the 26.2 headers, PDFBorder.h:15-21 and PDFAnnotationUtilities.h:20-25, with the values in the
// headers' own order.

// PDFBorderStyle, PDFBorder.h:15.  The five names, in the header's order.  Which /BS /S name answers
// which value is MEASURED, one fixture per name plus one the format does not list (PDFBorder11.m).
typedef NS_ENUM(NSInteger, PDFBorderStyle) {
    kPDFBorderStyleSolid = 0,
    kPDFBorderStyleDashed = 1,
    kPDFBorderStyleBeveled = 2,
    kPDFBorderStyleInset = 3,
    kPDFBorderStyleUnderline = 4,
};

// PDFWidgetControlType, PDFAnnotationUtilities.h:20.  -1 is the header's own kPDFWidgetUnknownControl,
// and it is also what PDFAppearanceCharacteristics answers before anything is set (measured).
typedef NS_ENUM(NSInteger, PDFWidgetControlType) {
    kPDFWidgetUnknownControl = -1,
    kPDFWidgetPushButtonControl = 0,
    kPDFWidgetRadioButtonControl = 1,
    kPDFWidgetCheckBoxControl = 2,
};

// The key names, declared here because the class files cannot import the SDK's PDFKit.h and the
// values are the ones PDFKitConstants11.m exports: @"W", @"S", @"D" and @"BG", @"BC", @"R", @"CA",
// @"RC", @"AC", read out of the host's own PDFKit by tests/backports/host/pdfkit-constants.
extern NSString *const PDFBorderKeyLineWidth;
extern NSString *const PDFBorderKeyStyle;
extern NSString *const PDFBorderKeyDashPattern;
extern NSString *const PDFAppearanceCharacteristicsKeyBackgroundColor;
extern NSString *const PDFAppearanceCharacteristicsKeyBorderColor;
extern NSString *const PDFAppearanceCharacteristicsKeyRotation;
extern NSString *const PDFAppearanceCharacteristicsKeyCaption;
extern NSString *const PDFAppearanceCharacteristicsKeyRolloverCaption;
extern NSString *const PDFAppearanceCharacteristicsKeyDownCaption;

// PDFBorder, over an annotation's /Border array and its /BS dictionary.  The header declares four
// members and no initializer, so the port reads a border out of the object graph rather than
// building one; -style and -lineWidth are declared readwrite as PDFBorder.h:19-20 has them, and only
// their getters are implemented, for the same reason PDFAnnotation's -bounds has no setter: this port
// reads documents, and a setter here would answer without changing the file behind it.
@interface PDFBorder : NSObject
@property (nonatomic) PDFBorderStyle style;
@property (nonatomic) CGFloat lineWidth;
@property (nonatomic, copy, nullable) NSArray *dashPattern;
@property (nonatomic, readonly, copy) NSDictionary *borderKeyValues;
@end

// The port's own constructor, over the annotation dictionary the border was read out of.  Not
// Apple's API: PDFBorder.h declares no initializer at all, so the object is reached through
// -[PDFAnnotation border].
@interface PDFBorder (CharonInternals)
- (nullable instancetype)initWithCharonAnnotationDictionary:(CGPDFDictionaryRef)annotation;
@end

// PDFAppearanceCharacteristics, the /MK dictionary of PDF 1.7 Table 8.40 as a value object.
//
// Nothing in the 26.2 SDK hands one out - there is no -[PDFAnnotation appearanceCharacteristics], and
// grep for appearanceCharacteristics across PDFKit.framework/Headers finds this class's own
// key-values property and nothing else - so the object is its own thing here too, built with -init and
// read back through the same members.  Every member is implemented on both sides of every pair, which
// is what makes it comparable at all: the host's setter and its getter were measured against each
// other (set every member, read every member, read the key values) and the port answers the same.
//
// -controlType is the one member with no key of its own.  The host keeps it, answers it back for every
// value from -1 to 3, and -appearanceCharacteristicsKeyValues does NOT gain a key for it (measured:
// six keys with all six dictionary members set, and still none of them controlType).  So it is an ivar
// here and not an entry in the dictionary, which is what the host does.
@interface PDFAppearanceCharacteristics : NSObject
@property (nonatomic) PDFWidgetControlType controlType;
@property (nonatomic, copy, nullable) UIColor *backgroundColor;
@property (nonatomic, copy, nullable) UIColor *borderColor;
@property (nonatomic) NSInteger rotation;
@property (nonatomic, copy, nullable) NSString *caption;
@property (nonatomic, copy, nullable) NSString *rolloverCaption;
@property (nonatomic, copy, nullable) NSString *downCaption;
@property (nonatomic, readonly, copy) NSDictionary *appearanceCharacteristicsKeyValues;
@end

NS_ASSUME_NONNULL_END
