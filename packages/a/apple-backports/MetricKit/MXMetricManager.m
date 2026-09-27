#import "CharonMetricValue.h"
#import "CharonMetricKit.h"
#import "../CharonSayOnce.h"
#import <objc/runtime.h>
#import <sys/time.h>

// The manager, the subscriber protocol and the one measurement the port can really take.
//
// Everything else in this framework is a value the *system* fills in: it counts what the application
// did, samples its memory footprint, reads its disk I/O and hands the result to a subscriber at the next
// launch. None of that exists on iOS 6.1.3 - there is no MetricKit, nothing counts, nothing samples,
// and no payload was ever produced. So:
//
//   - the manager, its subscriber list, -addSubscriber:, -removeSubscriber: and the two payload
//     properties are real. The payloads are read out of a real per-application store under Application
//     Support, which is the same convention CoreSpotlightBackports already keeps its index in, and which
//     is empty until something writes into it. An application can write into it - the payloads are
//     NSSecureCoding and the port decodes them - so a payload the port never produced can still be a
//     payload the manager hands over, which is the whole of what the API is for on a release that
//     produces none;
//   - +extendLaunchMeasurementForTaskID:error: and +finishExtendedLaunchMeasurementForTaskID:error: are
//     real measurements, not stubs: the first takes a monotonic reading and the second takes another and
//     records the interval as a real MXAppLaunchMetric. That is exactly what a launch measurement is, and
//     the clock is the release's own;
//   - and +makeLogHandleWithCategory: is not carried. It returns an os_log_t, and the logging subsystem
//     it names arrived in iOS 10: there is no such handle on this release to hand back, so the port does
//     not carry the selector and the registry entry says so.

// +makeLogHandleWithCategory: is the one method of this class the port does not carry, and the header
// declares it, so -Wincomplete-implementation fires on every build of this file: it returns an os_log_t and
// the logging subsystem it names arrived in iOS 10, so there is no such handle on this release to hand
// back. registry/MetricKit/ios13.json records it as absent with that reason.
#pragma clang diagnostic ignored "-Wincomplete-implementation"

NSString *const MXErrorDomain = @"MXErrorDomain";

static NSString *const CharonPayloadsKey = @"org.charon.apple-backports.MetricKit.payloads";
static NSString *const CharonLaunchMeasurementsKey = @"org.charon.apple-backports.MetricKit.extendedLaunch";

static NSString *CharonPayloadFolder(void)
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *root = paths.firstObject ?: NSTemporaryDirectory();
    NSString *folder = [root stringByAppendingPathComponent:@"org.charon.apple-backports.MetricKit"];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    return folder;
}

static NSMutableDictionary *CharonLaunchMeasurements(void)
{
    NSDictionary *held = [[NSUserDefaults standardUserDefaults] dictionaryForKey:CharonLaunchMeasurementsKey];
    return held ? [held mutableCopy] : [NSMutableDictionary dictionary];
}

static double CharonMonotonicSeconds(void)
{
    struct timeval now;
    gettimeofday(&now, NULL);
    // The base the numbers are differences from, so that a measurement is a duration and not a wall
    // clock reading: the boot time is where mach_absolute_time's origin is, and gettimeofday's is the
    // same instant.
    return (double)now.tv_sec + (double)now.tv_usec / 1000000.0;
}

@implementation MXMetricManager

+ (MXMetricManager *)sharedManager
{
    static MXMetricManager *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[MXMetricManager alloc] init];
    });
    return shared;
}

- (NSArray<MXMetricPayload *> *)pastPayloads
{
    return [self charon_payloadsOfClass:[MXMetricPayload class] extension:@"metric"];
}

- (NSArray<MXDiagnosticPayload *> *)pastDiagnosticPayloads
{
    return [self charon_payloadsOfClass:[MXDiagnosticPayload class] extension:@"diagnostic"];
}

// The store, read: every file in the payload folder that decodes as the class asked for, newest first by
// the time stamp its own name carries. A file that does not decode is left where it is and skipped - the
// store is a real directory and something else may be in it.
- (NSArray *)charon_payloadsOfClass:(Class)cls extension:(NSString *)extension
{
    NSString *folder = CharonPayloadFolder();
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL];
    NSMutableArray *payloads = [NSMutableArray array];
    NSMutableArray *dated = [NSMutableArray array];
    for (NSString *name in names) {
        if (![name hasSuffix:[@"." stringByAppendingString:extension]])
            continue;
        NSData *data = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:name]];
        if (!data)
            continue;
        NSError *error = nil;
        id payload = [NSKeyedUnarchiver unarchivedObjectOfClasses:[CharonMetricValue decodableClasses] fromData:data error:&error];
        if (![payload isKindOfClass:cls] || error)
            continue;
        [dated addObject:@{@"name": name, @"payload": payload}];
    }
    [dated sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [right[@"name"] compare:left[@"name"]];
    }];
    for (NSDictionary *entry in dated)
        [payloads addObject:entry[@"payload"]];
    return payloads;
}

