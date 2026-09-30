// PDFKit's constants of iOS 16.0, read out of the host's own PDFKit with dladdr naming the
// image each value came from; tests/backports/host/pdfkit-constants compares them, and the values
// below are the host's, not a guess at the format's literals.

#import <PDFKit/PDFKit.h>

PDFKIT_EXTERN NSString *const PDFDocumentBurnInAnnotationsOption;
NSString *const PDFDocumentBurnInAnnotationsOption = @"PDFDocumentBurnInAnnotationsOption";
PDFKIT_EXTERN NSString *const PDFDocumentSaveTextFromOCROption;
NSString *const PDFDocumentSaveTextFromOCROption = @"PDFDocumentSaveTextFromOCROption";
