#import <UIKit/UIKit.h>

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

@interface UITraitCollection (CharonTraitEnvironment)
+ (UITraitCollection *)charon_traitCollectionForScreen:(UIScreen *)screen;
@end

@interface UIView (CharonTraitEnvironment) <UITraitEnvironment>
@end

@implementation UIView (CharonTraitEnvironment)

- (UITraitCollection *)traitCollection
{
    for (UIView *view = self; view; view = view.superview) {
        UIResponder *next = view.nextResponder;
        if ([next isKindOfClass:[UIViewController class]] && ((UIViewController *)next).view == view)
            return [(UIViewController *)next traitCollection];
    }
    UIWindow *window = [self isKindOfClass:[UIWindow class]] ? (UIWindow *)self : self.window;
    return [UITraitCollection charon_traitCollectionForScreen:window.screen];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
}

@end
