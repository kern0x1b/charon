#import <objc/runtime.h>
#import "CharonDragDrop.h"

@implementation CharonDragDropBox
@end

static const char CharonDragDropKey;
static BOOL CharonDragInteractionDefault = NO;

CharonDragDropBox *charon_drag_drop_box(id object)
{
    CharonDragDropBox *box = objc_getAssociatedObject(object, &CharonDragDropKey);
    if (!box) {
        box = [[CharonDragDropBox alloc] init];
        objc_setAssociatedObject(object, &CharonDragDropKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return box;
}

// The flag the application set, and NO when it set none. This helper is carried by every band, so it
// names no symbol that only exists from iOS 11: the class default is applied by the drag and drop
// object, which is carried from 6.0, through charon_set_drag_interaction_enabled_default().
BOOL charon_drag_interaction_enabled(id object)
{
    CharonDragDropBox *box = objc_getAssociatedObject(object, &CharonDragDropKey);
    return box && box->didSetDragInteractionEnabled ? box->dragInteractionEnabled : CharonDragInteractionDefault;
}

void charon_set_drag_interaction_enabled_default(BOOL enabled)
{
    CharonDragInteractionDefault = enabled;
}

void charon_set_drag_interaction_enabled(id object, BOOL enabled)
{
    CharonDragDropBox *box = charon_drag_drop_box(object);
    box->didSetDragInteractionEnabled = YES;
    box->dragInteractionEnabled = enabled;
}
