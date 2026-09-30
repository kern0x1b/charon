// UIKit26_4.m - the 26.4 band's one member.
//
// ONE OBJECT, ONE RELEASE: 26.4, on its own.  A reader is the only thing that would notice this in
// UIKit26_0.m, because release-split reads band points only.

#import "CharonUIKit26.h"
#import <objc/runtime.h>

// UITextInput.unobscuredContentRect: a protocol property, so the accessor goes on NSObject - a category
// cannot be on a protocol - and the value is a CGRect the port holds.
//
// THE ROW FOR THIS ONE IS OWED, not carried, and this file says why: the queue dates the member 26.4 and
// the SDK 26.2 surface does NOT declare it, so there is no header here to read the declaration from, and
// a property carried on a remembered signature would be a guess with a symbol on it.  See
// coordination/api-queue.md.
@implementation NSObject (CharonUIKit26_4)

static char CharonTextInputUnobscuredContentRectKey;

- (CGRect)unobscuredContentRect
{
    NSValue *boxed = objc_getAssociatedObject(self, &CharonTextInputUnobscuredContentRectKey);
    CGRect rect = CGRectZero;
    if (boxed != nil)
        [boxed getValue:&rect];
    return rect;
}
- (void)setUnobscuredContentRect:(CGRect)rect
{
    objc_setAssociatedObject(self, &CharonTextInputUnobscuredContentRectKey,
                             [NSValue valueWithBytes:&rect objCType:@encode(CGRect)],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end
