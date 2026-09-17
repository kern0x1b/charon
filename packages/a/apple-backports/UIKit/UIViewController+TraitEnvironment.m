#import <UIKit/UIKit.h>

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
#import <objc/runtime.h>

@interface UITraitCollection (CharonTraitEnvironment)
+ (UITraitCollection *)charon_traitCollectionForScreen:(UIScreen *)screen;
+ (void)charon_deliverChangesInEnvironments:(NSArray *)environments change:(void (^)(void))change;
@end

static char charon_overrides_key;

@interface UIViewController (CharonTraitEnvironment) <UITraitEnvironment>
@end

@implementation UIViewController (CharonTraitEnvironment)

- (UITraitCollection *)traitCollection
{
    UIViewController *parent = self.parentViewController;
    if (parent) {
        UITraitCollection *inherited = [parent traitCollection];
        UITraitCollection *override = [parent overrideTraitCollectionForChildViewController:self];
        return override ? [UITraitCollection traitCollectionWithTraitsFromCollections:@[inherited, override]] : inherited;
    }
    UIViewController *presenting = self.presentingViewController;
    if (presenting && presenting != self)
        return [presenting traitCollection];
    return [UITraitCollection charon_traitCollectionForScreen:self.isViewLoaded ? self.view.window.screen : nil];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
}

- (void)setOverrideTraitCollection:(UITraitCollection *)collection forChildViewController:(UIViewController *)childViewController
{
    if (!childViewController)
        return;
    NSMapTable *overrides = objc_getAssociatedObject(self, &charon_overrides_key);
    if (!overrides && !collection)
        return;
    if (!overrides) {
        overrides = [NSMapTable weakToStrongObjectsMapTable];
        objc_setAssociatedObject(self, &charon_overrides_key, overrides, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UITraitCollection *stored = [collection copy];
    [UITraitCollection charon_deliverChangesInEnvironments:@[childViewController] change:^{
        if (stored)
            [overrides setObject:stored forKey:childViewController];
        else
            [overrides removeObjectForKey:childViewController];
    }];
}

- (UITraitCollection *)overrideTraitCollectionForChildViewController:(UIViewController *)childViewController
{
    return [objc_getAssociatedObject(self, &charon_overrides_key) objectForKey:childViewController];
}

@end
