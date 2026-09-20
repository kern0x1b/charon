#import "controlmenus_scenario.h"

void charon_windowed_run(UIWindow *window)
{
    @autoreleasepool {
        Class ourAction = NSClassFromString(@"CharonHostUIAction"), ourMenu = NSClassFromString(@"CharonHostUIMenu");
        charon_check(ourAction && ourMenu, "the port's classes are linked under their host names", @"missing");
        NSString *expected = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:getenv("CHARON_EXPECTED")] encoding:NSUTF8StringEncoding error:NULL];
        ur_agree(@"control menus, bar button items and segmented controls", menu_scenario(ourAction, ourMenu), [expected componentsSeparatedByString:@"\n"]);
    }
}
