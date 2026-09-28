#import <UIKit/UIKit.h>

// The renderer's five properties and its one arithmetic question, asked of the system's own
// UITextDragPreviewRenderer and of this port's, over the same laid-out text, in one process.
//
// The port's class is compiled under a second name (see the -D in the build), so both answers are
// live at once: UITextDragPreviewRenderer is the system's and CharonPortTextDragPreviewRenderer is
// the port's. The same cases run through each, and every answer is compared as it is produced, so a
// disagreement is named rather than found later.
//
// The text is laid out by the release's own layout manager in both halves, so the glyph positions are
// the release's and the only thing compared is the renderer's arithmetic over them.

typedef void (^Answer)(NSString *name, NSString *value);

// The port's renderer, compiled under this name (the build passes -D for it) so the system's and the
// port's are both live in one process and can be asked the same questions.
@interface CharonPortTextDragPreviewRenderer : NSObject
- (instancetype)initWithLayoutManager:(NSLayoutManager *)layoutManager
                                range:(NSRange)range
                          unifyRects:(BOOL)unify;
@property (nonatomic, readonly) NSLayoutManager *layoutManager;
@property (nonatomic, readonly) UIImage *image;
@property (nonatomic, readonly) CGRect firstLineRect;
@property (nonatomic, readonly) CGRect bodyRect;
@property (nonatomic, readonly) CGRect lastLineRect;
- (void)adjustFirstLineRect:(inout CGRect *)first bodyRect:(inout CGRect *)body
                lastLineRect:(inout CGRect *)last textOrigin:(CGPoint)origin;
@end

static NSString *CharonRect(CGRect rect)
{
    return [NSString stringWithFormat:@"%.1f,%.1f,%.1f,%.1f",
            rect.origin.x, rect.origin.y, rect.size.width, rect.size.height];
}

static NSLayoutManager *CharonMakeLayout(void)
{
    NSTextStorage *storage = [[NSTextStorage alloc] init];
    [storage setAttributedString:[[NSAttributedString alloc]
        initWithString:@"the quick brown fox jumps over the lazy dog and keeps on running for a while"
             attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:14]}]];
    [storage addAttribute:NSFontAttributeName
                    value:[UIFont boldSystemFontOfSize:20]
                    range:NSMakeRange(20, 24)];
    NSLayoutManager *layout = [[NSLayoutManager alloc] init];
    [layout addTextContainer:nil];
    NSTextContainer *container = [[NSTextContainer alloc] initWithSize:CGSizeMake(200, 1000)];
    container.lineFragmentPadding = 5;
    [layout addTextContainer:container];
    [layout ensureLayoutForTextContainer:container];
    return layout;
}

// One line, three lines, and a range starting mid-line rather than at a line's origin, over both
// unify settings: the cases where a rect is zero, where the body is empty and where it is not.
static NSArray<NSValue *> *CharonCases(void)
{
    NSMutableArray *cases = [NSMutableArray array];
    for (NSUInteger length = 1; length <= 45; length += 11)
        for (NSUInteger start = 0; start <= 30; start += 15)
            [cases addObject:[NSValue valueWithRange:NSMakeRange(start, length)]];
    return cases;
}

// The two renderers answer the same questions, and the questions are named by a protocol both
// already conform to in their own right -- the system's by the SDK and the port's by the file it
// implements -- so one body of questions can be asked of either.
@protocol CharonAsksRenderer <NSObject>
@property (nonatomic, readonly) CGRect firstLineRect;
@property (nonatomic, readonly) CGRect bodyRect;
@property (nonatomic, readonly) CGRect lastLineRect;
@property (nonatomic, readonly) NSLayoutManager *layoutManager;
@property (nonatomic, readonly) UIImage *image;
- (void)adjustFirstLineRect:(inout CGRect *)first bodyRect:(inout CGRect *)body
                lastLineRect:(inout CGRect *)last textOrigin:(CGPoint)origin;
@end

