#import <UIKit/UIKit.h>
#import "check.h"
#import "dragdroprouting-cases.h"

static NSString *const results_folder = @"/private/var/backports";

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
    printf("asked %s\n", line.UTF8String);
}

// The proposals, which is what carries the arguments: the destination index path the routing
// worked out, and the operation and intent the delegate gives in return, read back through the
// coordinator the routing hands it.
- (UICollectionViewDropProposal *)collectionView:(UICollectionView *)collectionView
                    dropSessionDidUpdate:(id<UIDropSession>)session
        withDestinationIndexPath:(NSIndexPath *)destination
{
    [self note:[NSString stringWithFormat:@"collection.dropSessionDidUpdate:withDestinationIndexPath:%@",
              NSStringFromIndexPath(destination)]];
    return [[UICollectionViewDropProposal alloc] initWithDropOperation:UIDropOperationMove
                                                              intent:UICollectionViewDropIntentInsertIntoDestinationIndexPath];
}

- (void)collectionView:(UICollectionView *)collectionView performDropWithCoordinator:(id<UICollectionViewDropCoordinator>)coordinator
{
    [self note:[NSString stringWithFormat:@"collection.performDropWithCoordinator:items=%lu:destination=%@:operation=%ld:intent=%ld",
              (unsigned long)coordinator.items.count,
              NSStringFromIndexPath(coordinator.destinationIndexPath),
              (long)coordinator.proposal.operation, (long)coordinator.proposal.intent]];
}

- (UITableViewDropProposal *)tableView:(UITableView *)tableView
              dropSessionDidUpdate:(id<UIDropSession>)session
      withDestinationIndexPath:(NSIndexPath *)destination
{
    [self note:[NSString stringWithFormat:@"table.dropSessionDidUpdate:withDestinationIndexPath:%@",
              NSStringFromIndexPath(destination)]];
    return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove
                                                          intent:UITableViewDropIntentInsertIntoDestinationIndexPath];
}

- (void)tableView:(UITableView *)tableView performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator
{
    [self note:[NSString stringWithFormat:@"table.performDropWithCoordinator:items=%lu:destination=%@:operation=%ld:intent=%ld",
              (unsigned long)coordinator.items.count,
              NSStringFromIndexPath(coordinator.destinationIndexPath),
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
              NSStringFromIndexPath(indexPath)]];
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
              NSStringFromIndexPath(indexPath)]];
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

@interface OrderDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation OrderDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
    [[NSFileManager defaultManager] createDirectoryAtPath:results_folder withIntermediateDirectories:YES attributes:nil error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:[results_folder stringByAppendingPathComponent:@"dragdroprouting.done"] error:NULL];
    charon_log_to([results_folder stringByAppendingPathComponent:@"dragdroprouting.log"]);
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[UIViewController alloc] init];
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self run];
    });
    return YES;
}

- (void)finish
{
    printf("checks=%d failures=%d\n", charon_checks, charon_failures);
    NSString *summary = [NSString stringWithFormat:@"%@ checks=%d failures=%d\n",
                         charon_failures ? @"FAIL" : @"ok", charon_checks, charon_failures];
    [summary writeToFile:[results_folder stringByAppendingPathComponent:@"dragdroprouting.done"]
              atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (void)run
{
    OrderProbe *probe = [[OrderProbe alloc] init];
    probe.log = [NSMutableArray array];

    UICollectionViewFlowLayout *flow = [[UICollectionViewFlowLayout alloc] init];
    flow.itemSize = CGSizeMake(40, 40);
    probe.collectionView = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 0, 320, 200)
                                             collectionViewLayout:flow];
    probe.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 320, 200)
                                                    style:UITableViewStylePlain];
    [probe.collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"c"];
    [self.window.rootViewController.view addSubview:probe.collectionView];
    [self.window.rootViewController.view addSubview:probe.tableView];
    [probe.collectionView reloadData];
    [probe.collectionView layoutIfNeeded];
    [probe.tableView reloadData];
    [probe.tableView layoutIfNeeded];

    // The views' own drop delegates, which is who the routing asks.
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
    for (NSString *message in charon_collection_drop_order()) {
        if ([message isEqualToString:@"dropSessionDidUpdate:withDestinationIndexPath:"])
            [expectedCollection addObject:[NSString stringWithFormat:@"collection.%@:0-0", message]];
        else if ([message isEqualToString:@"performDropWithCoordinator:"])
            [expectedCollection addObject:@"collection.performDropWithCoordinator:items=1:destination={0, 0}:operation=1:intent=2"];
        else if ([message isEqualToString:@"dropPreviewParametersForItemAtIndexPath:"])
            [expectedCollection addObject:@"collection.dropPreviewParametersForItemAtIndexPath:0-0"];
        else
            [expectedCollection addObject:[@"collection." stringByAppendingString:message]];
    }
    charon_check([collectionAsked isEqualToArray:expectedCollection],
                 @"the collection view's drop delegate is asked in the documented order, with the arguments it is given",
                 [NSString stringWithFormat:@"\n    asked   %@\n    expect  %@", collectionAsked, expectedCollection]);

    NSArray *tableExpectation = @[@"table.canHandleDropSession",
                                  @"table.dropSessionDidEnter",
                                  @"table.dropSessionDidUpdate:withDestinationIndexPath:0-0",
                                  @"table.dropPreviewParametersForRowAtIndexPath:0-0",
                                  @"table.performDropWithCoordinator:items=1:destination={0, 0}:operation=1:intent=2",
                                  @"table.dropSessionDidExit",
                                  @"table.dropSessionDidEnd"];
    charon_check([tableAsked isEqualToArray:tableExpectation],
                 @"the table view's drop delegate is asked in the documented order, with the arguments it is given",
                 [NSString stringWithFormat:@"\n    asked   %@\n    expect  %@", tableAsked, tableExpectation]);

    printf("asked %lu messages: %lu collection, %lu table\n",
           (unsigned long)probe.log.count, (unsigned long)collectionAsked.count, (unsigned long)tableAsked.count);
    [self finish];
}

@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([OrderDelegate class]));
    }
}
