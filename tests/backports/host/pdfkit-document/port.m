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

// The key values of one border, in the header's own key order, in the shape both binaries print.
static void printBorderKeys(const char *label, PDFBorder *border)
{
    NSDictionary *keys = [border borderKeyValues];
    NSMutableArray *sorted = [[keys allKeys] mutableCopy];
    [sorted sortUsingSelector:@selector(compare:)];
    printf("%s.keys=%lu\n", label, (unsigned long)sorted.count);
    for (NSString *key in sorted) {
        id value = keys[key];
        if ([value isKindOfClass:[NSArray class]]) {
            NSMutableArray *parts = [NSMutableArray array];
            for (id element in value)
                [parts addObject:[NSString stringWithFormat:@"%.4f", (double)[element doubleValue]]];
            printf("%s.key.%s=%s\n", label, [key UTF8String],
                   [[parts componentsJoinedByString:@","] UTF8String]);
        } else {
            printf("%s.key.%s=%.4f\n", label, [key UTF8String], (double)[value doubleValue]);
        }
    }
}

// The pattern's numbers, which -dashPattern answers and the key values also publish.
static void printBorderDash(const char *label, PDFBorder *border)
{
    NSArray *pattern = [border dashPattern];
    if (pattern == nil) {
        printf("%s.dash.values=(nil)\n", label);
        return;
    }
    NSMutableArray *parts = [NSMutableArray array];
    for (id value in pattern)
        [parts addObject:[NSString stringWithFormat:@"%.4f", (double)[value doubleValue]]];
    printf("%s.dash.values=%s\n", label, [[parts componentsJoinedByString:@","] UTF8String]);
}

// ---- the border as a VALUE OBJECT: its setters, its identity and -setBorder: --------------------
//
// The same keys, the same order and the same prints as host.m's function of the same name, and the
// port's own PDFBorder: -init answers the fresh values, the three setters change the object, and the
// annotation holds the object it is given rather than a copy.
static void printBorderValueFacts(void)
{
    PDFBorder *fresh = [[PDFBorder alloc] init];
    printf("border.fresh.style=%ld\n", (long)[fresh style]);
    printf("border.fresh.lineWidth=%.4f\n", (double)[fresh lineWidth]);
    printf("border.fresh.dash=%s\n", [fresh dashPattern] ? "an-array" : "(nil)");
    printBorderKeys("border.fresh", fresh);
    PDFBorder *all = [[PDFBorder alloc] init];
    [all setStyle:kPDFBorderStyleDashed];
    [all setLineWidth:5];
    [all setDashPattern:@[@7, @5]];
    printf("border.all.style=%ld\n", (long)[all style]);
    printf("border.all.lineWidth=%.4f\n", (double)[all lineWidth]);
    printf("border.all.dash=%s\n", [all dashPattern] ? "an-array" : "(nil)");
    printBorderDash("border.all", all);
    printBorderKeys("border.all", all);
    PDFBorder *pattern = [[PDFBorder alloc] init];
    [pattern setDashPattern:@[@7, @5]];
    printf("border.pattern.style=%ld\n", (long)[pattern style]);
    printf("border.pattern.lineWidth=%.4f\n", (double)[pattern lineWidth]);
    printBorderKeys("border.pattern", pattern);
    PDFBorder *empty = [[PDFBorder alloc] init];
    [empty setDashPattern:@[]];
    printf("border.empty.style=%ld\n", (long)[empty style]);
    printf("border.empty.dash=%s\n", [empty dashPattern] ? "an-array" : "(nil)");
    printBorderDash("border.empty", empty);
    printBorderKeys("border.empty", empty);
    PDFBorder *cleared = [[PDFBorder alloc] init];
    [cleared setLineWidth:5];
    [cleared setStyle:kPDFBorderStyleDashed];
    [cleared setDashPattern:@[@7, @5]];
    [cleared setDashPattern:nil];
    printf("border.cleared.style=%ld\n", (long)[cleared style]);
    printf("border.cleared.lineWidth=%.4f\n", (double)[cleared lineWidth]);
    printf("border.cleared.dash=%s\n", [cleared dashPattern] ? "an-array" : "(nil)");
    printBorderDash("border.cleared", cleared);
    printBorderKeys("border.cleared", cleared);
    PDFBorder *styleOnly = [[PDFBorder alloc] init];
    [styleOnly setStyle:kPDFBorderStyleInset];
    printf("border.styleonly.style=%ld lineWidth=%.4f dash=%s\n", (long)[styleOnly style],
           (double)[styleOnly lineWidth], [styleOnly dashPattern] ? "an-array" : "(nil)");
    printBorderKeys("border.styleonly", styleOnly);
    PDFBorder *widthOnly = [[PDFBorder alloc] init];
    [widthOnly setLineWidth:0];
    printf("border.widthzero.lineWidth=%.4f style=%ld\n", (double)[widthOnly lineWidth],
           (long)[widthOnly style]);
    printBorderKeys("border.widthzero", widthOnly);
}