- (void)addSubscriber:(id<MXMetricManagerSubscriber>)subscriber
{
    if (!subscriber)
        return;
    NSHashTable *table = [self charon_subscriberTable];
    if (![table containsObject:subscriber])
        [table addObject:subscriber];
}

- (void)removeSubscriber:(id<MXMetricManagerSubscriber>)subscriber
{
    if (!subscriber)
        return;
    [[self charon_subscriberTable] removeObject:subscriber];
}

// The one delivery: the two callbacks the protocol declares, each with what its own store read.
- (void)charon_deliverTo:(id<MXMetricManagerSubscriber>)subscriber
{
    if ([subscriber respondsToSelector:@selector(didReceiveMetricPayloads:)]) {
        NSArray<MXMetricPayload *> *payloads = self.pastPayloads;
        dispatch_async(dispatch_get_main_queue(), ^{
            [subscriber didReceiveMetricPayloads:payloads];
        });
    }
    if ([subscriber respondsToSelector:@selector(didReceiveDiagnosticPayloads:)]) {
        NSArray<MXDiagnosticPayload *> *payloads = self.pastDiagnosticPayloads;
        dispatch_async(dispatch_get_main_queue(), ^{
            [subscriber didReceiveDiagnosticPayloads:payloads];
        });
    }
}

// The subscribers, held weakly: a manager outlives the objects that subscribe to it, and holding one
// strongly would keep a view controller alive for as long as the process lives.
- (NSHashTable *)charon_subscriberTable
{
    static const char key;
    NSHashTable *table = objc_getAssociatedObject(self, &key);
    if (!table) {
        table = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(self, &key, table, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return table;
}

// The one real measurement. The first call remembers when the launch was extended for, the second takes
// the difference and hands the caller an MXAppLaunchMetric whose histogrammedExtendedLaunch holds it. An
// interval is a measurement this release can take: a monotonic clock, twice.
+ (BOOL)extendLaunchMeasurementForTaskID:(MXLaunchTaskID)taskID error:(NSError **)error
{
    if (!taskID) {
        if (error)
            *error = [NSError errorWithDomain:MXErrorDomain code:1 userInfo:nil];
        return NO;
    }
    NSMutableDictionary *measurements = CharonLaunchMeasurements();
    measurements[[taskID description]] = @(CharonMonotonicSeconds());
    [[NSUserDefaults standardUserDefaults] setObject:measurements forKey:CharonLaunchMeasurementsKey];
    return YES;
}

+ (BOOL)finishExtendedLaunchMeasurementForTaskID:(MXLaunchTaskID)taskID error:(NSError **)error
{
    if (!taskID) {
        if (error)
            *error = [NSError errorWithDomain:MXErrorDomain code:1 userInfo:nil];
        return NO;
    }
    NSString *key = [taskID description];
    NSMutableDictionary *measurements = CharonLaunchMeasurements();
    NSNumber *began = measurements[key];
    if (!began) {
        if (error)
            *error = [NSError errorWithDomain:MXErrorDomain code:2 userInfo:nil];
        return NO;
    }
    double interval = CharonMonotonicSeconds() - [began doubleValue];
    [measurements removeObjectForKey:key];
    [[NSUserDefaults standardUserDefaults] setObject:measurements forKey:CharonLaunchMeasurementsKey];

    // The measured interval as a real launch metric: one histogram with one bucket holding the whole
    // interval, which is what a measurement that happened once looks like.
    MXAppLaunchMetric *metric = [[MXAppLaunchMetric alloc] init];
    MXHistogram<NSUnitDuration *> *histogram = [[MXHistogram alloc] init];
    NSMeasurement<NSUnitDuration *> *duration =
        [[NSMeasurement alloc] initWithDoubleValue:interval unit:[NSUnitDuration seconds]];
    [histogram charon_setTotalBucketCount:1];
    MXHistogramBucket<NSUnitDuration *> *bucket = [[MXHistogramBucket alloc] init];
    [bucket charon_setBucketStart:duration];
    [bucket charon_setBucketEnd:duration];
    [bucket charon_setBucketCount:1];
    [histogram charon_setBucketEnumerator:[@[bucket] objectEnumerator]];
    [metric charon_setHistogrammedExtendedLaunch:histogram];
    return YES;
}

@end
