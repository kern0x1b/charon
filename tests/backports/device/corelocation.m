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

@interface CharonLocationProbe : NSObject <CLLocationManagerDelegate>
@property (nonatomic) int updates, failures, states;
@property (nonatomic) NSInteger lastErrorCode;
@property (nonatomic, copy) NSString *lastErrorDomain;
@property (nonatomic) CLRegionState lastState;
@property (nonatomic) NSUInteger lastCount;
@end

@implementation CharonLocationProbe
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations
{
    self.updates++;
    self.lastCount = locations.count;
}
- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    self.failures++;
    self.lastErrorCode = error.code;
    self.lastErrorDomain = error.domain;
}
- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region
{
    self.states++;
    self.lastState = state;
}
@end

@interface CharonSilentDelegate : NSObject <CLLocationManagerDelegate>
@end

@implementation CharonSilentDelegate
@end

static void spin_until(BOOL (^done)(void), NSTimeInterval seconds)
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done() && [limit timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
}

static NSString *raised(void (^block)(void))
{
    @try {
        block();
    } @catch (NSException *exception) {
        return [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason];
    }
    return @"nothing";
}

static void check_single_location(void)
{
    CLLocationManager *bare = [[CLLocationManager alloc] init];
    CharonSilentDelegate *silent = [[CharonSilentDelegate alloc] init];
    bare.delegate = silent;
    NSString *without = raised(^{ [bare requestLocation]; });
    CHECK([without hasPrefix:@"NSInternalInconsistencyException"] && [without containsString:@"locationManager:didUpdateLocations:"],
          "a delegate that cannot take a location is refused");
    CharonLocationProbe *probe = [[CharonLocationProbe alloc] init];
    CLLocationManager *manager = [[CLLocationManager alloc] init];
    manager.delegate = probe;
    manager.desiredAccuracy = kCLLocationAccuracyKilometer;
    [manager requestLocation];
    [manager requestLocation];
    spin_until(^BOOL { return probe.updates + probe.failures > 0; }, 25);
    spin_until(^BOOL { return NO; }, 1);
    CHECK(probe.updates + probe.failures == 1, "a request made while one is outstanding is not a second one");
    if (probe.updates)
        CHECK(probe.lastCount == 1, "a location request delivers one location");
    else
        CHECK([probe.lastErrorDomain isEqualToString:kCLErrorDomain], "a location request that fails fails in the location error domain");
    printf("info requestLocation: updates %d failures %d code %ld domain %s\n", probe.updates, probe.failures,
           (long)probe.lastErrorCode, probe.lastErrorDomain.UTF8String ?: "-");
}

static void check_region_state(void)
{
    CLLocationCoordinate2D center = {37.33, -122.03};
    CLRegion *region = [[CLRegion alloc] initCircularRegionWithCenter:center radius:100 identifier:@"state"];
    CharonLocationProbe *probe = [[CharonLocationProbe alloc] init];
    CLLocationManager *manager = [[CLLocationManager alloc] init];
    manager.delegate = probe;
    manager.desiredAccuracy = kCLLocationAccuracyKilometer;
    CLRegion *none = nil;
    CHECK([raised(^{ [manager requestStateForRegion:none]; }) hasPrefix:@"NSInternalInconsistencyException"], "no region is refused");
    [manager requestStateForRegion:region];
    spin_until(^BOOL { return probe.states > 0; }, 25);
    spin_until(^BOOL { return NO; }, 1);
    CHECK(probe.states == 1, "a region state is answered once");
    CHECK(probe.lastState == CLRegionStateUnknown || probe.lastState == CLRegionStateInside || probe.lastState == CLRegionStateOutside,
          "the state is one of the three");
    printf("info requestStateForRegion: states %d state %ld\n", probe.states, (long)probe.lastState);
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc > 1)
            charon_log_to(@(argv[1]));
        check_regions();
        check_availability();
        check_single_location();
        check_region_state();
        printf("%d checks, %d failed\n", charon_checks, charon_failures);
    }
    return charon_failures;
}
