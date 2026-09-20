#import <UIKit/UIKit.h>
#include <dlfcn.h>
#import "check.h"

static NSString *const results_folder = @"/private/var/backports";

static BOOL wait_until(BOOL (^done)(void), NSTimeInterval seconds)
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done() && [limit timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    return done();
}

static UIColor *pixel_of(UIImage *image)
{
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    unsigned char data[4] = {0};
    CGContextRef context = CGBitmapContextCreate(data, 1, 1, 8, 4, space, kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), image.CGImage);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    return [UIColor colorWithRed:data[0] / 255.0 green:data[1] / 255.0 blue:data[2] / 255.0 alpha:data[3] / 255.0];
}

@interface CharonBarsDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation CharonBarsDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
    charon_log_to([results_folder stringByAppendingPathComponent:@"barsapp.log"]);
    UIViewController *root = [[UIViewController alloc] init];
    root.title = @"Bars";
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:root];
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = navigation;
    [self.window makeKeyAndVisible];
    [self performSelector:@selector(runAndReport) withObject:nil afterDelay:0.5];
    return YES;
}

- (void)runAndReport
{
    @try {
        [self run];
    } @catch (NSException *exception) {
        charon_check(NO, "the checks raise no exception", [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]);
    }
    NSString *summary = [NSString stringWithFormat:@"%@ checks=%d failures=%d\n", charon_failures ? @"FAIL" : @"ok", charon_checks, charon_failures];
    [summary writeToFile:[results_folder stringByAppendingPathComponent:@"barsapp.done"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (void)run
{
    Dl_info info;
    CHECK(dladdr((__bridge const void *)[UINavigationBarAppearance class], &info) && !strcmp(strrchr(info.dli_fname, '/') + 1, "libUIKitBackports.dylib"), "UINavigationBarAppearance comes from the backports library");
    UINavigationController *navigation = (UINavigationController *)self.window.rootViewController;
    UINavigationBar *bar = navigation.navigationBar;
    CHECK(bar.standardAppearance != nil && bar.compactAppearance == nil, "a navigation bar has a standard appearance and no compact one at first");

    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = [UIColor redColor];
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName: [UIColor greenColor], NSFontAttributeName: [UIFont boldSystemFontOfSize:20]};
    bar.standardAppearance = appearance;
    UIImage *background = [bar backgroundImageForBarMetrics:UIBarMetricsDefault];
    CHECK(background != nil, "a background colour becomes a background image of the bar");
    UIColor *seen = pixel_of(background);
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    [seen getRed:&red green:&green blue:&blue alpha:&alpha];
    CHECK(red > 0.95 && green < 0.05 && blue < 0.05 && alpha > 0.95, "of that colour");
    NSDictionary *title = bar.titleTextAttributes;
    CHECK([title[UITextAttributeTextColor] isEqual:[UIColor greenColor]] && [title[UITextAttributeFont] isKindOfClass:[UIFont class]], "the title attributes reach the bar, translated for iOS 6");

    UINavigationBarAppearance *compact = [[UINavigationBarAppearance alloc] init];
    [compact configureWithOpaqueBackground];
    compact.backgroundColor = [UIColor blueColor];
    bar.compactAppearance = compact;
    UIImage *landscape = [bar backgroundImageForBarMetrics:UIBarMetricsLandscapePhone];
    UIColor *blueSeen = landscape ? pixel_of(landscape) : nil;
    [blueSeen getRed:&red green:&green blue:&blue alpha:&alpha];
    CHECK(landscape != nil && blue > 0.95 && red < 0.05, "the compact appearance goes to the landscape metrics");
    UIImage *again = [bar backgroundImageForBarMetrics:UIBarMetricsDefault];
    CHECK(again != nil, "and leaves the default metrics as they were");

    UINavigationBarAppearance *changed = bar.standardAppearance;
    changed.backgroundColor = [UIColor yellowColor];
    CHECK(wait_until(^BOOL {
        CGFloat r = 0, g = 0, b = 0, a = 0;
        [pixel_of([bar backgroundImageForBarMetrics:UIBarMetricsDefault]) getRed:&r green:&g blue:&b alpha:&a];
        return r > 0.95 && g > 0.95 && b < 0.05;
    }, 5), "a change to the appearance the bar keeps is applied on a later turn");

    bar.standardAppearance = nil;
    CHECK(bar.standardAppearance != nil, "setting nil brings the default back");

    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    [self.window.rootViewController.view addSubview:toolbar];
    UIToolbarAppearance *toolbarAppearance = [[UIToolbarAppearance alloc] init];
    [toolbarAppearance configureWithOpaqueBackground];
    toolbarAppearance.backgroundColor = [UIColor purpleColor];
    toolbar.standardAppearance = toolbarAppearance;
    UIImage *toolbarImage = [toolbar backgroundImageForToolbarPosition:UIToolbarPositionAny barMetrics:UIBarMetricsDefault];
    CHECK(toolbarImage != nil, "a toolbar's background colour becomes its background image");

    UITabBar *tabBar = [[UITabBar alloc] initWithFrame:CGRectMake(0, 100, 320, 49)];
    [self.window.rootViewController.view addSubview:tabBar];
    UITabBarAppearance *tabAppearance = [[UITabBarAppearance alloc] init];
    [tabAppearance configureWithOpaqueBackground];
    tabAppearance.backgroundColor = [UIColor orangeColor];
    tabAppearance.selectionIndicatorImage = [UIImage imageNamed:@"missing"];
    tabBar.standardAppearance = tabAppearance;
    CHECK(tabBar.backgroundImage != nil, "a tab bar's background colour becomes its background image");
    CHECK(![tabBar respondsToSelector:NSSelectorFromString(@"compactAppearance")], "a tab bar has no compact appearance");
}

@end

int main(int argc, char *argv[])
{
    @autoreleasepool {
        [[NSFileManager defaultManager] createDirectoryAtPath:results_folder withIntermediateDirectories:YES attributes:nil error:NULL];
        return UIApplicationMain(argc, argv, nil, @"CharonBarsDelegate");
    }
}
