#import <UIKit/UIKit.h>
#import "check.h"

// on iOS 6 the tint colour of a bar is the colour of the bar itself, which is what iOS 7 calls the bar tint
// colour, so the backport keeps the value it was given and hands it to the iOS 6 tint colour

#define NAMED(...) ([NSString stringWithFormat:__VA_ARGS__].UTF8String)

@interface UINavigationBar (CharonHostBarAppearance)
- (UIColor *)charonHostBarTintColor;
- (void)setCharonHostBarTintColor:(UIColor *)color;
- (UIImage *)charonHostBackIndicatorImage;
- (void)setCharonHostBackIndicatorImage:(UIImage *)image;
- (UIImage *)charonHostBackIndicatorTransitionMaskImage;
- (void)setCharonHostBackIndicatorTransitionMaskImage:(UIImage *)image;
@end

@interface UIToolbar (CharonHostBarTintColor)
- (UIColor *)charonHostBarTintColor;
- (void)setCharonHostBarTintColor:(UIColor *)color;
@end

@interface UITabBar (CharonHostBarTintColor)
- (UIColor *)charonHostBarTintColor;
- (void)setCharonHostBarTintColor:(UIColor *)color;
@end

@interface UISearchBar (CharonHostBarStyle)
- (UISearchBarStyle)charonHostSearchBarStyle;
- (void)setCharonHostSearchBarStyle:(UISearchBarStyle)style;
- (UIColor *)charonHostBarTintColor;
- (void)setCharonHostBarTintColor:(UIColor *)color;
@end

static UIImage *drawn_image(void)
{
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(4, 4), NO, 1);
    [[UIColor redColor] setFill];
    UIRectFill(CGRectMake(0, 0, 4, 4));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

int main(void)
{
    @autoreleasepool {
        UIColor *colour = [UIColor orangeColor];
        UINavigationBar *navigation = [[UINavigationBar alloc] init];
        [navigation setCharonHostBarTintColor:colour];
        charon_check([navigation charonHostBarTintColor] == colour, "the navigation bar keeps its bar tint colour", @"the colour differs");
        charon_check([navigation.tintColor isEqual:colour], "the navigation bar tints itself with it", [NSString stringWithFormat:@"%@", navigation.tintColor]);
        [navigation setCharonHostBarTintColor:nil];
        charon_check([navigation charonHostBarTintColor] == nil, "clearing the bar tint colour", [NSString stringWithFormat:@"%@", [navigation charonHostBarTintColor]]);

        UIImage *image = drawn_image(), *mask = drawn_image();
        [navigation setCharonHostBackIndicatorImage:image];
        [navigation setCharonHostBackIndicatorTransitionMaskImage:mask];
        charon_check([navigation charonHostBackIndicatorImage] == image, "the back indicator image is kept", @"the image differs");
        charon_check([navigation charonHostBackIndicatorTransitionMaskImage] == mask, "the back indicator mask is kept", @"the mask differs");

        UIToolbar *toolbar = [[UIToolbar alloc] init];
        [toolbar setCharonHostBarTintColor:colour];
        charon_check([toolbar charonHostBarTintColor] == colour && [toolbar.tintColor isEqual:colour], "the toolbar bar tint colour", @"the colour differs");
        UITabBar *tabs = [[UITabBar alloc] init];
        [tabs setCharonHostBarTintColor:colour];
        charon_check([tabs charonHostBarTintColor] == colour && [tabs.tintColor isEqual:colour], "the tab bar bar tint colour", @"the colour differs");

        UISearchBar *search = [[UISearchBar alloc] init];
        [search setCharonHostBarTintColor:colour];
        charon_check([search charonHostBarTintColor] == colour && [search.tintColor isEqual:colour], "the search bar bar tint colour", @"the colour differs");
        charon_check([search charonHostSearchBarStyle] == UISearchBarStyleDefault, "the default search bar style", @"the default style differs");
        [search setCharonHostSearchBarStyle:UISearchBarStyleMinimal];
        charon_check([search charonHostSearchBarStyle] == UISearchBarStyleMinimal, "the search bar style is kept", @"the style differs");
        charon_check(search.backgroundImage != nil, "the minimal style clears the iOS 6 bar background", @"the background image is still missing");
        [search setCharonHostSearchBarStyle:UISearchBarStyleProminent];
        charon_check(search.backgroundImage == nil, "leaving the minimal style brings the background back", @"the background image was kept");
        search.backgroundImage = image;
        [search setCharonHostSearchBarStyle:UISearchBarStyleMinimal];
        charon_check(CGSizeEqualToSize(search.backgroundImage.size, image.size), "the minimal style leaves an application background alone",
                     [NSString stringWithFormat:@"%@", NSStringFromCGSize(search.backgroundImage.size)]);
        [search setCharonHostSearchBarStyle:UISearchBarStyleDefault];
        charon_check(CGSizeEqualToSize(search.backgroundImage.size, image.size), "leaving the minimal style leaves an application background alone",
                     [NSString stringWithFormat:@"%@", NSStringFromCGSize(search.backgroundImage.size)]);

        printf("checks=%d failures=%d\n", charon_checks, charon_failures);
        return charon_failures;
    }
}