// ---- the action family and PDFDestination -------------------------------------------------------
//
// The same keys, the same order and the same prints as host.m's, on the port's own classes.  Two things
// are compared rather than described: the CLASS the object is, which is the /S name's answer, and the
// three destination members.  The unspecified sentinel is a NUMBER on both sides - the port exports
// FLT_MAX, which is the host's own value and not CGFLOAT_MAX - so it is printed as the number it is
// rather than symbolically, which is what lets the two bands' different CGFloat widths go unnoticed.
static void printCGFloatOrUnspecified(const char *label, CGFloat value)
{
    printf("%s=%.4f\n", label, (double)value);
}

static void printDestinationFacts(const char *prefix, PDFDestination *destination)
{
    if (destination == nil) {
        printf("%s.destination=nil\n", prefix);
        return;
    }
    printf("%s.destination=an-object\n", prefix);
    PDFPage *page = destination.page;
    printf("%s.destination.page=%s\n", prefix, page ? "an-object" : "(nil)");
    if (page != nil) {
        PDFDocument *owner = page.document;
        unsigned long index = owner ? owner.pageCount : 0;
        for (unsigned long i = 0; owner != nil && i < owner.pageCount; i++) {
            if ([owner pageAtIndex:i] == page) { index = i; break; }
        }
        printf("%s.destination.pageIndex=%lu\n", prefix, index);
    } else {
        printf("%s.destination.pageIndex=-1\n", prefix);
    }
    char key[512];
    snprintf(key, sizeof(key), "%s.destination.point.x", prefix);
    printCGFloatOrUnspecified(key, destination.point.x);
    snprintf(key, sizeof(key), "%s.destination.point.y", prefix);
    printCGFloatOrUnspecified(key, destination.point.y);
    snprintf(key, sizeof(key), "%s.destination.zoom", prefix);
    printCGFloatOrUnspecified(key, destination.zoom);
}

static void printActionFacts(const char *prefix, PDFAction *action)
{
    if (action == nil) {
        printf("%s.action=nil\n", prefix);
        return;
    }
    printf("%s.action.class=%s\n", prefix, class_getName([action class]));
    printf("%s.action.type=%s\n", prefix, [action type] ? [[action type] UTF8String] : "(nil)");
    if ([action isKindOfClass:[PDFActionGoTo class]]) {
        char key[512];
        snprintf(key, sizeof(key), "%s.actionGoTo", prefix);
        printDestinationFacts(key, [(PDFActionGoTo *)action destination]);
    }
    if ([action isKindOfClass:[PDFActionNamed class]])
        printf("%s.action.name=%ld\n", prefix, (long)[(PDFActionNamed *)action name]);
    if ([action isKindOfClass:[PDFActionURL class]]) {
        NSURL *url = [(PDFActionURL *)action URL];
        printf("%s.action.URL=%s\n", prefix,
               [url absoluteString] ? [[url absoluteString] UTF8String] : "(nil)");
    }
    if ([action isKindOfClass:[PDFActionRemoteGoTo class]]) {
        PDFActionRemoteGoTo *remote = (PDFActionRemoteGoTo *)action;
        char key[512];
        printf("%s.action.pageIndex=%lu\n", prefix, (unsigned long)[remote pageIndex]);
        snprintf(key, sizeof(key), "%s.action.point.x", prefix);
        printCGFloatOrUnspecified(key, remote.point.x);
        snprintf(key, sizeof(key), "%s.action.point.y", prefix);
        printCGFloatOrUnspecified(key, remote.point.y);
        printf("%s.action.URL=%s\n", prefix,
               [[remote URL] absoluteString] ? [[[remote URL] absoluteString] UTF8String] : "(nil)");
    }
    if ([action isKindOfClass:[PDFActionResetForm class]]) {
        PDFActionResetForm *reset = (PDFActionResetForm *)action;
        printf("%s.action.fields=%s\n", prefix, [reset fields] ? "an-array" : "(nil)");
        NSMutableArray *parts = [NSMutableArray array];
        for (NSString *field in [reset fields])
            [parts addObject:field];
        [parts sortUsingSelector:@selector(compare:)];
        printf("%s.action.fields.values=%s\n", prefix,
               [[parts componentsJoinedByString:@","] UTF8String]);
        printf("%s.action.cleared=%d\n", prefix, (int)[reset fieldsIncludedAreCleared]);
    }
}

