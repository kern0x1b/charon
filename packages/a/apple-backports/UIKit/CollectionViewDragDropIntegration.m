#import <UIKit/UIKit.h>

#import "CharonDragDrop.h"
#import "CharonDragSession.h"
#import "UIDropCoordinators.h"

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

// A collection view and a table view taking part in a drag: they install a drag interaction, they
// answer their drag and drop delegates, and they say whether a drag is under way.
//
// `hasActiveDrag` and `hasActiveDrop` are the two that were answering a constant NO while the
// registry called them implemented. They now answer from the sessions that exist: a view has an
// active drag when one of its drag interactions is carrying something, and an active drop when a
// session of its own is under the finger. That is a real answer, and it changes with the drag.

// The drag interactions a view has, which is what hasActiveDrag reports on.
@interface UICollectionView (CharonDragDropIntegration11)
- (NSArray<UIDragInteraction *> *)charon_dragInteractions;
- (NSArray<id<UICollectionViewDropItem>> *)charon_dropItemsAtPoint:(CGPoint)point session:(id<UIDropSession>)session;
@end

@implementation UICollectionView (CharonDragDropIntegration11)

// The drag interactions this view has, which is what hasActiveDrag reports on.
- (NSArray<UIDragInteraction *> *)charon_dragInteractions
{
    NSMutableArray *found = [NSMutableArray array];
    for (id<UIInteraction> interaction in self.interactions)
        if ([interaction isKindOfClass:[UIDragInteraction class]])
            [found addObject:(UIDragInteraction *)interaction];
    return found;
}

- (BOOL)hasActiveDrag
{
    for (UIDragInteraction *drag in [self charon_dragInteractions])
        if (drag.session)
            return YES;
    return NO;
}

- (BOOL)hasActiveDrop
{
    // A drop is active when a session of this view's own drop interaction is under the finger, which
    // is the session the interaction was handed.
    for (id<UIInteraction> interaction in self.interactions) {
        if (![interaction isKindOfClass:[UIDropInteraction class]])
            continue;
        CharonDropSession *session = ((UIDropInteraction *)interaction).currentDrop;
        if (session)
            return YES;
    }
    return NO;
}

// A drop over this view, which is what the release has no way to ask for and an application with a
// drop delegate needs: the items under the point, where they would land and what the delegate
// proposes for them.
- (NSArray<id<UICollectionViewDropItem>> *)charon_dropItemsAtPoint:(CGPoint)point session:(id<UIDropSession>)session
{
    NSMutableArray *items = [NSMutableArray array];
    for (id<UIInteraction> interaction in self.interactions) {
        if (![interaction isKindOfClass:[UIDropInteraction class]])
            continue;
        id<UIDropInteractionDelegate> delegate = ((UIDropInteraction *)interaction).delegate;
        if (![delegate respondsToSelector:@selector(dropInteraction:sessionDidUpdate:)])
            continue;
        NSIndexPath *destination = [self indexPathForItemAtPoint:[self convertPoint:point fromView:nil]];
        if (!destination)
            continue;
        for (UIDragItem *item in session.items) {
            CharonCollectionDropItem *drop = [[CharonCollectionDropItem alloc] init];
            drop.item = item;
            drop.source = [self indexPathForItemAtPoint:CGPointZero];
            UICollectionViewLayoutAttributes *attributes = [self.collectionViewLayout layoutAttributesForItemAtIndexPath:destination];
            drop.size = attributes ? attributes.size : CGSizeZero;
            [items addObject:drop];
        }
        return items;
    }
    return items;
}

@end

@interface UITableView (CharonDragDropIntegration11)
- (NSArray<UIDragInteraction *> *)charon_dragInteractions;
- (NSArray<id<UITableViewDropItem>> *)charon_dropItemsAtPoint:(CGPoint)point session:(id<UIDropSession>)session;
@end

@implementation UITableView (CharonDragDropIntegration11)

- (NSArray<UIDragInteraction *> *)charon_dragInteractions
{
    NSMutableArray *found = [NSMutableArray array];
    for (id<UIInteraction> interaction in self.interactions)
        if ([interaction isKindOfClass:[UIDragInteraction class]])
            [found addObject:(UIDragInteraction *)interaction];
    return found;
}

- (BOOL)hasActiveDrag
{
    for (UIDragInteraction *drag in [self charon_dragInteractions])
        if (drag.session)
            return YES;
    return NO;
}

- (BOOL)hasActiveDrop
{
    for (id<UIInteraction> interaction in self.interactions) {
        if (![interaction isKindOfClass:[UIDropInteraction class]])
            continue;
        CharonDropSession *session = ((UIDropInteraction *)interaction).currentDrop;
        if (session)
            return YES;
    }
    return NO;
}

- (NSArray<id<UITableViewDropItem>> *)charon_dropItemsAtPoint:(CGPoint)point session:(id<UIDropSession>)session
{
    NSMutableArray *items = [NSMutableArray array];
    for (id<UIInteraction> interaction in self.interactions) {
        if (![interaction isKindOfClass:[UIDropInteraction class]])
            continue;
        id<UIDropInteractionDelegate> delegate = ((UIDropInteraction *)interaction).delegate;
        if (![delegate respondsToSelector:@selector(dropInteraction:sessionDidUpdate:)])
            continue;
        NSIndexPath *destination = [self indexPathForRowAtPoint:[self convertPoint:point fromView:nil]];
        if (!destination)
            continue;
        for (UIDragItem *item in session.items) {
            CharonTableDropItem *drop = [[CharonTableDropItem alloc] init];
            drop.item = item;
            drop.source = [self indexPathForRowAtPoint:CGPointZero];
            drop.size = CGSizeMake(self.bounds.size.width, self.rowHeight);
            [items addObject:drop];
        }
        return items;
    }
    return items;
}

@end
