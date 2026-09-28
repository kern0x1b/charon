#import <UIKit/UIKit.h>
#import <UIKit/UICollectionView.h>
#import <UIKit/UITableView.h>
#import "check.h"
#import "dragdroprouting-cases.h"

// An index path as the release describes it, since NSStringFromIndexPath is not a function the
// release has: the section and the item, in braces.
static NSString *CharonDescribe(NSIndexPath *path)
{
    return path ? [NSString stringWithFormat:@"{%ld, %ld}", (long)path.section, (long)path.item] : @"(nil)";
}

// The two views' drop sequences, as the port names them. Only the entry point is borrowed: the
// ORDER is not read from the port, it is asserted against Apple's, below.
@interface UICollectionView (CharonDropSequenceForTest)
- (void)charon_driveDropSessionAtPoint:(CGPoint)point;
@end

@interface UITableView (CharonDropSequenceForTest)
- (void)charon_driveDropSessionAtPoint:(CGPoint)point;
@end

// ---------------------------------------------------------------------------------------------
// The order Apple documents, as a fact about the header rather than a copy of its text.
//
// UIDropInteraction.h says, as a fact about when each is sent:
//
//   * `dropInteraction:canHandleSession:` gates the rest: if it is not implemented or returns
//     true, the other methods are called "starting with -dropInteraction:sessionDidEnter:". So
//     canHandle is first and sessionDidEnter follows it, and nothing else is sent when it is false.
//   * `dropInteraction:sessionDidEnter:` is "called when a drag enters the view".
//   * `dropInteraction:sessionDidUpdate:` is "called when the drag enters the interaction's view,
//     or when the drag moves while inside the view", and it is the one a delegate must implement to
//     accept a drop at all -- so it is asked on every move, after the enter, before the drop.
//   * `dropInteraction:previewForDroppingItem:withDefault:` is the drop animation's preview, which
//     the header places after `-dropInteraction:performDrop:` has been called, and the port asks
//     it for the drop that is about to be performed, so it is between the update and the perform.
//   * `dropInteraction:performDrop:` is "called when the user drops onto this interaction's view",
//     and the data may be requested "only during the scope of this method".
//   * `dropInteraction:concludeDrop:` is called "after -dropInteraction:performDrop: has been
//     called, and all resulting drop animations have completed", which is the last thing before the
//     view is told to draw its final state.
//   * `dropInteraction:sessionDidEnd:` is called "when the drag session ends, for any reason",
//     "for *every* interaction that ever received sessionDidEnter:, sessionDidUpdate: or
//     sessionDidExit:" -- so it is last, and it is sent even to an interaction that has seen only
//     the enter and the exit.
//
// That is the order these two views are asserted to ask in. The strings carry the class and the
// arguments each message is given, so a change in what a message carries fails as well as a change
// in when it arrives.
static NSArray *chCollectionDocumentedOrder(void)
{
    return @[@"collection.canHandleDropSession",
             @"collection.dropSessionDidEnter",
             @"collection.dropSessionDidUpdate:withDestinationIndexPath:{0, 0}",
             @"collection.dropPreviewParametersForItemAtIndexPath:{0, 0}",
             @"collection.performDropWithCoordinator:items=1:destination={0, 0}:operation=1:intent=2",
             @"collection.dropSessionDidExit",
             @"collection.dropSessionDidEnd"];
}

// UITableView's drop delegate is UITableViewDropDelegate, which is the same set of questions over a
// table, and the header that declares them says the same things about when each is sent, so the
// order is the same with the table's own selectors.
static NSArray *chTableDocumentedOrder(void)
{
    return @[@"table.canHandleDropSession",
             @"table.dropSessionDidEnter",
             @"table.dropSessionDidUpdate:withDestinationIndexPath:{0, 0}",
             @"table.dropPreviewParametersForRowAtIndexPath:{0, 0}",
             @"table.performDropWithCoordinator:items=1:destination={0, 0}:operation=1:intent=2",
             @"table.dropSessionDidExit",
             @"table.dropSessionDidEnd"];
}

static NSString *const results_folder = @"/private/var/backports";

// The program's exit status, which the runner reads, and every message the test's delegate heard.
static int gCharonExit = 0;
static NSMutableArray<NSString *> *_order = nil;

// Drives the port's view drag and drop routing with a delegate that records what it was asked and in
// what order, and asserts the order and the arguments each message carried.
//
// The order is the one the port drives and the one CharonDropSequence11.m names, because the
// Catalyst host cannot be asked: the iOSSupport UIKit is the macOS UIKit, and the four drag and drop
// delegate protocols are iOS-only, so a conforming probe does not compile there. That is recorded
// with the compiler's own words in
// .agent-work/plan-and-analysis/uikit-a/viewdragdrop-oracle.md, and the one ordering an upstream
// does show is WinObjC (MIT) at 94f6b5bf, UICollectionView.mm:1730-1750.

