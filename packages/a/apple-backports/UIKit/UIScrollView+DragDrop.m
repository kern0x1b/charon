#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface CharonDragDropBox : NSObject {
@public
    __weak id dragDelegate;
    __weak id dropDelegate;
    BOOL didSetDragInteractionEnabled;
    BOOL dragInteractionEnabled;
}
@end

@implementation CharonDragDropBox
@end

static const char CharonDragDropKey;

static CharonDragDropBox *charon_box(id object)
{
    CharonDragDropBox *box = objc_getAssociatedObject(object, &CharonDragDropKey);
    if (!box) {
        box = [[CharonDragDropBox alloc] init];
        objc_setAssociatedObject(object, &CharonDragDropKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return box;
}

static BOOL charon_enabled(id object)
{
    CharonDragDropBox *box = objc_getAssociatedObject(object, &CharonDragDropKey);
    return box->didSetDragInteractionEnabled ? box->dragInteractionEnabled : [UIDragInteraction isEnabledByDefault];
}

static void charon_set_enabled(id object, BOOL enabled)
{
    CharonDragDropBox *box = charon_box(object);
    box->didSetDragInteractionEnabled = YES;
    box->dragInteractionEnabled = enabled;
}

@implementation UITableView (CharonDragDrop)

- (id<UITableViewDragDelegate>)dragDelegate
{
    return charon_box(self)->dragDelegate;
}

- (void)setDragDelegate:(id<UITableViewDragDelegate>)delegate
{
    charon_box(self)->dragDelegate = delegate;
}

- (id<UITableViewDropDelegate>)dropDelegate
{
    return charon_box(self)->dropDelegate;
}

- (void)setDropDelegate:(id<UITableViewDropDelegate>)delegate
{
    charon_box(self)->dropDelegate = delegate;
}

- (BOOL)dragInteractionEnabled
{
    return charon_enabled(self);
}

- (void)setDragInteractionEnabled:(BOOL)enabled
{
    charon_set_enabled(self, enabled);
}

- (BOOL)hasActiveDrag
{
    return NO;
}

- (BOOL)hasActiveDrop
{
    return NO;
}

@end

@implementation UICollectionView (CharonDragDrop)

- (id<UICollectionViewDragDelegate>)dragDelegate
{
    return charon_box(self)->dragDelegate;
}

- (void)setDragDelegate:(id<UICollectionViewDragDelegate>)delegate
{
    charon_box(self)->dragDelegate = delegate;
}

- (id<UICollectionViewDropDelegate>)dropDelegate
{
    return charon_box(self)->dropDelegate;
}

- (void)setDropDelegate:(id<UICollectionViewDropDelegate>)delegate
{
    charon_box(self)->dropDelegate = delegate;
}

- (BOOL)dragInteractionEnabled
{
    return charon_enabled(self);
}

- (void)setDragInteractionEnabled:(BOOL)enabled
{
    charon_set_enabled(self, enabled);
}

- (BOOL)hasActiveDrag
{
    return NO;
}

- (BOOL)hasActiveDrop
{
    return NO;
}

@end
