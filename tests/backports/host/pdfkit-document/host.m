// Binary A: the HOST's PDFKit, and nothing else in the process.
// One key=value line per fact, plus the image dladdr names for the classes it used.
//
// This is half of a two-binary comparison on purpose: an earlier version linked the port's objects
// in here with their class names renamed, so the host framework's own PDFKit and the port's
// @interface shared a translation-unit universe, and a small integer ended up in the port's
// CGPDFDocumentRef.  Nothing of the port's is in this process now.
#import <Foundation/Foundation.h>
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <stdio.h>

static const char *imageOf(Class c)
{
    Dl_info info;
    return (c && dladdr((__bridge const void *)c, &info) && info.dli_fname) ? info.dli_fname : "?";
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        printf("side=host\n");
        printf("host.PDFDocument.image=%s\n", imageOf([PDFDocument class]));
        printf("host.PDFPage.image=%s\n", imageOf([PDFPage class]));
        printf("host.PDFDocument.hasInitWithURL=%d\n", [PDFDocument instancesRespondToSelector:@selector(initWithURL:)]);
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
                    printf("%s.documentAttribute.%s=%s\n", name, [(NSString *)key UTF8String], value ? [(NSString *)value UTF8String] : "(nil)");
                } else {
                    printf("%s.documentAttribute.%s=NOT-COMPARED-no-such-method\n", name, key.UTF8String);
                }
            }
            SEL pageAt = NSSelectorFromString(@"pageAtIndex:");
            if ([document respondsToSelector:pageAt]) {
                PDFPage *first = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(document, pageAt, (NSUInteger)0);
                for (NSString *box in @[ @"mediaBox", @"cropBox" ]) {
                    SEL which = NSSelectorFromString(box);
                    if ([first respondsToSelector:which])
                        printf("%s.page0.%s=%s\n", name, [(NSString *)box UTF8String],
                               NSStringFromRect(((CGRect (*)(id, SEL))objc_msgSend)(first, which)).UTF8String);
                    else
                        printf("%s.page0.%s=NOT-COMPARED-no-such-method\n", name, [(NSString *)box UTF8String]);
                }
                id past = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(document, pageAt, document.pageCount);
                printf("%s.pageAtIndex.one-past-the-end=%s\n", name, past ? "an-object" : "nil");
            } else {
                printf("%s.pageAtIndex.one-past-the-end=NOT-COMPARED-no-such-method\n", name);
            }
        }
    }
    return 0;
}
