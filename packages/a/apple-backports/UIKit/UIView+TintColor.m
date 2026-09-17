#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static char charon_tint_color_key;
static char charon_tint_mode_key;

static UIColor *charon_stored_tint(UIView *view)
{
    return objc_getAssociatedObject(view, &charon_tint_color_key);
}

static UIViewTintAdjustmentMode charon_stored_mode(UIView *view)
{
    return (UIViewTintAdjustmentMode)[objc_getAssociatedObject(view, &charon_tint_mode_key) integerValue];
}

static UIColor *charon_default_tint(void)
{
    static UIColor *color;
    if (!color)
        color = [UIColor colorWithRed:0 green:122 / 255.0f blue:1 alpha:1];
    return color;
}

static UIColor *charon_dimmed(UIColor *color)
{
    CGFloat white = 0, alpha = 1;
    if ([color getWhite:&white alpha:&alpha])
        return [UIColor colorWithWhite:white alpha:alpha];
    CGFloat red = 0, green = 0, blue = 0;
    if ([color getRed:&red green:&green blue:&blue alpha:&alpha])
        return [UIColor colorWithWhite:red * 0.299f + green * 0.587f + blue * 0.114f alpha:alpha];
    return color;
}

static void charon_tint_changed(UIView *view, BOOL colorChanged)
{
    [view tintColorDidChange];
    for (UIView *subview in view.subviews) {
        if (colorChanged && charon_stored_tint(subview))
            continue;
        if (!colorChanged && charon_stored_mode(subview) != UIViewTintAdjustmentModeAutomatic)
            continue;
        charon_tint_changed(subview, colorChanged);
    }
}

@implementation UIView (CharonTintColor)

- (UIColor *)tintColor
{
    UIColor *color = nil;
    for (UIView *view = self; view && !color; view = view.superview)
        color = charon_stored_tint(view);
    if (!color)
        color = charon_default_tint();
    return self.tintAdjustmentMode == UIViewTintAdjustmentModeDimmed ? charon_dimmed(color) : color;
}

- (void)setTintColor:(UIColor *)tintColor
{
    objc_setAssociatedObject(self, &charon_tint_color_key, tintColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    charon_tint_changed(self, YES);
}

- (UIViewTintAdjustmentMode)tintAdjustmentMode
{
    for (UIView *view = self; view; view = view.superview) {
        UIViewTintAdjustmentMode mode = charon_stored_mode(view);
        if (mode != UIViewTintAdjustmentModeAutomatic)
            return mode;
    }
    return UIViewTintAdjustmentModeNormal;
}

- (void)setTintAdjustmentMode:(UIViewTintAdjustmentMode)tintAdjustmentMode
{
    objc_setAssociatedObject(self, &charon_tint_mode_key, @(tintAdjustmentMode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    charon_tint_changed(self, NO);
}

- (void)tintColorDidChange
{
}

@end
