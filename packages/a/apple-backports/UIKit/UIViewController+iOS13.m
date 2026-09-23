#import "CharonMenus.h"
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

static const char charon_style_key, charon_modal_key;

@implementation UIViewController (CharonThirteen)

- (UIUserInterfaceStyle)overrideUserInterfaceStyle
{
    return (UIUserInterfaceStyle)[objc_getAssociatedObject(self, &charon_style_key) integerValue];
}

- (void)setOverrideUserInterfaceStyle:(UIUserInterfaceStyle)overrideUserInterfaceStyle
{
    if (overrideUserInterfaceStyle == UIUserInterfaceStyleDark)
        charon_menus_say_once(@"dark-override", @"overrideUserInterfaceStyle: iOS 6 has one appearance, the light one, so a dark override is kept and read back and changes neither the traits nor what is drawn");
    objc_setAssociatedObject(self, &charon_style_key, @(overrideUserInterfaceStyle), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)isModalInPresentation
{
    return [objc_getAssociatedObject(self, &charon_modal_key) boolValue];
}

/* Read by the sheet (UISheetPresentationController.m), which a drag or a tap on its dimming
   view then does not dismiss. */
- (void)setModalInPresentation:(BOOL)modalInPresentation
{
    objc_setAssociatedObject(self, &charon_modal_key, @(modalInPresentation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)performsActionsWhilePresentingModally
{
    id configured = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UIViewControllerPerformsActionsWhilePresentingModally"];
    return [configured respondsToSelector:@selector(boolValue)] ? [configured boolValue] : YES;
}

@end
