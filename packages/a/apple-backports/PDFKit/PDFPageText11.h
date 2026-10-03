// PDFPageText11.h - one page's text, in the three coordinate systems a selection needs.
//
// A PDFSelection's range is an offset into the page's -[PDFPage string], its -selectionsByLine splits that
// string at the line breaks the walk put in it, and its geometry needs the run each character was drawn
// from.  So the walk's result is not a string: it is this, and the string is one of its three answers.
//
// Nothing here is PDFKit API.  The file that implements it exports no symbol any release has, which is
// what lets a band that already carries PDFKit leave it out: see the shared-C-function trap in
// charon/AGENTS.md.  The class names are the port's own, and the port's own registry says so.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// One run of drawn text: the characters, where they were drawn, and the text state they were drawn with.
//
// Every property is @synthesize'd EXPLICITLY: the port's compile line carries
// -Werror=objc-missing-property-synthesis, which is there because a member the port does not carry needs
// @dynamic rather than a silent ivar, and auto-synthesis would give one whether it was asked for or not.
@interface PDFTextRun : NSObject
// The run's own characters, after the control-byte mapping the walk applies.
@property (nonatomic, copy) NSString *text;
// Where this run's text begins in the page's -string, which is what makes the string and the runs two
// views of ONE thing rather than two things that have to be kept in step.
@property (nonatomic) NSUInteger offset;
@property (nonatomic) CGFloat x;
@property (nonatomic) CGFloat y;
@property (nonatomic) CGFloat size;
// The name Tf named, and nil for a stream that draws text without naming a font.
@property (nonatomic, copy, nullable) NSString *fontName;
@end

@interface PDFPageText : NSObject

// The page's -[PDFPage string], or nil for a page whose walk was DISCARDED for taking fewer shows than
// its content stream holds.  The runs and the lines are empty in that case too.
@property (nonatomic, readonly, copy, nullable) NSString *string;
// The runs, in the order the string is built from them: sorted by y DESCENDING, a tie in drawing order.
@property (nonatomic, readonly, copy) NSArray<PDFTextRun *> *runs;

// Built from runs the walk already collected in DRAWING order; the ordering above is applied here, so the
// walk does not care and the string is a property of the runs rather than a second thing to keep.
+ (nullable instancetype)layoutWithRuns:(NSArray<PDFTextRun *> *)drawnRuns;

// The page's text over a range, or nil for a range outside it.
- (nullable NSString *)substringForRange:(NSRange)range;

// THE LINES.  A line is [start, end) in the string, and `end` is one PAST the line-break character when
// the line has one - measured: for the match "two\nthree" on cgfixture-lines2, -selectionsByLine answers
// line 0 with the range {4,4} and the string "two", so the line's RANGE carries the newline and the line's
// STRING does not.  A page with no break has one line, which is the whole string.
- (NSUInteger)numberOfLines;
- (NSRange)lineRangeAtIndex:(NSUInteger)index;
// The lines a range touches, in order, as NSValue-wrapped NSRanges.  A range inside one line answers one;
// a range across two answers two.
- (NSArray<NSValue *> *)lineRangesForRange:(NSRange)range;
// The run a character came from, or nil for an offset the string does not have.
- (nullable PDFTextRun *)runForOffset:(NSUInteger)offset;

@end

// THE LINE RULE, and where it lives.  A line is trimmed of U+0020 at both ends and every run of U+0020
// inside it collapses to one - measured, and facts/PDFKit/Document11.md has the five fixtures.  It is
// applied in -[PDFPageText layoutWithRuns:] rather than exposed, because the layout is the only thing that
// builds page text out of runs and it needs the CHARACTER MAPPING as well as the string: a collapse or a
// trim moves every character after it, so a run's offset into the finished string is not its offset into
// the line it was drawn in.

NS_ASSUME_NONNULL_END