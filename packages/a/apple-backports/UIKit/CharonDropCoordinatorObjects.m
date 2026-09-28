#import <UIKit/UIKit.h>
#import <objc/message.h>

#import "CharonDragSession.h"
#import <UIKit/UICollectionView.h>
#import <UIKit/UITableView.h>
#import "UIDropCoordinators.h"

#pragma clang diagnostic ignored "-Wobjc-property-implementation"

// What a drop delegate is handed, and the two placeholder contexts it commits through.
//
// The coordinators are protocols in the header and there is no drop on this release, so the objects
// that answer them are the port's own. What they do is the release's own work: an insertion goes
// through the data source's own callback and the view's own insert, a delete through its own delete,
// and a cell that is showing a placeholder is handed to the delegate's own block.

@implementation CharonCollectionPlaceholderContext {
@private
    UICollectionViewDropPlaceholder *_placeholder;
    UIDragItem *_item;
    __weak UICollectionView *_collectionView;
}

- (instancetype)initWithPlaceholder:(UICollectionViewDropPlaceholder *)placeholder
                                item:(UIDragItem *)item
                              inView:(UICollectionView *)collectionView
{
    if ((self = [super init])) {
        _placeholder = placeholder;
        _item = item;
        _collectionView = collectionView;
    }
    return self;
}

- (UIDragItem *)dragItem
{
    return _item;
}

// The index path and identifier the placeholder stands at, read out of the placeholder itself. They
// are its own properties, on a class whose header the 16.4 umbrella does not carry, so they are
// asked for by their selectors rather than written out here.
- (NSIndexPath *)insertionIndexPath
{
    SEL ask = @selector(insertionIndexPath);
    if ([_placeholder respondsToSelector:ask])
        return ((NSIndexPath * (*)(id, SEL))objc_msgSend)(_placeholder, ask);
    return nil;
}

- (NSString *)reuseIdentifier
{
    SEL ask = @selector(reuseIdentifier);
    if ([_placeholder respondsToSelector:ask])
        return ((NSString * (*)(id, SEL))objc_msgSend)(_placeholder, ask);
    return nil;
}

// The cell for the placeholder, given to the delegate's block. The 26.2 header says this is a no-op
// today and could change; it is implemented as the block being run, which is what the release's own
// comment describes the method's purpose as.
- (void)setNeedsCellUpdate
{
    if (!_collectionView || !_placeholder)
        return;
    void (^update)(__kindof UICollectionViewCell *) = _placeholder.cellUpdateHandler;
    NSIndexPath *path = self.insertionIndexPath;
    if (!update || !path)
        return;
    UICollectionViewCell *cell = [_collectionView dequeueReusableCellWithReuseIdentifier:self.reuseIdentifier
                                                                               forIndexPath:path];
    if (cell)
        update(cell);
}

// The insertion, with the changes the data source made: the block is where the delegate says what it
// inserted, and the view is told afterwards, in the release's own order.
- (BOOL)commitInsertionWithDataSourceUpdates:(void (NS_NOESCAPE ^)(NSIndexPath *insertionIndexPath))dataSourceUpdates
{
    if (!_collectionView || !_placeholder)
        return NO;
    NSIndexPath *path = self.insertionIndexPath;
    if (dataSourceUpdates)
        dataSourceUpdates(path);
    id dataSource = _collectionView.dataSource;
    SEL insert = @selector(collectionView:insertItemsAtIndexPaths:);
    if ([dataSource respondsToSelector:insert]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(dataSource, insert, _collectionView, @[path]);
        [_collectionView insertItemsAtIndexPaths:@[path]];
    } else {
        [_collectionView insertItemsAtIndexPaths:@[path]];
    }
    return YES;
}

// The placeholder is done with, and the view is told to take it out.
- (BOOL)deletePlaceholder
{
    if (!_collectionView || !_placeholder)
        return NO;
    NSIndexPath *path = self.insertionIndexPath;
    id dataSource = _collectionView.dataSource;
    SEL remove = @selector(collectionView:deleteItemsAtIndexPaths:);
    if ([dataSource respondsToSelector:remove]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(dataSource, remove, _collectionView, @[path]);
        [_collectionView deleteItemsAtIndexPaths:@[path]];
    } else {
        [_collectionView deleteItemsAtIndexPaths:@[path]];
    }
    return YES;
}

@end

@interface CharonTablePlaceholderContext ()
- (NSIndexPath *)insertionIndexPath;
@end

@implementation CharonTablePlaceholderContext {
@private
    UITableViewDropPlaceholder *_placeholder;
    UIDragItem *_item;
    __weak UITableView *_tableView;
}

- (instancetype)initWithPlaceholder:(UITableViewDropPlaceholder *)placeholder
                                item:(UIDragItem *)item
                              inView:(UITableView *)tableView
{
    if ((self = [super init])) {
        _placeholder = placeholder;
        _item = item;
        _tableView = tableView;
    }
    return self;
}

- (UIDragItem *)dragItem
{
    return _item;
}

- (BOOL)commitInsertionWithDataSourceUpdates:(void (NS_NOESCAPE ^)(NSIndexPath *insertionIndexPath))dataSourceUpdates
{
    if (!_tableView || !_placeholder)
        return NO;
    NSIndexPath *path = self.insertionIndexPath;
    if (dataSourceUpdates)
        dataSourceUpdates(path);
    id dataSource = _tableView.dataSource;
    SEL insert = @selector(tableView:insertRowsAtIndexPaths:withRowAnimation:);
    if ([dataSource respondsToSelector:insert]) {
        ((void (*)(id, SEL, id, id, NSInteger))objc_msgSend)(dataSource, insert, _tableView, @[path], UITableViewRowAnimationAutomatic);
        [_tableView insertRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationAutomatic];
    } else {
        [_tableView insertRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    return YES;
}

- (BOOL)deletePlaceholder
{
    if (!_tableView || !_placeholder)
        return NO;
    NSIndexPath *path = self.insertionIndexPath;
    id dataSource = _tableView.dataSource;
    SEL remove = @selector(tableView:deleteRowsAtIndexPaths:withRowAnimation:);
    if ([dataSource respondsToSelector:remove]) {
        ((void (*)(id, SEL, id, id, NSInteger))objc_msgSend)(dataSource, remove, _tableView, @[path], UITableViewRowAnimationAutomatic);
        [_tableView deleteRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationAutomatic];
    } else {
        [_tableView deleteRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    return YES;
}

@end
