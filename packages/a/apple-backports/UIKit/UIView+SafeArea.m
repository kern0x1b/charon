#import <UIKit/UIKit.h>

UIEdgeInsets charon_safe_area_insets(UIView *view);
UIEdgeInsets charon_content_overlay_insets(UIViewController *controller, UIView *view);
UIEdgeInsets charon_status_bar_overlap(UIView *view);

static UIEdgeInsets charon_insets_max(UIEdgeInsets one, UIEdgeInsets other)
{
    return UIEdgeInsetsMake(MAX(one.top, other.top), MAX(one.left, other.left),
                            MAX(one.bottom, other.bottom), MAX(one.right, other.right));
}

static UIEdgeInsets charon_insets_in_inner_rect(UIEdgeInsets insets, CGRect outer, CGRect inner)
{
    CGFloat top = MAX(0, CGRectGetMinY(outer) + insets.top - CGRectGetMinY(inner));
    CGFloat left = MAX(0, CGRectGetMinX(outer) + insets.left - CGRectGetMinX(inner));
    CGFloat bottom = MAX(0, CGRectGetMaxY(inner) - (CGRectGetMaxY(outer) - insets.bottom));
    CGFloat right = MAX(0, CGRectGetMaxX(inner) - (CGRectGetMaxX(outer) - insets.right));
    return UIEdgeInsetsMake(MIN(top, CGRectGetHeight(inner)), MIN(left, CGRectGetWidth(inner)),
                            MIN(bottom, CGRectGetHeight(inner)), MIN(right, CGRectGetWidth(inner)));
}

static UIViewController *charon_view_controller(UIView *view)
{
    UIResponder *next = [view nextResponder];
    return [next isKindOfClass:[UIViewController class]] ? (UIViewController *)next : nil;
}

UIEdgeInsets charon_safe_area_insets(UIView *view)
{
    UIView *superview = view.superview;
    if (!superview) {
        if ([view isKindOfClass:[UIWindow class]])
            return charon_status_bar_overlap(view);
        UIViewController *controller = charon_view_controller(view);
        return controller ? charon_content_overlay_insets(controller, view) : UIEdgeInsetsZero;
    }
    UIEdgeInsets outer = charon_safe_area_insets(superview);
    UIViewController *controller = charon_view_controller(superview);
    if (controller)
        outer = charon_insets_max(outer, charon_content_overlay_insets(controller, superview));
    return charon_insets_in_inner_rect(outer, superview.bounds, view.frame);
}

@implementation UIView (CharonSafeArea)

- (UIEdgeInsets)safeAreaInsets
{
    UIViewController *controller = charon_view_controller(self);
    if (controller)
        return charon_insets_max(charon_safe_area_insets(self), charon_content_overlay_insets(controller, self));
    return charon_safe_area_insets(self);
}

@end
