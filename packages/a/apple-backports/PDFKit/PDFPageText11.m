#import "PDFPageText11.h"

// The page's text as three views of one walk.  Everything here is arithmetic over the runs the walk
// collected: the string, where each run's text begins in it, and where the line breaks are.  No rule of
// its own is decided here - the rules (a control byte in a run is a NUL, a line is trimmed, the runs of
// spaces inside a line collapse to one, a line ends with the break that joins it to the next) are the
// walk's and are written down in facts/PDFKit/Document11.md.

@implementation PDFTextRun
@synthesize text = _text;
@synthesize offset = _offset;
@synthesize x = _x;
@synthesize y = _y;
@synthesize size = _size;
@synthesize fontName = _fontName;
@end

@implementation PDFPageText {
    // The offsets of the line-break characters in _string, ascending.  Computed once, because a
    // selection asks for a line range per line and a page with many lines would otherwise walk them again.
    NSUInteger *_breaks;
    NSUInteger _breakCount;
}

@synthesize string = _string;
@synthesize runs = _runs;

// ONE LINE, closed: trimmed at both ends, every run of U+0020 inside it collapsed to one, and the
// mapping back to where each kept character was, because a collapse or a trim moves every character
// after it and a run's offset has to be its offset into the FINISHED string.
//
// The two halves of the rule are measured over five fixtures and the mapping is not a rule at all, it is
// the arithmetic: facts/PDFKit/Document11.md has the table, and this is the only place it is applied.
static NSString *charonCloseLine(NSString *line, NSUInteger **mapping, NSUInteger *mappingCount)
{
    NSUInteger length = line.length;
    NSUInteger start = 0;
    NSUInteger end = length;
    while (start < end && [line characterAtIndex:start] == ' ')
        start++;
    while (end > start && [line characterAtIndex:end - 1] == ' ')
        end--;
    NSMutableString *closed = [NSMutableString stringWithCapacity:end - start];
    NSMutableArray<NSNumber *> *from = [NSMutableArray arrayWithCapacity:end - start];
    BOOL afterSpace = NO;
    for (NSUInteger i = start; i < end; i++) {
        unichar c = [line characterAtIndex:i];
        if (c == ' ') {
            if (afterSpace)
                continue;                       // collapsed away, and nothing after it moves either
            afterSpace = YES;
        } else {
            afterSpace = NO;
        }
        [closed appendFormat:@"%C", c];
        [from addObject:@(i)];
    }
    *mappingCount = from.count;
    if (from.count > 0) {
        *mapping = malloc(sizeof(NSUInteger) * from.count);
        if (*mapping == NULL) {
            *mappingCount = 0;
            return nil;
        }
        for (NSUInteger i = 0; i < from.count; i++)
            (*mapping)[i] = [[from objectAtIndex:i] unsignedIntegerValue];
    }
    return closed;
}

