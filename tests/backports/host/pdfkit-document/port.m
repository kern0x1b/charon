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
            for (NSString *key in @[ @"Title", @"Author", @"Creator" ]) {
                id value = [document documentAttribute:key];
                printf("%s.documentAttribute.%s=%s\n", name, [(NSString *)key UTF8String],
                       value ? [(NSString *)value UTF8String] : "(nil)");
            }
            // the page must not outlive the document: a page holds its own reference to the
            // CGPDFDocument, and a page still alive when the document deallocs means the page's dealloc
            // releases a document that is already gone
            __autoreleasing PDFPage *first = [document pageAtIndex:0];
            first = nil;
            first = [document pageAtIndex:0];
            if (first == nil) {
                for (unsigned k = 0; k < sizeof(kinds) / sizeof(*kinds); k++)
                    printf("%s.page0.%s=NOT-COMPARED-no-page\n", name, kinds[k].name);
            } else {
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
