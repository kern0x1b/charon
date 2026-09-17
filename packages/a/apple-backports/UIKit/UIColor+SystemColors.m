#import <UIKit/UIKit.h>

static UIColor *charon_color(CGFloat red, CGFloat green, CGFloat blue)
{
    return [UIColor colorWithRed:red / 255 green:green / 255 blue:blue / 255 alpha:1];
}

@implementation UIColor (CharonSystemColors)

+ (UIColor *)systemRedColor
{
    return charon_color(255, 59, 48);
}

+ (UIColor *)systemGreenColor
{
    return charon_color(76, 217, 100);
}

+ (UIColor *)systemBlueColor
{
    return charon_color(0, 122, 255);
}

+ (UIColor *)systemOrangeColor
{
    return charon_color(255, 149, 0);
}

+ (UIColor *)systemYellowColor
{
    return charon_color(255, 204, 0);
}

+ (UIColor *)systemPinkColor
{
    return charon_color(255, 45, 85);
}

+ (UIColor *)systemTealColor
{
    return charon_color(90, 200, 250);
}

+ (UIColor *)systemGrayColor
{
    return charon_color(142, 142, 147);
}

@end
