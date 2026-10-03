// A text fixture written by a CONFORMING writer, so the token walk has a stream whose /Length is right.
//
// The hand-written fixtures in make-annotation-fixtures.py are the control and stay in the harness: they
// carry a /Length that does not match what the stream consumes, which is where CGPDFScannerScan stopped
// returning.  This tool exists to answer whether that is a property of the scanner or of those files, and
// it is only useful if it differs from them in exactly that one way - so the TEXT is the same text at the
// same position as charon-fixture-1, through the same CoreGraphics calls the existing make-pdf.m makes.
//
// CGPDFContext IS a conforming writer: it computes /Length from the bytes it wrote.  Nothing here
// post-processes the file, and nothing here writes a PDF by hand.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <string.h>

// One page, the text the harness already asks about, at the position make-pdf.m uses: x=20,
// y=height-40, Helvetica 12.  A second fixture draws the same text at a different y, because a token
// walk that only ever sees one position has not been tested against the page's own geometry.
// THREE LINES on one page, each naming itself, at three different heights.  A selection's
// -selectionsByLine and the line boundaries a search spans are only measurable on a page with more than
// one line, and a conforming writer is what draws them - the same text, the same font, three calls to
// CGContextShowTextAtPoint at descending y.
static void drawLines(NSString *path, CGRect box, const char *const *lines, int count, CGFloat top)
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[(id)kCGPDFContextTitle] = @"conforming-writer three-line fixture";
    info[(id)kCGPDFContextCreator] = @"CGPDFContext";
    CGContextRef context = CGPDFContextCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],
                                                    &box, (__bridge CFDictionaryRef)info);
    if (context == NULL) {
        fprintf(stderr, "could not make a PDF context for %s\n", path.UTF8String);
        return;
    }
    CGPDFContextBeginPage(context, NULL);
    CGContextSelectFont(context, "Helvetica", 12.0, kCGEncodingMacRoman);
    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    for (int i = 0; i < count; i++) {
        CGFloat y = top - 20.0 * i;
        CGContextShowTextAtPoint(context, 20, y, lines[i], (int)strlen(lines[i]));
    }
    CGPDFContextEndPage(context);
    CGPDFContextClose(context);
    CGContextRelease(context);
}

// TWO runs and WHERE the second one is, because the separator between runs is the thing this fixture
// family has to fix and a page with one show operator cannot show it.  Three shapes through the same
// conforming writer: the second run DESCENDING (a new line), at the SAME y (no move at all), and
// ASCENDING - back up the page, which is the shape a rule written from the descending case alone gets
// wrong.
static void drawPair(NSString *path, CGRect box, const char *first, const char *second, CGFloat y0,
                      CGFloat y1)
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[(id)kCGPDFContextCreator] = @"CGPDFContext";
    CGContextRef context = CGPDFContextCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],
                                                    &box, (__bridge CFDictionaryRef)info);
    if (context == NULL) {
        fprintf(stderr, "could not make a PDF context for %s\n", path.UTF8String);
        return;
    }
    CGPDFContextBeginPage(context, NULL);
    CGContextSelectFont(context, "Helvetica", 12.0, kCGEncodingMacRoman);
    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    CGContextShowTextAtPoint(context, 20, y0, first, (int)strlen(first));
    CGContextShowTextAtPoint(context, 20, y1, second, (int)strlen(second));
    CGPDFContextEndPage(context);
    CGPDFContextClose(context);
    CGContextRelease(context);
}

static void draw(NSString *path, int pages, CGRect box, const char *text, CGFloat y)
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[(id)kCGPDFContextTitle] = @"conforming-writer fixture";
    info[(id)kCGPDFContextAuthor] = @"make-text-fixture";
    info[(id)kCGPDFContextCreator] = @"CGPDFContext";
    CGContextRef context = CGPDFContextCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],
                                                    &box, (__bridge CFDictionaryRef)info);
    if (context == NULL) {
        fprintf(stderr, "could not make a PDF context for %s\n", path.UTF8String);
        return;
    }
    for (int page = 1; page <= pages; page++) {
        CGPDFContextBeginPage(context, NULL);
        CGContextSelectFont(context, "Helvetica", 12.0, kCGEncodingMacRoman);
        CGContextSetRGBFillColor(context, 0, 0, 0, 1);
        // Every page shows text through the same call, so the fixtures differ in their GEOMETRY and in
        // their TEXT, and in nothing else.  The text varies PER PAGE - the first version passed one
        // string for all three pages, so pages 2 and 3 drew "page 1" and the host answered "page 1" for
        // all three.  That looked like the host ignoring the page and was this tool drawing the same
        // words three times: a fixture that cannot fail is not a fixture.  Each page now names itself, so
        // a per-page -string is measured rather than assumed.
        NSString *shown = pages > 1 ? [NSString stringWithFormat:@"page %d", page] : @(text);
        CGContextShowTextAtPoint(context, 20, y, shown.UTF8String, (int)shown.length);
        CGPDFContextEndPage(context);
    }
    CGPDFContextClose(context);
    CGContextRelease(context);
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        NSString *directory = argc > 1 ? @(argv[1]) : NSTemporaryDirectory();

        // one page, 200x400, the text at y=360 - the same page as charon-fixture-1, written correctly
        CGRect small = CGRectMake(0, 0, 200, 400);
        NSString *one = [directory stringByAppendingPathComponent:@"cgfixture-1.pdf"];
        draw(one, 1, small, "page 1", 360);
        // three pages, 612x792, the text at y=752 - the same SHAPE as charon-fixture-3, written correctly
        CGRect large = CGRectMake(0, 0, 612, 792);
        NSString *three = [directory stringByAppendingPathComponent:@"cgfixture-3.pdf"];
        draw(three, 3, large, "page 1", 752);
        // one page with NO text at all, so the empty-selection answer is measured on a conforming file
        // and not only on a hand-written one
        NSString *bare = [directory stringByAppendingPathComponent:@"cgfixture-bare.pdf"];
        draw(bare, 1, small, "", 360);

        // one page, three lines at y = 360, 340 and 320 - each naming itself, and the first two lines
        // sharing a WORD ("shared") so a search that spans lines is measurable
        static const char *const lines[] = {"shared one", "shared two", "third line"};
        CGRect lines_box = CGRectMake(0, 0, 300, 400);
        NSString *lines_pdf = [directory stringByAppendingPathComponent:@"cgfixture-lines.pdf"];
        drawLines(lines_pdf, lines_box, lines, 3, 360);

        CGRect pair_box = CGRectMake(0, 0, 300, 400);
        NSString *down = [directory stringByAppendingPathComponent:@"cgfixture-pair-down.pdf"];
        drawPair(down, pair_box, "alpha", "beta", 360, 340);
        NSString *same = [directory stringByAppendingPathComponent:@"cgfixture-pair-same.pdf"];
        drawPair(same, pair_box, "alpha", "beta", 360, 360);
        NSString *up = [directory stringByAppendingPathComponent:@"cgfixture-pair-up.pdf"];
        drawPair(up, pair_box, "alpha", "beta", 340, 360);

        for (NSString *p in @[one, three, bare, lines_pdf, down, same, up])
            printf("  wrote %s\n", [p.lastPathComponent UTF8String]);
    }
    return 0;
}
