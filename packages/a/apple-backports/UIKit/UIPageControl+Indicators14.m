#import "CharonMenus.h"
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

static const char charon_images_key, charon_preferred_key, charon_continuous_key, charon_background_key;

static void charon_check_page(UIPageControl *control, NSInteger page)
{
    if (page < 0 || page >= control.numberOfPages)
        [NSException raise:NSInternalInconsistencyException format:@"Page (%ld) must be within 0 and %ld.", (long)page, (long)control.numberOfPages];
}

@implementation UIPageControl (CharonIndicators14)

- (UIImage *)indicatorImageForPage:(NSInteger)page
{
    charon_check_page(self, page);
    return [objc_getAssociatedObject(self, &charon_images_key) objectForKey:@(page)];
}

- (void)setIndicatorImage:(UIImage *)image forPage:(NSInteger)page
{
    charon_check_page(self, page);
    if (image)
        charon_menus_say_once(@"page-indicator", @"UIPageControl indicator images: iOS 6 draws the dots of a page control itself, so the images are kept and read back and the dots are drawn as before");
    NSMutableDictionary *held = objc_getAssociatedObject(self, &charon_images_key);
    if (!held) {
        held = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, &charon_images_key, held, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (image)
        held[@(page)] = image;
    else
        [held removeObjectForKey:@(page)];
}

- (UIImage *)preferredIndicatorImage
{
    return objc_getAssociatedObject(self, &charon_preferred_key);
}

- (void)setPreferredIndicatorImage:(UIImage *)preferredIndicatorImage
{
    objc_setAssociatedObject(self, &charon_preferred_key, preferredIndicatorImage, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)allowsContinuousInteraction
{
    NSNumber *held = objc_getAssociatedObject(self, &charon_continuous_key);
    return held ? held.boolValue : YES;
}

- (void)setAllowsContinuousInteraction:(BOOL)allowsContinuousInteraction
{
    objc_setAssociatedObject(self, &charon_continuous_key, @(allowsContinuousInteraction), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (UIPageControlBackgroundStyle)backgroundStyle
{
    return (UIPageControlBackgroundStyle)[objc_getAssociatedObject(self, &charon_background_key) integerValue];
}

- (void)setBackgroundStyle:(UIPageControlBackgroundStyle)backgroundStyle
{
    objc_setAssociatedObject(self, &charon_background_key, @(backgroundStyle), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (UIPageControlInteractionState)interactionState
{
    return UIPageControlInteractionStateNone;
}

@end
