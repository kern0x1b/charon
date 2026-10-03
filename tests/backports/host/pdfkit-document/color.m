// The PORT's PDFAppearanceCharacteristics, in a process that has a real UIColor, and nothing else.
//
// WHY THIS IS A THIRD BINARY and not part of port.m: PDFAppearanceCharacteristics' two colour members
// are UIColor, and UIColor does not exist in a macOS process - the host's own type there is NSColor.
// Mac Catalyst has both: UIKit backed by AppKit, and the CoreGraphics the port reads a PDF with, which
// is the same shape tests/backports/host/uikit2/run.sh builds against.  So this binary is the port's
// objects plus UIKit, and it prints ONLY the appearance block: the six objects and the controlType
// sweep, in the same order and the same keys host.m prints them, so run.sh can merge its answers into
// the port's map for those keys and leave every other key to the macOS port binary.
//
// The two printing helpers below are written out twice, once per binary, and that is forced rather than
// tidy: host.m includes <PDFKit/PDFKit.h> and this file includes "CharonPDFKit.h", and a translation
// unit holding both would carry two @interface PDFDocument definitions that disagree - which is the
// reason this harness is separate processes in the first place.  Their shapes stay identical on
// purpose, because run.sh compares by key and a key only one side prints is not a fact at all.
//
// What that makes comparable: the host sets NSColor red and reads it back as 1 0 0 1, and this binary
// sets UIColor red and reads it back as 1 0 0 1.  The two colour classes differ; the colour does not,
// and the four components are what each platform's own class answers.  No stand-in colour object is
// involved anywhere.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CharonPDFKit.h"
#include <stdio.h>

// A colour, by the four components its own class answers, or "(nil)".  -getRed:green:blue:alpha: is
// on both UIColor and NSColor, so this one function is the whole of the platform difference.
static void printAppearanceColour(const char *label, const char *member, UIColor *colour)
{
    if (colour == nil) {
        printf("appearance.%s.%s=(nil)\n", label, member);
        return;
    }
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [colour getRed:&r green:&g blue:&b alpha:&a];
    printf("appearance.%s.%s=%.6f,%.6f,%.6f,%.6f\n", label, member, (double)r, (double)g, (double)b,
           (double)a);
}

// One appearance-characters object, printed under one label, in the same shape and the same order as
// host.m's function of the same name.
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
        } else if ([value isKindOfClass:[UIColor class]]) {
            CGFloat r = 0, g = 0, b = 0, a = 0;
            [(UIColor *)value getRed:&r green:&g blue:&b alpha:&a];
            printf("appearance.%s.key.%s=%.6f,%.6f,%.6f,%.6f\n", label, [key UTF8String], (double)r,
                   (double)g, (double)b, (double)a);
        } else {
            printf("appearance.%s.key.%s=%.6f\n", label, [key UTF8String], (double)[value doubleValue]);
        }
    }
}

int main(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        printf("side=portcolor\n");
        printAppearanceCharacteristics("fresh", [[PDFAppearanceCharacteristics alloc] init]);
        {
            PDFAppearanceCharacteristics *only = [[PDFAppearanceCharacteristics alloc] init];
            only.caption = @"cap";
            printAppearanceCharacteristics("captionOnly", only);
            PDFAppearanceCharacteristics *cleared = [[PDFAppearanceCharacteristics alloc] init];
            cleared.caption = @"cap";
            cleared.backgroundColor = [UIColor redColor];
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
            full.backgroundColor = [UIColor redColor];
            full.borderColor = [UIColor blueColor];
            full.rotation = 90;
            full.caption = @"cap";
            full.rolloverCaption = @"roll";
            full.downCaption = @"down";
            printAppearanceCharacteristics("full", full);
        }
    }
    return 0;
}