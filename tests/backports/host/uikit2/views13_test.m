#import "views13_scenario.h"

void charon_windowed_run(UIWindow *window)
{
    @autoreleasepool {
        struct {
            const char *cls;
            const char *selector;
        } probes[] = {{"UIView", "transform3D"}, {"UIView", "overrideUserInterfaceStyle"}, {"UIView", "focusGroupIdentifier"}, {"UIViewController", "modalInPresentation"}, {"UISwitch", "preferredStyle"},
                      {"UIPageControl", "indicatorImageForPage:"}, {"UILabel", "lineBreakStrategy"}, {"NSLayoutManager", "usesDefaultHyphenation"}, {"UIDatePicker", "preferredDatePickerStyle"}, {"NSObject", "accessibilityUserInputLabels"},
                      {"UIAccessibilityCustomAction", "actionHandler"}, {"UIScreen", "calibratedLatency"}, {"UISegmentedControl", "selectedSegmentTintColor"}, {"UIResponder", "validateCommand:"}};
        NSMutableArray *others = [NSMutableArray array];
        for (size_t index = 0; index < sizeof(probes) / sizeof(probes[0]); index++) {
            IMP imp = class_getMethodImplementation(objc_getClass(probes[index].cls), sel_registerName(probes[index].selector));
            Dl_info info;
            if (!dladdr((void *)imp, &info) || !info.dli_fname || strstr(info.dli_fname, "UIKit") || strstr(info.dli_fname, "Foundation"))
                [others addObject:[NSString stringWithFormat:@"%s %s", probes[index].cls, probes[index].selector]];
        }
        charon_check(others.count == 0, "the port's members are the ones the classes answer with", [others componentsJoinedByString:@", "]);
        NSString *expected = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:getenv("CHARON_EXPECTED")] encoding:NSUTF8StringEncoding error:NULL];
        ur_agree(@"view, controller, control and accessibility members", views_scenario(), [expected componentsSeparatedByString:@"\n"]);
    }
}
