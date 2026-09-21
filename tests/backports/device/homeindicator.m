#import <UIKit/UIKit.h>
#import "check.h"
#import "homeindicator-cases.h"
#import "homeindicator-expectations.h"

static NSString *const results_folder = @"/private/var/backports";

@interface HomeIndicatorDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation HomeIndicatorDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
    [[NSFileManager defaultManager] createDirectoryAtPath:results_folder withIntermediateDirectories:YES attributes:nil error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:[results_folder stringByAppendingPathComponent:@"homeindicator.done"] error:NULL];
    charon_log_to([results_folder stringByAppendingPathComponent:@"homeindicator.log"]);
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[UIViewController alloc] init];
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSDictionary *expected = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:homeindicator_expectations length:strlen(homeindicator_expectations)] options:0 error:NULL];
        NSMutableDictionary *records = [NSMutableDictionary dictionary];
        homeindicator_run(self.window, ^(NSString *name, NSString *value) { records[name] = value; printf("record %s: %s\n", name.UTF8String, value.UTF8String); });
        for (NSString *name in [expected.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            if ([expected[name] isEqualToString:records[name]])
                charon_check(YES, name.UTF8String, nil);
            else
                charon_check(NO, name.UTF8String, [NSString stringWithFormat:@"\n    device %@\n    host   %@", records[name], expected[name]]);
        }
        CHECK_EQUAL(@(records.count), @(expected.count), "the device answers every record the host did and no other");
        UIViewController *root = [[UIViewController alloc] init];
        UIViewController *top = [[UIViewController alloc] init];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:root];
        [navigation pushViewController:top animated:NO];
        CHECK(navigation.childViewControllerForScreenEdgesDeferringSystemGestures == top, "a navigation controller passes the edge gestures to its top view controller, as UIKit 12 does");
        UITabBarController *tabs = [[UITabBarController alloc] init];
        tabs.viewControllers = @[root, top];
        tabs.selectedIndex = 1;
        CHECK(tabs.childViewControllerForScreenEdgesDeferringSystemGestures == top, "and a tab bar controller to the selected one");
        printf("checks=%d failures=%d\n", charon_checks, charon_failures);
        NSString *summary = [NSString stringWithFormat:@"%@ checks=%d failures=%d\n", charon_failures ? @"FAIL" : @"ok", charon_checks, charon_failures];
        [summary writeToFile:[results_folder stringByAppendingPathComponent:@"homeindicator.done"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    });
    return YES;
}

@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([HomeIndicatorDelegate class]));
    }
}
