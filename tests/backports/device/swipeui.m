#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <mach/mach_time.h>
#import "check.h"

static NSString *const results_folder = @"/private/var/backports";

typedef void *HidRef;
static HidRef (*hid_client_create)(CFAllocatorRef);
static void (*hid_dispatch)(HidRef, HidRef);
static HidRef (*hid_hand)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, float, float, float, float, float, Boolean, Boolean, uint32_t);
static HidRef (*hid_finger)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, float, float, float, float, float, Boolean, Boolean, uint32_t);
static void (*hid_append)(HidRef, HidRef);
static HidRef hid_client;

static BOOL hid_ready(void)
{
    if (hid_client)
        return YES;
    void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    hid_client_create = dlsym(handle, "IOHIDEventSystemClientCreate");
    hid_dispatch = dlsym(handle, "IOHIDEventSystemClientDispatchEvent");
    hid_hand = dlsym(handle, "IOHIDEventCreateDigitizerEvent");
    hid_finger = dlsym(handle, "IOHIDEventCreateDigitizerFingerEvent");
    hid_append = dlsym(handle, "IOHIDEventAppendEvent");
    if (!hid_client_create || !hid_dispatch || !hid_hand || !hid_finger || !hid_append)
        return NO;
    hid_client = hid_client_create(kCFAllocatorDefault);
    return hid_client != NULL;
}

static void touch(int phase, CGPoint point)
{
    CGSize size = [UIScreen mainScreen].bounds.size;
    uint64_t now = mach_absolute_time();
    float x = point.x / size.width, y = point.y / size.height;
    BOOL down = phase != 2;
    uint32_t mask = phase == 1 ? 0x4 : 0x23;
    HidRef hand = hid_hand(kCFAllocatorDefault, now, 3, 0, 0, mask, 0, x, y, 0, 0, 0, down, down, 0);
    HidRef finger = hid_finger(kCFAllocatorDefault, now, 1, 2, mask, x, y, 0, 0, 0, down, down, 0);
    hid_append(hand, finger);
    hid_dispatch(hid_client, hand);
}

static NSMutableArray *queue;

static void step(NSTimeInterval wait, void (^block)(void))
{
    [queue addObject:@[@(wait), [block copy]]];
}

static void run_queue(void)
{
    if (!queue.count) {
        printf("checks=%d failures=%d\n", charon_checks, charon_failures);
        NSString *summary = [NSString stringWithFormat:@"%@ checks=%d failures=%d\n", charon_failures ? @"FAIL" : @"ok", charon_checks, charon_failures];
        [summary writeToFile:[results_folder stringByAppendingPathComponent:@"swipeui.done"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        return;
    }
    NSArray *entry = queue[0];
    [queue removeObjectAtIndex:0];
    void (^block)(void) = entry[1];
    block();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([entry[0] doubleValue] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        run_queue();
    });
}

static void drag(CGPoint (^from)(void), CGPoint (^to)(void), int steps, NSTimeInterval settle)
{
    __block CGPoint start, end;
    step(0.03, ^{ start = from(); end = to(); touch(0, start); });
    for (int index = 1; index <= steps; index++)
        step(0.03, ^{ touch(1, CGPointMake(start.x + (end.x - start.x) * index / steps, start.y + (end.y - start.y) * index / steps)); });
    step(settle, ^{ touch(2, end); });
}

static void tap(CGPoint (^point)(void), NSTimeInterval settle)
{
    __block CGPoint at;
    step(0.08, ^{ at = point(); touch(0, at); });
    step(settle, ^{ touch(2, at); });
}

@interface SwipeSource : NSObject <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) NSMutableArray *events;
@end

@implementation SwipeSource

