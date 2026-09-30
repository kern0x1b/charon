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
            // the document's own answers, every one of which the host answers with NO WINDOW open
            printf("%s.isLocked=%d\n", name, (int)document.isLocked);
            printf("%s.isEncrypted=%d\n", name, (int)document.isEncrypted);
            printf("%s.allowsCopying=%d\n", name, (int)document.allowsCopying);
            printf("%s.documentURL=%s\n", name,
                   document.documentURL ? [document.documentURL lastPathComponent].UTF8String : "(nil)");
            printf("%s.dataRepresentation.length=%lu\n", name,
                   (unsigned long)document.dataRepresentation.length);
            // the SINGULAR -documentAttribute: the host does not have it (respondsToSelector: 0), so it is
            // not a fact this run can compare and the row stays inert with that reason
            printf("%s.documentAttribute.supported=%d\n", name,
                   (int)[document respondsToSelector:NSSelectorFromString(@"documentAttribute:")]);
            // the PLURAL -documentAttributes the host does have, compared by KEY SET and by the three
            // stable strings.  Never a date and never Producer: the fixture writes a fresh timestamp on
            // every run and Producer is the writer's own string, so neither is a fact that can agree.
            NSDictionary *attributes = document.documentAttributes;
            NSMutableArray *keys = [[attributes allKeys] mutableCopy];
            [keys sortUsingSelector:@selector(compare:)];
            printf("%s.documentAttributes.keys=%lu\n", name, (unsigned long)keys.count);
            for (NSString *key in keys)
                printf("%s.documentAttributes.key.%s\n", name, [(NSString *)key UTF8String]);
            // PDFView with NO WINDOW, the same cases in the same order as the port side
            {
                PDFView *view = [[PDFView alloc] init];
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
                view.displayBox = 0;
                printf("%s.view.displayBox.afterMedia=%ld\n", name, (long)view.displayBox);
                if (view.document.pageCount > 0)
                    [view goToPage:[view.document pageAtIndex:0]];
                printf("%s.view.goToPage.currentPage=%s\n", name,
                       view.currentPage ? "an-object" : "(nil)");
                view.document = nil;
                printf("%s.view.document.afterNil=%s\n", name, view.document ? "an-object" : "(nil)");
                printf("%s.view.currentPage.afterNil=%s\n", name,
                       view.currentPage ? "an-object" : "(nil)");
            }
            for (NSString *key in @[ @"Title", @"Author", @"Creator" ]) {
                id value = attributes[key];
                printf("%s.documentAttributes.%s=%s\n", name, [(NSString *)key UTF8String],
                       value ? [(NSString *)value UTF8String] : "(nil)");
            }
            SEL pageAt = NSSelectorFromString(@"pageAtIndex:");
            PDFPage *first = [document respondsToSelector:pageAt]
                                  ? ((id (*)(id, SEL, NSUInteger))objc_msgSend)(document, pageAt, (NSUInteger)0)
                                  : nil;
            if (first != nil) {
                printf("%s.page0.rotation=%ld\n", name, (long)first.rotation);
                // the page's own answers, measured on the host with no window open either
                printf("%s.page0.label=%s\n", name, first.label ? [first.label UTF8String] : "(nil)");
                printf("%s.page0.document=%s\n", name, first.document ? "an-object" : "(nil)");
                printf("%s.page0.pageIndex.supported=%d\n", name,
                       (int)[first respondsToSelector:NSSelectorFromString(@"pageIndex")]);
                printf("%s.page0.numberOfCharacters=%ld\n", name, (long)first.numberOfCharacters);
                printf("%s.page0.annotations.supported=%d\n", name,
                       (int)[first respondsToSelector:NSSelectorFromString(@"annotations")]);
            } else {
                printf("%s.page0.rotation=NOT-COMPARED-no-page\n", name);
                printf("%s.page0.label=NOT-COMPARED-no-page\n", name);
                printf("%s.page0.document=NOT-COMPARED-no-page\n", name);
                printf("%s.page0.pageIndex=NOT-COMPARED-no-page\n", name);
                printf("%s.page0.numberOfCharacters=NOT-COMPARED-no-page\n", name);
                printf("%s.page0.annotations.count=NOT-COMPARED-no-page\n", name);
            }
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