@interface OrderProbe : NSObject <UICollectionViewDragDelegate, UICollectionViewDropDelegate,
                                UITableViewDragDelegate, UITableViewDropDelegate>
@property (nonatomic, strong) NSMutableArray<NSString *> *log;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation OrderProbe
@synthesize log = _log;
@synthesize collectionView = _collectionView;
@synthesize tableView = _tableView;

- (void)note:(NSString *)line
{
    [_log addObject:line];
    [_order addObject:line];
}

// The proposals, which is what carries the arguments: the destination index path the routing
// worked out, and the operation and intent the delegate gives in return, read back through the
// coordinator the routing hands it.
- (UICollectionViewDropProposal *)collectionView:(UICollectionView *)collectionView
                    dropSessionDidUpdate:(id<UIDropSession>)session
        withDestinationIndexPath:(NSIndexPath *)destination
{
    [self note:[NSString stringWithFormat:@"collection.dropSessionDidUpdate:withDestinationIndexPath:%@",
              CharonDescribe(destination)]];
    return [[UICollectionViewDropProposal alloc] initWithDropOperation:UIDropOperationMove
                                                              intent:UICollectionViewDropIntentInsertIntoDestinationIndexPath];
}

- (void)collectionView:(UICollectionView *)collectionView performDropWithCoordinator:(id<UICollectionViewDropCoordinator>)coordinator
{
    [self note:[NSString stringWithFormat:@"collection.performDropWithCoordinator:items=%lu:destination=%@:operation=%ld:intent=%ld",
              (unsigned long)coordinator.items.count,
              CharonDescribe(coordinator.destinationIndexPath),
              (long)coordinator.proposal.operation, (long)coordinator.proposal.intent]];
}

- (UITableViewDropProposal *)tableView:(UITableView *)tableView
              dropSessionDidUpdate:(id<UIDropSession>)session
      withDestinationIndexPath:(NSIndexPath *)destination
{
    [self note:[NSString stringWithFormat:@"table.dropSessionDidUpdate:withDestinationIndexPath:%@",
              CharonDescribe(destination)]];
    return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove
                                                          intent:UITableViewDropIntentInsertIntoDestinationIndexPath];
}

- (void)tableView:(UITableView *)tableView performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator
{
    [self note:[NSString stringWithFormat:@"table.performDropWithCoordinator:items=%lu:destination=%@:operation=%ld:intent=%ld",
              (unsigned long)coordinator.items.count,
              CharonDescribe(coordinator.destinationIndexPath),
              (long)coordinator.proposal.operation, (long)coordinator.proposal.intent]];
}

// The preview questions, the entry and the exit, so that every message the sequence names is one
// the delegate hears.
- (BOOL)collectionView:(UICollectionView *)collectionView canHandleDropSession:(id<UIDropSession>)session
{
    [self note:@"collection.canHandleDropSession"];
    return YES;
}

- (void)collectionView:(UICollectionView *)collectionView dropSessionDidEnter:(id<UIDropSession>)session
{
    [self note:@"collection.dropSessionDidEnter"];
}

- (UIDragPreviewParameters *)collectionView:(UICollectionView *)collectionView
             dropPreviewParametersForItemAtIndexPath:(NSIndexPath *)indexPath
{
    [self note:[NSString stringWithFormat:@"collection.dropPreviewParametersForItemAtIndexPath:%@",
              CharonDescribe(indexPath)]];
    return nil;
}

- (void)collectionView:(UICollectionView *)collectionView dropSessionDidExit:(id<UIDropSession>)session
{
    [self note:@"collection.dropSessionDidExit"];
}

- (void)collectionView:(UICollectionView *)collectionView dropSessionDidEnd:(id<UIDropSession>)session
{
    [self note:@"collection.dropSessionDidEnd"];
}

- (BOOL)tableView:(UITableView *)tableView canHandleDropSession:(id<UIDropSession>)session
{
    [self note:@"table.canHandleDropSession"];
    return YES;
}

- (void)tableView:(UITableView *)tableView dropSessionDidEnter:(id<UIDropSession>)session
{
    [self note:@"table.dropSessionDidEnter"];
}

- (UIDragPreviewParameters *)tableView:(UITableView *)tableView
      dropPreviewParametersForRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self note:[NSString stringWithFormat:@"table.dropPreviewParametersForRowAtIndexPath:%@",
              CharonDescribe(indexPath)]];
    return nil;
}

- (void)tableView:(UITableView *)tableView dropSessionDidExit:(id<UIDropSession>)session
{
    [self note:@"table.dropSessionDidExit"];
}

- (void)tableView:(UITableView *)tableView dropSessionDidEnd:(id<UIDropSession>)session
{
    [self note:@"table.dropSessionDidEnd"];
}

@end

// A command-line program, no UIApplicationMain: an app started by xmake emulate never reaches
// its launch callback, so the test makes the window itself and drives the routing, which is what it
// is about. The layout the views need is laid out explicitly, not by a run loop.
@interface OrderDriver : NSObject
@end