- (instancetype)init
{
    if ((self = [super init]))
        _events = [NSMutableArray array];
    return self;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section
{
    return 30;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path
{
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cell"];
    cell.textLabel.text = [NSString stringWithFormat:@"row %ld", (long)path.row];
    return cell;
}

- (void)tableView:(UITableView *)table commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path
{
    [_events addObject:[NSString stringWithFormat:@"commit %ld", (long)path.row]];
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path
{
    [_events addObject:[NSString stringWithFormat:@"select %ld", (long)path.row]];
}

- (void)tableView:(UITableView *)table willBeginEditingRowAtIndexPath:(NSIndexPath *)path
{
    [_events addObject:[NSString stringWithFormat:@"willBegin %ld", (long)path.row]];
}

- (void)tableView:(UITableView *)table didEndEditingRowAtIndexPath:(NSIndexPath *)path
{
    [_events addObject:[NSString stringWithFormat:@"didEnd %ld", (long)path.row]];
}

- (NSArray *)tableView:(UITableView *)table editActionsForRowAtIndexPath:(NSIndexPath *)path
{
    UITableViewRowAction *remove = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive title:@"Delete" handler:^(UITableViewRowAction *action, NSIndexPath *where) {
        [self.events addObject:[NSString stringWithFormat:@"delete %ld", (long)where.row]];
    }];
    UITableViewRowAction *more = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal title:@"More options" handler:^(UITableViewRowAction *action, NSIndexPath *where) {
        [self.events addObject:[NSString stringWithFormat:@"more %ld", (long)where.row]];
    }];
    return @[remove, more];
}

@end

@interface SwipeConfigured : SwipeSource
@property (nonatomic) BOOL fullSwipe;
@end

@implementation SwipeConfigured

- (BOOL)respondsToSelector:(SEL)selector
{
    if (selector == @selector(tableView:editActionsForRowAtIndexPath:))
        return NO;
    return [super respondsToSelector:selector];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path
{
    UIContextualAction *archive = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Archive" handler:^(UIContextualAction *action, UIView *source, void (^completion)(BOOL)) {
        [self.events addObject:[NSString stringWithFormat:@"archive %ld source=%d", (long)path.row, source != nil]];
        completion(YES);
    }];
    archive.backgroundColor = [UIColor blueColor];
    UIContextualAction *flag = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Flag" handler:^(UIContextualAction *action, UIView *source, void (^completion)(BOOL)) {
        [self.events addObject:[NSString stringWithFormat:@"flag %ld", (long)path.row]];
        completion(NO);
    }];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[archive, flag]];
    configuration.performsFirstActionWithFullSwipe = self.fullSwipe;
    return configuration;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)table leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path
{
    UIContextualAction *pin = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Pin" handler:^(UIContextualAction *action, UIView *source, void (^completion)(BOOL)) {
        [self.events addObject:[NSString stringWithFormat:@"pin %ld", (long)path.row]];
        completion(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[pin]];
}

@end

@interface SwipeBare : SwipeSource
@end

@implementation SwipeBare

- (BOOL)respondsToSelector:(SEL)selector
{
    if (selector == @selector(tableView:editActionsForRowAtIndexPath:))
        return NO;
    return [super respondsToSelector:selector];
}

@end

static UIWindow *the_window;
static UITableView *the_table;
static SwipeSource *the_source;

