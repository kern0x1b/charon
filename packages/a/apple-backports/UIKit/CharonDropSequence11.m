#import <UIKit/UIKit.h>
#import <UIKit/UICollectionView.h>
#import <UIKit/UITableView.h>

#import "CharonDragDrop.h"
#import "CharonDragSession.h"
#import "UIDropCoordinators.h"

// One drop, run through, in one place so the routing and the test that asserts it read the same
// order. The messages are the ones ViewDragDropRouting11.m asks; this only says which comes next,
// and it is a separate object rather than a method in that file so the sequence is one readable list
// and the mutation that must turn the test red is a swap of two lines in it.
//
// The order is the host's own, or where the host cannot be asked: the iOSSupport UIKit is the macOS
// UIKit and the four drag and drop delegate protocols are iOS-only, so a conforming Catalyst probe
// does not compile. The sequence is the documented one, and the one ordering an upstream does show
// is WinObjC (MIT) at 94f6b5bf, UICollectionView.mm:1730-1750 -- remove, then tell, then reuse.

@interface CharonTestDropSession : NSObject <UIDropSession>
@property (nonatomic, strong) UIDragItem *item;
@property (nonatomic, assign) CGPoint point;
@property (nonatomic, strong) NSProgress *progress;
@property (nonatomic, assign) UIDropSessionProgressIndicatorStyle progressIndicatorStyle;
- (instancetype)initWithPoint:(CGPoint)point;
@end

@implementation CharonTestDropSession
@synthesize item = _item;
@synthesize point = _point;
@synthesize progress = _progress;
@synthesize progressIndicatorStyle = _progressIndicatorStyle;

// One item carrying a provider, so a delegate that asks what the session carries gets an answer and
// the coordinator has something to move.
- (instancetype)initWithPoint:(CGPoint)point
{
    if ((self = [super init])) {
        _point = point;
        _item = [[UIDragItem alloc] initWithItemProvider:[[NSItemProvider alloc] initWithObject:@"charon"]];
        _progress = [NSProgress progressWithTotalUnitCount:1];
    }
    return self;
}

- (NSArray<UIDragItem *> *)items
{
    return @[_item];
}

- (CGPoint)locationInView:(UIView *)view
{
    return view ? [view convertPoint:_point fromView:nil] : _point;
}

- (BOOL)allowsMoveOperation
{
    return YES;
}

- (BOOL)isRestrictedToDraggingApplication
{
    return YES;
}

- (BOOL)hasItemsConformingToTypeIdentifiers:(NSArray<NSString *> *)typeIdentifiers
{
    return [_item.itemProvider hasItemConformingToTypeIdentifier:typeIdentifiers.firstObject];
}

- (BOOL)canLoadObjectsOfClass:(Class<NSItemProviderReading>)aClass
{
    return [_item.itemProvider canLoadObjectOfClass:aClass];
}

- (id<UIDragSession>)localDragSession
{
    return nil;
}

@end

// What each view asks, in the order it asks it.
NSArray *charon_collection_drop_order(void)
{
    return @[@"canHandleDropSession",
             @"dropSessionDidEnter",
             @"dropSessionDidUpdate:withDestinationIndexPath:",
             @"dropPreviewParametersForItemAtIndexPath:",
             @"performDropWithCoordinator:",
             @"dropSessionDidExit",
             @"dropSessionDidEnd"];
}

NSArray *charon_table_drop_order(void)
{
    return @[@"canHandleDropSession",
             @"dropSessionDidEnter",
             @"dropSessionDidUpdate:withDestinationIndexPath:",
             @"dropPreviewParametersForRowAtIndexPath:",
             @"performDropWithCoordinator:",
             @"dropSessionDidExit",
             @"dropSessionDidEnd"];
}

@interface UICollectionView (CharonDropSequence11)
- (BOOL)charon_canHandleDropSession:(id<UIDropSession>)session;
- (void)charon_tellDropDelegateDidEnter:(id<UIDropSession>)session;
- (UICollectionViewDropProposal *)charon_dropProposalForSession:(id<UIDropSession>)session atIndexPath:(NSIndexPath *)destination;
- (UIDragPreviewParameters *)charon_dropPreviewParametersForItemAtIndexPath:(NSIndexPath *)indexPath;
- (void)charon_performDropOfSession:(id<UIDropSession>)session;
- (void)charon_tellDropDelegateDidExit:(id<UIDropSession>)session;
- (void)charon_tellDropDelegateDidEnd:(id<UIDropSession>)session;
@end

@interface UITableView (CharonDropSequence11)
- (BOOL)charon_canHandleDropSession:(id<UIDropSession>)session;
- (void)charon_tellDropDelegateDidEnter:(id<UIDropSession>)session;
- (UITableViewDropProposal *)charon_dropProposalForSession:(id<UIDropSession>)session atIndexPath:(NSIndexPath *)destination;
- (UIDragPreviewParameters *)charon_dropPreviewParametersForRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)charon_performDropOfSession:(id<UIDropSession>)session;
- (void)charon_tellDropDelegateDidExit:(id<UIDropSession>)session;
- (void)charon_tellDropDelegateDidEnd:(id<UIDropSession>)session;
@end

@implementation UICollectionView (CharonDropSequence11)

- (void)charon_driveDropSessionAtPoint:(CGPoint)point
{
    CharonTestDropSession *session = [[CharonTestDropSession alloc] initWithPoint:point];
    if (![self charon_canHandleDropSession:session])
        return;
    [self charon_tellDropDelegateDidEnter:session];
    NSIndexPath *destination = [self indexPathForItemAtPoint:[self convertPoint:point fromView:nil]];
    if (!destination)
        return;
    [self charon_dropProposalForSession:session atIndexPath:destination];
    [self charon_dropPreviewParametersForItemAtIndexPath:destination];
    [self charon_performDropOfSession:session];
    [self charon_tellDropDelegateDidExit:session];
    [self charon_tellDropDelegateDidEnd:session];
}

@end

@implementation UITableView (CharonDropSequence11)

- (void)charon_driveDropSessionAtPoint:(CGPoint)point
{
    CharonTestDropSession *session = [[CharonTestDropSession alloc] initWithPoint:point];
    if (![self charon_canHandleDropSession:session])
        return;
    [self charon_tellDropDelegateDidEnter:session];
    NSIndexPath *destination = [self indexPathForRowAtPoint:[self convertPoint:point fromView:nil]];
    if (!destination)
        return;
    [self charon_dropProposalForSession:session atIndexPath:destination];
    [self charon_dropPreviewParametersForRowAtIndexPath:destination];
    [self charon_performDropOfSession:session];
    [self charon_tellDropDelegateDidExit:session];
    [self charon_tellDropDelegateDidEnd:session];
}

@end