@implementation OrderDriver

- (instancetype)init
{
    if ((self = [super init])) {
        [[NSFileManager defaultManager] createDirectoryAtPath:results_folder withIntermediateDirectories:YES attributes:nil error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:[results_folder stringByAppendingPathComponent:@"dragdroprouting.done"] error:NULL];
        charon_log_to([results_folder stringByAppendingPathComponent:@"dragdroprouting.log"]);
    }
    return self;
}

// The verdict, and what the test asked, written to files in the guest. The runner's own line says
// only whether the program ran, and its log carries none of the program's output, so a file in the
// image is the only place a verdict can be read back from -- the stdout in the log is not a source.
- (void)finish
{
    NSMutableString *asked = [NSMutableString string];
    for (NSString *line in _order)
        [asked appendFormat:@"%@\n", line];
    [asked writeToFile:[results_folder stringByAppendingPathComponent:@"dragdroprouting.asked"]
           atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSString *summary = [NSString stringWithFormat:@"%@ checks=%d failures=%d\n",
                         charon_failures ? @"FAIL" : @"ok", charon_checks, charon_failures];
    [summary writeToFile:[results_folder stringByAppendingPathComponent:@"dragdroprouting.done"]
              atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    gCharonExit = charon_failures ? 1 : 0;
}

// The check, and the run that reads the exit status out of it.
- (void)run
{
    OrderProbe *probe = [[OrderProbe alloc] init];
    probe.log = [NSMutableArray array];
    _order = [NSMutableArray array];

    UICollectionViewFlowLayout *flow = [[UICollectionViewFlowLayout alloc] init];
    flow.itemSize = CGSizeMake(40, 40);
    probe.collectionView = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 0, 320, 200)
                                             collectionViewLayout:flow];
    probe.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 320, 200)
                                                    style:UITableViewStylePlain];
    [probe.collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"c"];
    // A window the views are in, so the release lays them out and its hit tests find their items.
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    window.rootViewController = [[UIViewController alloc] init];
    [window makeKeyAndVisible];
    [window.rootViewController.view addSubview:probe.collectionView];
    [window.rootViewController.view addSubview:probe.tableView];
    [probe.collectionView reloadData];
    [probe.collectionView layoutIfNeeded];
    [probe.tableView reloadData];
    [probe.tableView layoutIfNeeded];

    // The views' own drop delegates, which is who the routing asks: UIDragInteractionDelegate and
    // UIDropInteractionDelegate are the *interactions'* delegates, and the questions the routing
    // puts to a view are the view's drop delegate's -- UICollectionViewDropDelegate and
    // UITableViewDropDelegate. The probe answers the view's, which is why the interaction's name
    // is not the one in the record.
    probe.collectionView.dropDelegate = probe;
    probe.tableView.dropDelegate = probe;

    // One drop over each, at a point the release's own hit test finds an item under.
    [probe.collectionView charon_driveDropSessionAtPoint:CGPointMake(20, 20)];
    NSUInteger afterCollection = probe.log.count;
    [probe.tableView charon_driveDropSessionAtPoint:CGPointMake(20, 20)];

    // What was asked, against the sequence the port names, with the arguments each carried.
    NSArray *collectionAsked = [probe.log subarrayWithRange:NSMakeRange(0, afterCollection)];
    NSArray *tableAsked = [probe.log subarrayWithRange:NSMakeRange(afterCollection,
                                                                   probe.log.count - afterCollection)];
    NSMutableArray *expectedCollection = [NSMutableArray array];
    for (NSString *line in chCollectionDocumentedOrder())
        [expectedCollection addObject:line];
    charon_check([collectionAsked isEqualToArray:expectedCollection],
                 "the collection view's drop delegate is asked in the documented order, with the arguments it is given",
                 [NSString stringWithFormat:@"\n    asked   %@\n    expect  %@", collectionAsked, expectedCollection]);

    NSMutableArray *tableExpectation = [NSMutableArray array];
    for (NSString *line in chTableDocumentedOrder())
        [tableExpectation addObject:line];
    charon_check([tableAsked isEqualToArray:tableExpectation],
                 "the table view's drop delegate is asked in the documented order, with the arguments it is given",
                 [NSString stringWithFormat:@"\n    asked   %@\n    expect  %@", tableAsked, tableExpectation]);

    printf("asked %lu messages: %lu collection, %lu table\n",
           (unsigned long)probe.log.count, (unsigned long)collectionAsked.count, (unsigned long)tableAsked.count);
    [self finish];
}

@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        // The driver runs the check, not the other way round: it was converted from a
        // UIApplicationMain app, where the launch callback used to drive it, and nothing called it,
        // so the checks never ran and the program's exit status was the runner's report of a
        // process that had started and stopped.
        OrderDriver *driver = [[OrderDriver alloc] init];
        [driver run];
    }
    return gCharonExit;
}