+ (instancetype)layoutWithRuns:(NSArray<PDFTextRun *> *)drawnRuns
{
    if (drawnRuns == nil)
        return nil;
    PDFPageText *layout = [[PDFPageText alloc] init];
    NSArray<PDFTextRun *> *ordered = [drawnRuns sortedArrayWithOptions:NSSortStable
                                                        usingComparator:^NSComparisonResult(id a, id b) {
        PDFTextRun *left = a, *right = b;
        if (left.y > right.y)
            return NSOrderedAscending;      // higher on the page first
        if (left.y < right.y)
            return NSOrderedDescending;
        return NSOrderedSame;                // a tie keeps drawing order
    }];
    NSMutableString *text = [NSMutableString string];
    NSMutableArray<PDFTextRun *> *runs = [NSMutableArray arrayWithCapacity:ordered.count];
    NSMutableArray<NSNumber *> *breaks = [NSMutableArray array];
    // The line being built, and the runs in it with their offsets INSIDE it - which are not their offsets
    // in the string, because the line is trimmed and collapsed when it closes.
    NSMutableString *line = [NSMutableString string];
    NSMutableArray<PDFTextRun *> *lineRuns = [NSMutableArray array];
    CGFloat previousY = 0;
    BOOL first = YES;
    // Close the line, put it in the string, and hand every run in it the offset it ends up at.
    void (^closeLine)(void) = ^{
        NSUInteger *mapping = NULL;
        NSUInteger mappingCount = 0;
        NSString *closed = charonCloseLine(line, &mapping, &mappingCount);
        NSUInteger lineStart = text.length;
        if (closed != nil) {
            [text appendString:closed];
            for (PDFTextRun *run in lineRuns) {
                NSUInteger at = run.offset;
                run.offset = mappingCount > at && at != NSUIntegerMax ? lineStart + mapping[at] : lineStart;
            }
            free(mapping);
        }
        for (PDFTextRun *run in lineRuns)
            [runs addObject:run];
        [lineRuns removeAllObjects];
        [line setString:@""];
    };
    for (PDFTextRun *run in ordered) {
        if (run.text == nil || run.text.length == 0)
            continue;
        if (!first && run.y != previousY) {
            closeLine();
            [breaks addObject:@(text.length)];       // the break character goes here
            [text appendString:@"\n"];
        }
        // A tie on y joins with NOTHING, so the line so far is not re-trimmed as it grows - measured, and
        // re-trimming it is what would turn "alpha " + "beta" into "alphabeta".
        run.offset = line.length;
        [line appendString:run.text];
        [lineRuns addObject:run];
        previousY = run.y;
        first = NO;
    }
    if (!first)
        closeLine();
    layout->_string = [text copy];
    layout->_runs = [runs copy];
    layout->_breakCount = breaks.count;
    if (breaks.count > 0) {
        layout->_breaks = malloc(sizeof(NSUInteger) * breaks.count);
        if (layout->_breaks == NULL) {
            layout->_breakCount = 0;
        } else {
            for (NSUInteger i = 0; i < breaks.count; i++)
                layout->_breaks[i] = [[breaks objectAtIndex:i] unsignedIntegerValue];
        }
    }
    return layout;
}

- (void)dealloc
{
    free(_breaks);
}

- (NSUInteger)numberOfLines
{
    if (_string == nil || _string.length == 0)
        return 0;
    return _breakCount + 1;
}

- (NSRange)lineRangeAtIndex:(NSUInteger)index
{
    if (_string == nil || index >= [self numberOfLines])
        return NSMakeRange(NSNotFound, 0);
    NSUInteger start = 0;
    for (NSUInteger i = 0; i < index; i++)
        start = _breaks[i] + 1;
    NSUInteger end = index < _breakCount ? _breaks[index] + 1 : (NSUInteger)_string.length;
    return NSMakeRange(start, end - start);
}

- (NSArray<NSValue *> *)lineRangesForRange:(NSRange)range
{
    NSMutableArray<NSValue *> *answer = [NSMutableArray array];
    if (_string == nil || range.location >= _string.length || range.length == 0)
        return answer;
    for (NSUInteger i = 0; i < [self numberOfLines]; i++) {
        NSRange line = [self lineRangeAtIndex:i];
        if (line.location == NSNotFound)
            break;
        NSRange hit = NSIntersectionRange(line, range);
        if (hit.length > 0)
            [answer addObject:[NSValue valueWithRange:hit]];
    }
    return answer;
}

- (NSString *)substringForRange:(NSRange)range
{
    if (_string == nil || range.location == NSNotFound || range.length == 0)
        return nil;
    if (range.location + range.length > _string.length)
        return nil;
    return [_string substringWithRange:range];
}

- (PDFTextRun *)runForOffset:(NSUInteger)offset
{
    if (_string == nil || offset >= _string.length)
        return nil;
    for (PDFTextRun *run in _runs) {
        if (offset >= run.offset && offset < run.offset + run.text.length)
            return run;
    }
    return nil;
}

@end