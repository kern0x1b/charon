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

// A colour, by its components, or "(nil)".
static void printAppearanceColour(const char *label, const char *member, id colour)
{
    if (colour == nil) {
        printf("appearance.%s.%s=(nil)\n", label, member);
        return;
    }
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [(id)colour getRed:&r green:&g blue:&b alpha:&a];
    printf("appearance.%s.%s=%.6f,%.6f,%.6f,%.6f\n", label, member, (double)r, (double)g, (double)b,
           (double)a);
}

// One appearance-characters object, printed under one label, so the two sides' blocks are the same
// shape and the comparison needs no knowledge of which is which.
static void printAppearanceCharacteristics(const char *label,
                                           PDFAppearanceCharacteristics *characteristics)
{
    printf("appearance.%s.controlType=%ld\n", label, (long)characteristics.controlType);
    printf("appearance.%s.rotation=%ld\n", label, (long)characteristics.rotation);
    printAppearanceColour(label, "backgroundColor", characteristics.backgroundColor);
    printAppearanceColour(label, "borderColor", characteristics.borderColor);
    printf("appearance.%s.caption=%s\n", label,
           characteristics.caption ? characteristics.caption.UTF8String : "(nil)");
    printf("appearance.%s.rolloverCaption=%s\n", label,
           characteristics.rolloverCaption ? characteristics.rolloverCaption.UTF8String : "(nil)");
    printf("appearance.%s.downCaption=%s\n", label,
           characteristics.downCaption ? characteristics.downCaption.UTF8String : "(nil)");
    NSDictionary *keys = characteristics.appearanceCharacteristicsKeyValues;
    NSMutableArray *sorted = [[keys allKeys] mutableCopy];
    [sorted sortUsingSelector:@selector(compare:)];
    printf("appearance.%s.keys=%lu\n", label, (unsigned long)sorted.count);
    for (NSString *key in sorted) {
        id value = keys[key];
        if ([value isKindOfClass:[NSString class]]) {
            printf("appearance.%s.key.%s=%s\n", label, [key UTF8String],
                   [(NSString *)value UTF8String]);
        } else if ([value respondsToSelector:@selector(getRed:green:blue:alpha:)]) {
            // a colour, compared by its four components: the host's is an NSColor and the port's is a
            // UIColor, and their -description strings are not the same string, so the components are
            // what both sides can answer
            CGFloat r = 0, g = 0, b = 0, a = 0;
            [(id)value getRed:&r green:&g blue:&b alpha:&a];
            printf("appearance.%s.key.%s=%.6f,%.6f,%.6f,%.6f\n", label, [key UTF8String], (double)r,
                   (double)g, (double)b, (double)a);
        } else {
            printf("appearance.%s.key.%s=%.6f\n", label, [key UTF8String], (double)[value doubleValue]);
        }
    }
}

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
                printf("%s.page0.string=%s\n", name, first.string ? first.string.UTF8String : "(nil)");
                printf("%s.page0.annotations.count=%lu\n", name, (unsigned long)first.annotations.count);
                // The BORDER, whose own members are a family of their own: PDFBorder11.m carries the
                // rules and the fixtures that fix them.  A nil border is printed as nil and is NOT
                // compared against the port's nil by accident - it is compared like anything else, and
                // the subtypes that answer one where the port does not would show up here.
                for (unsigned a = 0; a < first.annotations.count; a++) {
                    PDFBorder *border = first.annotations[a].border;
                    if (border == nil) {
                        printf("%s.page0.annotation%u.border=nil\n", name, a);
                        continue;
                    }
                    printf("%s.page0.annotation%u.border.style=%ld\n", name, a, (long)border.style);
                    printf("%s.page0.annotation%u.border.lineWidth=%.6f\n", name, a,
                           (double)border.lineWidth);
                    printf("%s.page0.annotation%u.border.dash=%s\n", name, a,
                           border.dashPattern ? "an-array" : "(nil)");
                    if (border.dashPattern) {
                        NSMutableArray *parts = [NSMutableArray array];
                        for (id value in border.dashPattern)
                            [parts addObject:[NSString stringWithFormat:@"%.6f",
                                               (double)[value doubleValue]]];
                        printf("%s.page0.annotation%u.border.dash.values=%s\n", name, a,
                               [[parts componentsJoinedByString:@","] UTF8String]);
                    }
                    NSDictionary *keys = border.borderKeyValues;
                    NSMutableArray *sorted = [[keys allKeys] mutableCopy];
                    [sorted sortUsingSelector:@selector(compare:)];
                    printf("%s.page0.annotation%u.border.keys=%lu\n", name, a,
                           (unsigned long)sorted.count);
                    for (NSString *key in sorted) {
                        id value = keys[key];
                        if ([value isKindOfClass:[NSString class]]) {
                            printf("%s.page0.annotation%u.border.key.%s=%s\n", name, a,
                                   [key UTF8String], [(NSString *)value UTF8String]);
                        } else if ([value isKindOfClass:[NSArray class]]) {
                            NSMutableArray *parts = [NSMutableArray array];
                            for (id element in value)
                                [parts addObject:[NSString stringWithFormat:@"%.6f",
                                                   (double)[element doubleValue]]];
                            printf("%s.page0.annotation%u.border.key.%s=%s\n", name, a,
                                   [key UTF8String], [[parts componentsJoinedByString:@","] UTF8String]);
                        } else {
                            printf("%s.page0.annotation%u.border.key.%s=%.6f\n", name, a,
                                   [key UTF8String], (double)[value doubleValue]);
                        }
                    }
                }
                for (unsigned a = 0; a < first.annotations.count; a++) {
                    PDFAnnotation *an = first.annotations[a];
                    CGRect r = an.bounds;
                    printf("%s.page0.annotation%u.type=%s\n", name, a,
                           an.type ? an.type.UTF8String : "(nil)");
                    printf("%s.page0.annotation%u.bounds=%.4f,%.4f,%.4f,%.4f\n", name, a,
                           r.origin.x, r.origin.y, r.size.width, r.size.height);
                    printf("%s.page0.annotation%u.contents=%s\n", name, a,
                           an.contents ? an.contents.UTF8String : "(nil)");
                    printf("%s.page0.annotation%u.userName=%s\n", name, a,
                           an.userName ? an.userName.UTF8String : "(nil)");
                    printf("%s.page0.annotation%u.shouldPrint=%d\n", name, a, (int)an.shouldPrint);
                    printf("%s.page0.annotation%u.page=%s\n", name, a, an.page ? "an-object" : "(nil)");
                }
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
        // PDFAppearanceCharacteristics, which no annotation hands out in the 26.2 SDK, so it is its
        // own object on this side too and the comparison is object against object.  Every member is
        // read on a fresh one, then every member is set and read again, and the key values are read
        // at each step: the second reading is what shows a setter that drops its value.
        printAppearanceCharacteristics("fresh", [[PDFAppearanceCharacteristics alloc] init]);
        {
            PDFAppearanceCharacteristics *only = [[PDFAppearanceCharacteristics alloc] init];
            only.caption = @"cap";
            printAppearanceCharacteristics("captionOnly", only);
            PDFAppearanceCharacteristics *cleared = [[PDFAppearanceCharacteristics alloc] init];
            cleared.caption = @"cap";
            cleared.backgroundColor = [NSColor redColor];
            cleared.caption = nil;
            cleared.backgroundColor = nil;
            printAppearanceCharacteristics("cleared", cleared);
            PDFAppearanceCharacteristics *empty = [[PDFAppearanceCharacteristics alloc] init];
            empty.caption = @"";
            empty.downCaption = @"";
            printAppearanceCharacteristics("empty", empty);
            PDFAppearanceCharacteristics *negative = [[PDFAppearanceCharacteristics alloc] init];
            negative.rotation = -90;
            printAppearanceCharacteristics("negative", negative);
            for (long control = -1; control <= 3; control++) {
                PDFAppearanceCharacteristics *probe =
                    [[PDFAppearanceCharacteristics alloc] init];
                probe.controlType = (PDFWidgetControlType)control;
                printf("appearance.controlType%ld.read=%ld\n", control, (long)probe.controlType);
                printf("appearance.controlType%ld.keys=%lu\n", control,
                       (unsigned long)probe.appearanceCharacteristicsKeyValues.count);
            }
            PDFAppearanceCharacteristics *full = [[PDFAppearanceCharacteristics alloc] init];
            full.controlType = kPDFWidgetCheckBoxControl;
            full.backgroundColor = [NSColor redColor];
            full.borderColor = [NSColor blueColor];
            full.rotation = 90;
            full.caption = @"cap";
            full.rolloverCaption = @"roll";
            full.downCaption = @"down";
            printAppearanceCharacteristics("full", full);
        }
    }
    return 0;
}
