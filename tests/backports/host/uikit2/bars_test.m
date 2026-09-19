#import <UIKit/UIKit.h>
#import "check.h"

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

        NSInteger styles[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 15, 16, 255, 256, -1, -2, NSIntegerMin, NSIntegerMax};
        for (size_t index = 0; index < sizeof styles / sizeof *styles; index++) {
            UISearchBar *ours = [[UISearchBar alloc] init], *system = [[UISearchBar alloc] init];
            [ours setCharonHostSearchBarStyle:(UISearchBarStyle)styles[index]];
            system.searchBarStyle = (UISearchBarStyle)styles[index];
            charon_check((NSInteger)[ours charonHostSearchBarStyle] == (NSInteger)system.searchBarStyle, NAMED(@"search bar style %ld reads as the system's", (long)styles[index]),
                         [NSString stringWithFormat:@"%ld != %ld", (long)[ours charonHostSearchBarStyle], (long)system.searchBarStyle]);
        }

        for (unsigned steps = 0; steps < 4096; steps++) {
            UINavigationBar *ours = [[UINavigationBar alloc] init], *system = [[UINavigationBar alloc] init];
            UIImage *pair[2] = {drawn_image(), drawn_image()};
            UIImage *other[2] = {drawn_image(), drawn_image()};
            NSMutableString *trace = [NSMutableString string];
            BOOL same = YES;
            unsigned seed = steps;
            for (int move = 0; move < 6 && same; move++, seed /= 4) {
                int which = (seed >> 0) & 1, clear = (seed >> 1) & 1;
                UIImage *given = clear ? nil : (move % 2 ? other[which] : pair[which]);
                [trace appendFormat:@"%s%s ", which ? "mask" : "image", clear ? "=nil" : (move % 2 ? "'" : "")];
                if (which) {
                    [ours setCharonHostBackIndicatorTransitionMaskImage:given];
                    system.backIndicatorTransitionMaskImage = given;
                } else {
                    [ours setCharonHostBackIndicatorImage:given];
                    system.backIndicatorImage = given;
                }
                same = [ours charonHostBackIndicatorImage] == system.backIndicatorImage && [ours charonHostBackIndicatorTransitionMaskImage] == system.backIndicatorTransitionMaskImage;
            }
            if (!same) {
                charon_check(NO, NAMED(@"the back indicator pair after %@", trace), @"the images differ from the system's");
                break;
            }
            if (steps == 4095)
                charon_check(YES, "the back indicator pair answers as the system's over every order of six changes", @"");
        }

        printf("checks=%d failures=%d\n", charon_checks, charon_failures);
        return charon_failures;
    }
}