static UITableViewCell *cell_at(NSInteger row)
{
    return [the_table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
}

static CGFloat shift(NSInteger row)
{
    return cell_at(row).contentView.transform.tx;
}

static CGPoint row_point(NSInteger row, CGFloat x)
{
    CGRect rect = [the_table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
    return [the_table convertPoint:CGPointMake(x, CGRectGetMidY(rect)) toView:nil];
}

static CGFloat table_width(void)
{
    return the_table.bounds.size.width;
}

static NSString *joined(void)
{
    return [the_source.events componentsJoinedByString:@","];
}

static NSArray *buttons_of(NSInteger row)
{
    for (UIView *view in cell_at(row).subviews)
        if (strstr(class_getName([view class]), "CharonSwipeContainer"))
            return view.subviews;
    return nil;
}

static CGPoint centre_of(UIView *button)
{
    return [button.superview convertPoint:CGPointMake(CGRectGetMidX(button.frame), CGRectGetMidY(button.frame)) toView:nil];
}

static BOOL any_open(void)
{
    for (UITableViewCell *cell in the_table.visibleCells)
        if (fabs(cell.contentView.transform.tx) > 1)
            return YES;
    return NO;
}

static NSInteger visible_row(void)
{
    return [[the_table indexPathsForVisibleRows][2] row];
}

static void use_table(SwipeSource *source)
{
    step(0.3, ^{
        the_source = source;
        the_table = [[UITableView alloc] initWithFrame:the_window.bounds];
        the_table.dataSource = source;
        the_table.delegate = source;
        UIViewController *controller = [[UIViewController alloc] init];
        controller.view = the_table;
        the_window.rootViewController = controller;
        [the_table layoutIfNeeded];
    });
}

static void rows_scenario(void)
{
    use_table([[SwipeSource alloc] init]);
    drag(^{ return row_point(1, table_width() - 30); }, ^{ return row_point(1, table_width() - 150); }, 8, 0.6);
    step(0.1, ^{
        NSArray *buttons = buttons_of(1);
        CHECK(buttons.count == 2, "a swipe left on a row of a delegate that answers row actions shows two buttons");
        CHECK(shift(1) < -100, "and the content of the row has slid to the left");
        CGFloat total = 0;
        for (UIView *button in buttons)
            total += button.frame.size.width;
        CHECK(fabs(-shift(1) - total) < 1.5, "by the width of the buttons together");
        if (buttons.count == 2) {
            CHECK(((UIView *)buttons[0]).frame.origin.x > ((UIView *)buttons[1]).frame.origin.x, "the second action is to the left of the first, which is at the edge");
            CHECK(((UIView *)buttons[0]).backgroundColor != nil, "each has its colour");
        }
        CHECK([joined() isEqualToString:@"willBegin 1"], "the delegate is told that editing of the row begins");
    });
    tap(^{ return centre_of(buttons_of(1)[0]); }, 0.8);
    step(0.1, ^{
        CHECK([joined() hasPrefix:@"willBegin 1,delete 1"], "a tap on the button at the edge runs its handler with the row's index path");
        CHECK(fabs(shift(1)) < 0.5 && buttons_of(1) == nil, "and the row closes after it");
        CHECK([the_source.events containsObject:@"didEnd 1"], "and the delegate is told that editing of the row ended");
        [the_source.events removeAllObjects];
    });
    drag(^{ return row_point(2, table_width() - 30); }, ^{ return row_point(2, table_width() - 170); }, 6, 0.6);
    step(0.1, ^{
        CHECK(fabs(shift(2)) > 100, "a drag over half the buttons opens the row and it stays open");
    });
    tap(^{ return row_point(4, 60); }, 0.6);
    step(0.1, ^{
        CHECK(!any_open() && buttons_of(2) == nil, "a tap on another row closes it");
        CHECK(![joined() containsString:@"select"], "and selects nothing");
        [the_source.events removeAllObjects];
    });
    drag(^{ return row_point(3, table_width() - 20); }, ^{ return row_point(3, 20); }, 10, 1.0);
    step(0.1, ^{
        CHECK([joined() containsString:@"delete 3"], "a swipe across the row runs the first action");
        CHECK(!any_open(), "and the row is closed after it");
        [the_source.events removeAllObjects];
    });
    __block CGFloat before = 0;
    step(0.1, ^{ before = the_table.contentOffset.y; });
    drag(^{ return CGPointMake(160, 400); }, ^{ return CGPointMake(160, 200); }, 8, 2.0);
    step(0.1, ^{
        CHECK(the_table.contentOffset.y > before + 20, "a vertical drag still scrolls the table");
        CHECK(!any_open(), "and swipes nothing");
    });
    drag(^{ return row_point(visible_row(), table_width() - 30); }, ^{ return row_point(visible_row(), table_width() - 170); }, 6, 0.6);
    __block CGFloat scrolled = 0;
    step(0.1, ^{ scrolled = the_table.contentOffset.y; CHECK(any_open(), "a row is open again"); });
    drag(^{ return CGPointMake(160, 250); }, ^{ return CGPointMake(160, 400); }, 6, 2.0);
    step(0.1, ^{
        CHECK(fabs(the_table.contentOffset.y - scrolled) > 20, "the table scrolls with a row open");
        CHECK(!any_open(), "and the open row closes when it does");
    });
}

static void bare_scenario(void)
{
    use_table([[SwipeBare alloc] init]);
    drag(^{ return row_point(1, table_width() - 30); }, ^{ return row_point(1, table_width() - 150); }, 8, 0.6);
    step(0.1, ^{
        CHECK(buttons_of(1) == nil && fabs(shift(1)) < 0.5, "a table whose delegate answers no actions is left to the release");
    });
}

static void configuration_scenario(void)
{
    use_table([[SwipeConfigured alloc] init]);
    drag(^{ return row_point(1, table_width() - 30); }, ^{ return row_point(1, table_width() - 200); }, 8, 0.6);
    step(0.1, ^{
        NSArray *buttons = buttons_of(1);
        CHECK(buttons.count == 2, "the trailing configuration shows its two actions");
        UIView *first = buttons.count == 2 ? buttons[0] : nil;
        CHECK([first.backgroundColor isEqual:[UIColor blueColor]], "the first action is at the edge with the colour it was given");
    });
    tap(^{ return centre_of(buttons_of(1)[0]); }, 0.8);
    step(0.1, ^{
        CHECK([joined() containsString:@"archive 1 source=1"], "a tap runs the handler with the action's view as its source");
        CHECK(!any_open(), "and the completion handler closes the row");
        [the_source.events removeAllObjects];
    });
    drag(^{ return row_point(2, 30); }, ^{ return row_point(2, 200); }, 8, 0.6);
    step(0.1, ^{
        CHECK(buttons_of(2).count == 1 && shift(2) > 60, "a swipe to the right shows the leading action and slides the row to the right");
    });
    tap(^{ return row_point(5, 60); }, 0.6);
    drag(^{ return row_point(3, table_width() - 20); }, ^{ return row_point(3, 20); }, 10, 0.8);
    step(0.1, ^{
        CHECK(![joined() containsString:@"archive"], "a swipe across a row whose configuration does not ask for a full swipe runs nothing");
        CHECK(fabs(shift(3)) > 100, "and leaves it open");
    });
    tap(^{ return row_point(6, 60); }, 0.6);
    step(0.1, ^{
        ((SwipeConfigured *)the_source).fullSwipe = YES;
        [the_source.events removeAllObjects];
    });
    drag(^{ return row_point(4, table_width() - 20); }, ^{ return row_point(4, 20); }, 10, 1.0);
    step(0.1, ^{
        CHECK([joined() containsString:@"archive 4"], "with full swipe it runs the first action");
    });
}

@interface SwipeDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SwipeDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
    [[NSFileManager defaultManager] createDirectoryAtPath:results_folder withIntermediateDirectories:YES attributes:nil error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:[results_folder stringByAppendingPathComponent:@"swipeui.done"] error:NULL];
    charon_log_to([results_folder stringByAppendingPathComponent:@"swipeui.log"]);
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[UIViewController alloc] init];
    [self.window makeKeyAndVisible];
    the_window = self.window;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        queue = [NSMutableArray array];
        step(0.01, ^{ CHECK(hid_ready(), "touches can be sent to the application through the HID event system"); });
        rows_scenario();
        bare_scenario();
        configuration_scenario();
        run_queue();
    });
    return YES;
}

@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([SwipeDelegate class]));
    }
}
