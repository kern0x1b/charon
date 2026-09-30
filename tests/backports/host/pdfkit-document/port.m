// Binary B: the PORT's PDFDocument and PDFPage, and nothing else in the process.
//
// No macOS PDFKit is imported or linked here, so the host framework's PDFDocument cannot be in this
// address space and the two sets of ivars cannot meet.  The port's own CharonPDFKit.h declares its
// classes and imports only Foundation and CoreGraphics, which is why this compiles as it stands.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "CharonPDFKit.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#import <objc/message.h>
#include <stdio.h>
#include <string.h>

static const char *imageOf(Class c)
{
    Dl_info info;
    return (c && dladdr((__bridge const void *)c, &info) && info.dli_fname) ? info.dli_fname : "?";
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        printf("side=port\n");
        printf("port.PDFDocument.image=%s\n", imageOf([PDFDocument class]));
        printf("port.PDFPage.image=%s\n", imageOf([PDFPage class]));
        printf("port.PDFDocument.hasInitWithURL=%d\n", [PDFDocument instancesRespondToSelector:@selector(initWithURL:)]);
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
                printf("%s.documentAttribute.%s=%s\n", name, [(NSString *)key UTF8String], value ? [(NSString *)value UTF8String] : "(nil)");
            }
            __autoreleasing PDFPage *first = [document pageAtIndex:0];
            if (first != nil) {
                for (NSString *box in @[ @"mediaBox", @"cropBox" ]) {
                    CGRect r = [first boundsForBox:[box isEqualToString:@"mediaBox"] ? kCGPDFMediaBox : kCGPDFCropBox];
                    printf("%s.page0.%s=%s\n", name, [(NSString *)box UTF8String], NSStringFromRect(r).UTF8String);
                }
            } else {
                printf("%s.page0.mediaBox=NOT-COMPARED-no-page\n", name);
                printf("%s.page0.cropBox=NOT-COMPARED-no-page\n", name);
            }
            // TEST 2: the page must not outlive the document here.  A page holds its own reference to
            // the CGPDFDocument, and a page still alive when the document deallocs means the page's
            // dealloc releases a document the document already released.
            first = nil;
            PDFPage *past = [document pageAtIndex:document.pageCount];
            printf("%s.pageAtIndex.one-past-the-end=%s\n", name, past ? "an-object" : "nil");
        }
    }
    return 0;
}
