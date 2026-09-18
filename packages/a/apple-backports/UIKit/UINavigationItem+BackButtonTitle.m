#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static const char CharonBackButtonTitleKey, CharonBackButtonItemKey;

@implementation UINavigationItem (CharonBackButtonTitle)

- (NSString *)backButtonTitle
{
    return objc_getAssociatedObject(self, &CharonBackButtonTitleKey);
}

- (void)setBackButtonTitle:(NSString *)backButtonTitle
{
    objc_setAssociatedObject(self, &CharonBackButtonTitleKey, backButtonTitle, OBJC_ASSOCIATION_COPY_NONATOMIC);

    UIBarButtonItem *held = self.backBarButtonItem;
    UIBarButtonItem *made = objc_getAssociatedObject(self, &CharonBackButtonItemKey);
    if (held && held != made)
        return;

    UIBarButtonItem *item = nil;
    if (backButtonTitle)
        item = [[UIBarButtonItem alloc] initWithTitle:backButtonTitle style:UIBarButtonItemStylePlain target:nil action:NULL];
    objc_setAssociatedObject(self, &CharonBackButtonItemKey, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.backBarButtonItem = item;
}

@end