static void CharonAsk(id<CharonAsksRenderer> renderer, NSString *tag, Answer host)
{
    host([tag stringByAppendingString:@".firstLineRect"], CharonRect(renderer.firstLineRect));
    host([tag stringByAppendingString:@".bodyRect"], CharonRect(renderer.bodyRect));
    host([tag stringByAppendingString:@".lastLineRect"], CharonRect(renderer.lastLineRect));
    host([tag stringByAppendingString:@".hasLayoutManager"], renderer.layoutManager ? @"yes" : @"no");
    UIImage *image = renderer.image;
    host([tag stringByAppendingString:@".imageSize"],
         image ? CharonRect(CGRectMake(0, 0, image.size.width, image.size.height)) : @"(nil)");

    CGRect first = renderer.firstLineRect;
    CGRect body = renderer.bodyRect;
    CGRect last = renderer.lastLineRect;
    [renderer adjustFirstLineRect:&first bodyRect:&body lastLineRect:&last textOrigin:CGPointMake(7, 11)];
    host([tag stringByAppendingString:@".adjustedFirst"], CharonRect(first));
    host([tag stringByAppendingString:@".adjustedBody"], CharonRect(body));
    host([tag stringByAppendingString:@".adjustedLast"], CharonRect(last));
}

int main(void)
{
    @autoreleasepool {
        NSMutableDictionary *host = [NSMutableDictionary dictionary];
        NSMutableDictionary *port = [NSMutableDictionary dictionary];
        NSLayoutManager *hostLayout = CharonMakeLayout();
        NSLayoutManager *portLayout = CharonMakeLayout();

        for (NSValue *value in CharonCases()) {
            NSRange range = value.rangeValue;
            for (NSNumber *unify in @[@NO, @YES]) {
                NSString *tag = [NSString stringWithFormat:@"unify%@.%lu+%lu",
                                 unify ? @"1" : @"0", (unsigned long)range.location, (unsigned long)range.length];
                UITextDragPreviewRenderer *system = [[UITextDragPreviewRenderer alloc]
                    initWithLayoutManager:hostLayout range:range unifyRects:unify.boolValue];
                CharonPortTextDragPreviewRenderer *ours = [[CharonPortTextDragPreviewRenderer alloc]
                    initWithLayoutManager:portLayout range:range unifyRects:unify.boolValue];
                CharonAsk(system, tag, ^(NSString *n, NSString *v) {
                    host[n] = v;
                });
                CharonAsk(ours, tag, ^(NSString *n, NSString *v) {
                    port[n] = v;
                });
            }
        }

        // The two answers a renderer with nothing to measure gives, which must not be a picture.
        UITextDragPreviewRenderer *systemEmpty = [[UITextDragPreviewRenderer alloc]
            initWithLayoutManager:nil range:NSMakeRange(0, 10) unifyRects:NO];
        host[@"empty.firstLineRect"] = CharonRect(systemEmpty.firstLineRect);
        host[@"empty.image"] = systemEmpty.image ? @"drew" : @"(nil)";
        CharonPortTextDragPreviewRenderer *portEmpty = [[CharonPortTextDragPreviewRenderer alloc]
            initWithLayoutManager:nil range:NSMakeRange(0, 10) unifyRects:NO];
        port[@"empty.firstLineRect"] = CharonRect(portEmpty.firstLineRect);
        port[@"empty.image"] = portEmpty.image ? @"drew" : @"(nil)";

        NSUInteger compared = 0, differing = 0;
        NSArray<NSString *> *names = [[host allKeys] sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *name in names) {
            compared++;
            NSString *h = [host[name] description];
            NSString *p = [port[name] description];
            if (![h isEqualToString:p]) {
                differing++;
                printf("DIFFER %-34s system %-26s port %s\n",
                       name.UTF8String, h.UTF8String, p.UTF8String);
            }
        }
        printf("compared %lu, differing %lu\n", (unsigned long)compared, (unsigned long)differing);
        for (NSString *name in names)
            printf("%s\t%s\n", name.UTF8String, [[host[name] description] UTF8String]);
        return differing ? 1 : 0;
    }
}