// The six designated initializers the 26.2 headers declare, each built in code with no dictionary
// behind it, because a class the program cannot construct is a class whose setters answer a crash - the
// question the coordinator asked about PDFBorder, asked here before the code was written.
static void printInitializerFacts(const char *fixture)
{
    // A real document, so -initWithPage:atPoint: is asked about a page that exists.  An
    // empty one has no page and answers a different set of values, which is a corner
    // nothing in this harness needs and which probe12 measured separately.
    PDFDocument *document = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:@(fixture)]];
    PDFDestination *plain = [[PDFDestination alloc] init];
    printf("init.destination.page=%s\n", [plain page] ? "an-object" : "(nil)");
    printCGFloatOrUnspecified("init.destination.point.x", [plain point].x);
    printCGFloatOrUnspecified("init.destination.zoom", [plain zoom]);
    PDFPage *page = document != nil && document.pageCount > 0 ? [document pageAtIndex:0] : nil;
    PDFDestination *made = [[PDFDestination alloc] initWithPage:page atPoint:CGPointMake(3, 4)];
    printf("init.destination.made.page=%s\n", [made page] ? "an-object" : "(nil)");
    printCGFloatOrUnspecified("init.destination.made.point.x", [made point].x);
    printCGFloatOrUnspecified("init.destination.made.point.y", [made point].y);
    printCGFloatOrUnspecified("init.destination.made.zoom", [made zoom]);
    [made setZoom:2.5];
    printCGFloatOrUnspecified("init.destination.made.zoomAfterSet", [made zoom]);
    PDFAction *base = [[PDFAction alloc] init];
    printf("init.action.class=%s\n", class_getName([base class]));
    printf("init.action.type=%s\n", [base type] ? [[base type] UTF8String] : "(nil)");
    PDFActionGoTo *goTo = [[PDFActionGoTo alloc] initWithDestination:made];
    printf("init.goto.class=%s type=%s destination=%s\n", class_getName([goTo class]),
           [goTo type] ? [[goTo type] UTF8String] : "(nil)", [goTo destination] ? "an-object" : "(nil)");
    PDFActionGoTo *goToNil = [[PDFActionGoTo alloc] initWithDestination:nil];
    printf("init.gotoNil.destination=%s\n", [goToNil destination] ? "an-object" : "(nil)");
    PDFActionNamed *named = [[PDFActionNamed alloc] initWithName:kPDFActionNamedLastPage];
    printf("init.named.class=%s type=%s name=%ld\n", class_getName([named class]),
           [named type] ? [[named type] UTF8String] : "(nil)", (long)[named name]);
    PDFActionNamed *namedNone = [[PDFActionNamed alloc] initWithName:kPDFActionNamedNone];
    printf("init.namedNone.name=%ld\n", (long)[namedNone name]);
    PDFActionNamed *named99 = [[PDFActionNamed alloc] initWithName:(PDFActionNamedName)99];
    printf("init.named99.name=%ld\n", (long)[named99 name]);
    PDFActionURL *url = [[PDFActionURL alloc] initWithURL:[NSURL URLWithString:@"https://example.com/x"]];
    printf("init.url.class=%s type=%s URL=%s\n", class_getName([url class]),
           [url type] ? [[url type] UTF8String] : "(nil)", [[url URL] absoluteString] ? [[[url URL] absoluteString] UTF8String] : "(nil)");
    PDFActionRemoteGoTo *remote = [[PDFActionRemoteGoTo alloc]
        initWithPageIndex:2 atPoint:CGPointMake(5, 6) fileURL:[NSURL fileURLWithPath:@"/tmp/other.pdf"]];
    printf("init.remote.class=%s type=%s pageIndex=%lu\n", class_getName([remote class]),
           [remote type] ? [[remote type] UTF8String] : "(nil)", (unsigned long)[remote pageIndex]);
    printCGFloatOrUnspecified("init.remote.point.x", [remote point].x);
    printf("init.remote.URL=%s\n", [[remote URL] absoluteString] ? [[[remote URL] absoluteString] UTF8String] : "(nil)");
    PDFActionResetForm *reset = [[PDFActionResetForm alloc] init];
    printf("init.reset.class=%s type=%s fields=%s cleared=%d\n", class_getName([reset class]),
           [reset type] ? [[reset type] UTF8String] : "(nil)", [reset fields] ? "an-array" : "(nil)",
           (int)[reset fieldsIncludedAreCleared]);
    [reset setFields:@[@"a", @"b"]];
    [reset setFieldsIncludedAreCleared:NO];
    printf("init.reset.after.fields=%lu cleared=%d\n", (unsigned long)[reset fields].count,
           (int)[reset fieldsIncludedAreCleared]);
}
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
                printf("%s.page0.string=%s\n", name, [first string] ? [first string].UTF8String : "(nil)");
                printf("%s.page0.annotations.count=%lu\n", name, (unsigned long)first.annotations.count);
                for (unsigned a = 0; a < first.annotations.count; a++) {
                    PDFAnnotation *each = first.annotations[a];
                    char prefix[512];
                    snprintf(prefix, sizeof(prefix), "%s.page0.annotation%u", name, a);
                    printActionFacts(prefix, [each action]);
                    printDestinationFacts(prefix, [each destination]);
                }
                // the BORDER, over PDFBorder11.m, printed in the same keys and the same order as
                // host.m prints it
                for (unsigned a = 0; a < first.annotations.count; a++) {
                    PDFAnnotation *annotation = first.annotations[a];
                    PDFBorder *border = annotation.border;
                    if (border == nil) {
                        printf("%s.page0.annotation%u.border=nil\n", name, a);
                        continue;
                    }
                    printf("%s.page0.annotation%u.border.style=%ld\n", name, a, (long)[border style]);
                    printf("%s.page0.annotation%u.border.lineWidth=%.6f\n", name, a,
                           (double)[border lineWidth]);
                    printf("%s.page0.annotation%u.border.dash=%s\n", name, a,
                           [border dashPattern] ? "an-array" : "(nil)");
                    if ([border dashPattern]) {
                        NSMutableArray *parts = [NSMutableArray array];
                        for (id value in [border dashPattern])
                            [parts addObject:[NSString stringWithFormat:@"%.6f",
                                               (double)[value doubleValue]]];
                        printf("%s.page0.annotation%u.border.dash.values=%s\n", name, a,
                               [[parts componentsJoinedByString:@","] UTF8String]);
                    }
                    NSDictionary *keys = [border borderKeyValues];
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
                // -border's IDENTITY and -setBorder:, in the same keys as host.m prints them and after
                // the per-annotation facts above, because they change that annotation's border
                if (first.annotations.count > 0) {
                    PDFAnnotation *target = first.annotations[0];
                    PDFBorder *once = target.border;
                    printf("%s.page0.border.identity.same=%d\n", name, (int)(once == target.border));
                    if (once != nil) {
                        [once setLineWidth:9];
                        printf("%s.page0.border.identity.mutated=%.4f\n", name,
                               (double)[target.border lineWidth]);
                        PDFBorder *replacement = [[PDFBorder alloc] init];
                        [replacement setLineWidth:11];
                        [target setBorder:replacement];
                        printf("%s.page0.border.set.same=%d\n", name,
                               (int)(target.border == replacement));
                        printf("%s.page0.border.set.lineWidth=%.4f\n", name,
                               (double)[target.border lineWidth]);
                        [replacement setLineWidth:12];
                        printf("%s.page0.border.set.mutated=%.4f\n", name,
                               (double)[target.border lineWidth]);
                        [target setBorder:nil];
                        printf("%s.page0.border.set.nil=%d\n", name, (int)(target.border == nil));
                    }
                }
                for (unsigned k = 0; k < sizeof(kinds) / sizeof(*kinds); k++) {
                    CGRect box = [first boundsForBox:kinds[k].box];
                    printf("%s.page0.%s=%.4f,%.4f,%.4f,%.4f\n", name, kinds[k].name, box.origin.x,
                           box.origin.y, box.size.width, box.size.height);
                }
            }
            PDFPage *past = [document pageAtIndex:document.pageCount];
            printf("%s.pageAtIndex.one-past-the-end=%s\n", name, past ? "an-object" : "nil");
        }
        printInitializerFacts(argv[1]);
        printBorderValueFacts();
    }
    return 0;
}
