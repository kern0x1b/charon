// The port's PDFDocument and PDFPage, and nothing else: no macOS PDFKit is imported or linked here, so
// the host framework's classes cannot be in this process and the two sets of ivars cannot meet.
//
// One key=value line per fact, and the same keys as host.m, so run.sh can diff the two.  The box facts
// go through the port's own -boundsForBox:, which answers every kind CGPDFBox declares, over all five of
// them: the host has that method and answers it (measured: 193 instance methods with
// -[PDFPage boundsForBox:] among them), so these are facts the run compares rather than facts it skips.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "CharonPDFKit.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#include <stdio.h>
#include <string.h>

static const char *imageOf(Class c)
{
    Dl_info info;
    return (c && dladdr((__bridge const void *)c, &info) && info.dli_fname) ? info.dli_fname : "?";
}

// the five box kinds CGPDFBox declares, in the order the header lists them
static const struct { CGPDFBox box; const char *name; } kinds[] = {
    { kCGPDFMediaBox, "mediaBox" }, { kCGPDFCropBox, "cropBox" },
    { kCGPDFBleedBox, "bleedBox" }, { kCGPDFTrimBox, "trimBox" }, { kCGPDFArtBox, "artBox" },
};

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        printf("side=port\n");
        printf("port.PDFDocument.image=%s\n", imageOf([PDFDocument class]));
        printf("port.PDFPage.image=%s\n", imageOf([PDFPage class]));
        printf("port.PDFDocument.hasInitWithURL=%d\n",
               (int)[PDFDocument instancesRespondToSelector:@selector(initWithURL:)]);
        for (int i = 1; i < argc; i++) {
            NSString *path = @(argv[i]);
            const char *name = strrchr(argv[i], '/');
            name = name ? name + 1 : argv[i];
            PDFDocument *document = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:path]];
            if (document == nil) {
                printf("%s.pageCount=nil\n", name);
                printf("%s.document=nil\n", name);
                continue;
            }
            printf("%s.document=an-object\n", name);
            printf("%s.pageCount=%lu\n", name, (unsigned long)document.pageCount);
            // the SINGULAR accessor's presence is EXPECTED to differ: the port implements it and the
            // host does not (respondsToSelector: 0), which is why its row stays inert.
            printf("%s.documentAttribute.supported=%d\n", name,
                   (int)[document respondsToSelector:@selector(documentAttribute:)]);
            // the PLURAL -documentAttributes, which the host does have, compared by KEY SET and by the
            // three stable strings.  A date and Producer are NOT compared: the fixture writes a fresh
            // timestamp on every run and Producer is the writer's own string, so neither can agree.
            NSDictionary *attributes = [document documentAttributes];
            NSMutableArray *keys = [[attributes allKeys] mutableCopy];
            [keys sortUsingSelector:@selector(compare:)];
            printf("%s.documentAttributes.keys=%lu\n", name, (unsigned long)keys.count);
            for (NSString *key in keys)
                printf("%s.documentAttributes.key.%s\n", name, [(NSString *)key UTF8String]);
            for (NSString *key in @[ @"Title", @"Author", @"Creator" ]) {
                id value = attributes[key];
                printf("%s.documentAttributes.%s=%s\n", name, [(NSString *)key UTF8String],
                       value ? [(NSString *)value UTF8String] : "(nil)");
            }
            // the document's own answers, every one measured on the host without a window
            printf("%s.isLocked=%d\n", name, (int)document.isLocked);
            printf("%s.isEncrypted=%d\n", name, (int)document.isEncrypted);
            printf("%s.allowsCopying=%d\n", name, (int)document.allowsCopying);
            printf("%s.documentURL=%s\n", name,
                   document.documentURL ? [document.documentURL lastPathComponent].UTF8String : "(nil)");
            printf("%s.dataRepresentation.length=%lu\n", name,
                   (unsigned long)document.dataRepresentation.length);
                // PDFView with NO WINDOW, which is what this release offers: the host answers these
                // with no window and never shown, and so does the port.
                PDFView *view = [[PDFView alloc] init];
                // -window is a UIView property and the port's PDFView is NOT a UIView: neither band
                // carries UIKit's PDFView, so the fact is the selector's presence, answered by both.
                printf("%s.view.window.supported=%d\n", name,
                       (int)[view respondsToSelector:sel_registerName("window")]);
                printf("%s.view.document.before=%s\n", name, view.document ? "an-object" : "(nil)");
                view.document = document;
                printf("%s.view.document=%s\n", name, view.document ? "an-object" : "(nil)");
                printf("%s.view.currentPage=%s\n", name, view.currentPage ? "an-object" : "(nil)");
                printf("%s.view.scaleFactor=%.4f\n", name, view.scaleFactor);
                printf("%s.view.minScaleFactor=%.4f\n", name, view.minScaleFactor);
                printf("%s.view.maxScaleFactor=%.4f\n", name, view.maxScaleFactor);
                printf("%s.view.autoScales=%d\n", name, (int)view.autoScales);
                printf("%s.view.displayMode=%ld\n", name, (long)view.displayMode);
                printf("%s.view.displayBox=%ld\n", name, (long)view.displayBox);
                printf("%s.view.displayDirection=%ld\n", name, (long)view.displayDirection);
                printf("%s.view.pageShadowsEnabled=%d\n", name, (int)view.pageShadowsEnabled);
                // the VALIDATING setter: the host refuses a box the document does not have
                view.displayBox = 0;   // kPDFDisplayBoxMediaBox, which every page has
                printf("%s.view.displayBox.afterMedia=%ld\n", name, (long)view.displayBox);
                // the one windowful member, compared on the part both sides can answer: the page left
                if (view.document.pageCount > 0)
                    [view goToPage:[view.document pageAtIndex:0]];
                printf("%s.view.goToPage.currentPage=%s\n", name, view.currentPage ? "an-object" : "(nil)");
                view.document = nil;
                printf("%s.view.document.afterNil=%s\n", name, view.document ? "an-object" : "(nil)");
                printf("%s.view.currentPage.afterNil=%s\n", name, view.currentPage ? "an-object" : "(nil)");
            // the page must not outlive the document: a page holds its own reference to the
            // CGPDFDocument, and a page still alive when the document deallocs means the page's dealloc
            // releases a document that is already gone
            __autoreleasing PDFPage *first = [document pageAtIndex:0];
            first = nil;
            first = [document pageAtIndex:0];
            if (first == nil) {
                for (unsigned k = 0; k < sizeof(kinds) / sizeof(*kinds); k++)
                    printf("%s.page0.%s=NOT-COMPARED-no-page\n", name, kinds[k].name);
                printf("%s.page0.rotation=NOT-COMPARED-no-page\n", name);
            } else {
                printf("%s.page0.rotation=%ld\n", name, (long)[first rotation]);
                printf("%s.page0.label=%s\n", name, [first label] ? [first label].UTF8String : "(nil)");
                printf("%s.page0.document=%s\n", name, [first document] ? "an-object" : "(nil)");
                // the host's PDFPage has NO -pageIndex - its own method list carries a private
                // -_documentIndex instead - so the port's index is compared against the index
                // -pageAtIndex: was handed, which is the same number and is answered by both.
                printf("%s.page0.pageIndex.supported=%d\n", name,
                       (int)[first respondsToSelector:@selector(pageIndex)]);
                printf("%s.page0.numberOfCharacters=%ld\n", name, (long)[first numberOfCharacters]);
                // -annotations hands back PDFAnnotation objects and the annotation model is NOT built
                // yet - 62 rows of it are still owed - so the case asks whether the selector is there
                // at all, which is the honest fact until the model exists.
                printf("%s.page0.annotations.supported=%d\n", name,
                       (int)[first respondsToSelector:@selector(annotations)]);
                for (unsigned k = 0; k < sizeof(kinds) / sizeof(*kinds); k++) {
                    CGRect box = [first boundsForBox:kinds[k].box];
                    printf("%s.page0.%s=%.4f,%.4f,%.4f,%.4f\n", name, kinds[k].name, box.origin.x,
                           box.origin.y, box.size.width, box.size.height);
                }
            }
            PDFPage *past = [document pageAtIndex:document.pageCount];
            printf("%s.pageAtIndex.one-past-the-end=%s\n", name, past ? "an-object" : "nil");
        }
    }
    return 0;
}
