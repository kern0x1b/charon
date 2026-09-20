#import "controlmenus_scenario.h"

void charon_windowed_run(UIWindow *window)
{
    @autoreleasepool {
        NSArray *lines = menu_scenario([UIAction class], [UIMenu class]);
        [[lines componentsJoinedByString:@"\n"] writeToFile:[NSString stringWithUTF8String:getenv("CHARON_EXPECTED")] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
}
