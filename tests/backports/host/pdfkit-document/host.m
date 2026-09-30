// The HOST's PDFKit, and nothing else: no port object is in this process, so the two sides cannot
// meet and every answer is proved to have come from where it should - dladdr names the image on each.
//
// One key=value line per fact, and the same keys as port.m.  The box facts go through the host's own
// -boundsForBox: over all five box kinds CGPDFBox declares: the host HAS that method and answers it
// (measured with class_copyMethodList: 193 instance methods, -[PDFPage boundsForBox:] among them), so
// these are facts the run compares.  The host has no -mediaBox and no -cropBox property, which is why
// the two properties' rows are inert while the method's is not.
#import <Foundation/Foundation.h>
#import <PDFKit/PDFKit.h>
#import <objc/message.h>
#import <dlfcn.h>
#include <stdio.h>
#include <string.h>

static const char *imageOf(Class c)
{
    Dl_info info;
    return (c && dladdr((__bridge const void *)c, &info) && info.dli_fname) ? info.dli_fname : "?";
}

static const struct { CGPDFBox box; const char *name; } kinds[] = {
    { kCGPDFMediaBox, "mediaBox" }, { kCGPDFCropBox, "cropBox" },
    { kCGPDFBleedBox, "bleedBox" }, { kCGPDFTrimBox, "trimBox" }, { kCGPDFArtBox, "artBox" },
};

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        printf("side=host\n");
        printf("host.PDFDocument.image=%s\n", imageOf([PDFDocument class]));
        printf("host.PDFPage.image=%s\n", imageOf([PDFPage class]));
        printf("host.PDFDocument.hasInitWithURL=%d\n",
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
                SEL attribute = NSSelectorFromString(@"documentAttribute:");
                if ([document respondsToSelector:attribute]) {
                    id value = ((id (*)(id, SEL, id))objc_msgSend)(document, attribute, key);
                    printf("%s.documentAttribute.%s=%s\n", name, [(NSString *)key UTF8String],
                           value ? [(NSString *)value UTF8String] : "(nil)");
                } else {
                    printf("%s.documentAttribute.%s=NOT-COMPARED-no-such-method\n", name,
                           [(NSString *)key UTF8String]);
                }
            }
            SEL pageAt = NSSelectorFromString(@"pageAtIndex:");
            PDFPage *first = [document respondsToSelector:pageAt]
                                  ? ((id (*)(id, SEL, NSUInteger))objc_msgSend)(document, pageAt, (NSUInteger)0)
                                  : nil;
            if (first == nil || ![first respondsToSelector:@selector(boundsForBox:)]) {
                for (unsigned k = 0; k < sizeof(kinds) / sizeof(*kinds); k++)
                    printf("%s.page0.%s=NOT-COMPARED-no-such-method\n", name, kinds[k].name);
            } else {
                for (unsigned k = 0; k < sizeof(kinds) / sizeof(*kinds); k++) {
                    CGRect box = ((CGRect (*)(id, SEL, CGPDFBox))objc_msgSend)(first,
                                                                            @selector(boundsForBox:),
                                                                            kinds[k].box);
                    printf("%s.page0.%s=%.4f,%.4f,%.4f,%.4f\n", name, kinds[k].name, box.origin.x,
                           box.origin.y, box.size.width, box.size.height);
                }
            }
            id past = [document respondsToSelector:pageAt]
                          ? ((id (*)(id, SEL, NSUInteger))objc_msgSend)(document, pageAt, document.pageCount)
                          : nil;
            printf("%s.pageAtIndex.one-past-the-end=%s\n", name, past ? "an-object" : "nil");
        }
    }
    return 0;
}
