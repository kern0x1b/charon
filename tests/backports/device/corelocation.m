#import <CoreLocation/CoreLocation.h>
#include <dlfcn.h>
#import "check.h"

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static NSString *image_of(Class cls)
{
    Dl_info info;
    return dladdr((__bridge const void *)cls, &info) ? @(info.dli_fname).lastPathComponent : @"?";
}

static void check_regions(void)
{
    CLLocationCoordinate2D center = {37.33, -122.03}, far = {40, -100};
    Class circular = NSClassFromString(@"CLCircularRegion");
    CHECK(circular != Nil, "CLCircularRegion exists");
    CHECK_EQUAL(image_of(circular), @"libCoreLocationBackports.dylib", "CLCircularRegion comes from the backports");
    CLCircularRegion *region = [[CLCircularRegion alloc] initWithCenter:center radius:250 identifier:@"own"];
    CHECK([region isKindOfClass:[CLRegion class]], "a circular region is a region");
    CHECK_EQUAL(NSStringFromClass([region class]), @"CLCircularRegion", "the class of a circular region");
    CHECK(region.radius == 250, "the radius");
    CHECK(region.center.latitude == 37.33 && region.center.longitude == -122.03, "the centre");
    CHECK_EQUAL(region.identifier, @"own", "the identifier");
    CHECK([region containsCoordinate:center], "it contains its centre");
    CHECK(![region containsCoordinate:far], "it does not contain a far coordinate");
    CHECK_EQUAL(NSStringFromClass([[region copy] class]), @"CLCircularRegion", "a copy is a circular region again");
    CHECK(region.notifyOnEntry && region.notifyOnExit, "both notify flags start YES");
    region.notifyOnEntry = NO;
    CHECK(!region.notifyOnEntry && region.notifyOnExit, "notifyOnEntry answers what was set and leaves the exit flag alone");
    region.notifyOnExit = NO;
    CHECK(!region.notifyOnEntry && !region.notifyOnExit, "notifyOnExit answers what was set");
    CLRegion *plain = [[CLRegion alloc] initCircularRegionWithCenter:center radius:100 identifier:@"plain"];
    CHECK_EQUAL(NSStringFromClass([plain class]), @"CLRegion", "a region of the release keeps its own class");
    CHECK(plain.radius == 100 && [plain containsCoordinate:center] && ![plain containsCoordinate:far], "a region of the release answers as before");
    CHECK(plain.notifyOnEntry && plain.notifyOnExit, "a region of the release gets the notify flags too, YES to start");
}

static void check_availability(void)
{
    Class circular = NSClassFromString(@"CLCircularRegion");
    BOOL monitoring = [CLLocationManager regionMonitoringAvailable];
    CHECK([CLLocationManager isMonitoringAvailableForClass:circular] == monitoring, "circular monitoring is the release's region monitoring");
    CHECK([CLLocationManager isMonitoringAvailableForClass:[CLRegion class]] == monitoring, "plain region monitoring is the release's region monitoring");
    CHECK(![CLLocationManager isMonitoringAvailableForClass:[NSString class]], "a class that is no region is not monitorable");
    Class none = Nil;
    CHECK(![CLLocationManager isMonitoringAvailableForClass:none], "no class is not monitorable");
    CHECK(![CLLocationManager isRangingAvailable], "ranging is not available");
    CLLocationManager *manager = [[CLLocationManager alloc] init];
    CHECK([manager.rangedRegions isKindOfClass:[NSSet class]] && manager.rangedRegions.count == 0, "no region is ranged");
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc > 1)
            charon_log_to(@(argv[1]));
        check_regions();
        check_availability();
        printf("%d checks, %d failed\n", charon_checks, charon_failures);
    }
    return charon_failures;
}
