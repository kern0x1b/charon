#import <Foundation/Foundation.h>
#import <MetricKit/MetricKit.h>
#import "metricvalue-cases.h"
#if defined(CHARON_METRICVALUE_PORT)
// The port's own category declarations: how a translation unit outside MetricKit's files sees the
// setters the shared machinery generates for a value. The system half asks the host, not the port.
#import "CharonMetricValue.h"

// The two setters the case fills a value in through. The port generates a setter for every value
// property, in the class's own file, so a translation unit outside those files declares the two it
// needs - which is the same shape CharonValueStore.h's own note and MetricKit's
// MXHistogram (CharonMetricKitSetters) use.
@interface MXCPUMetric (CharonMetricValueCases)
- (void)charon_setValue:(id)value forKey:(NSString *)key;
@end

@interface MXDiagnosticPayload (CharonMetricValueCases)
- (void)charon_setValue:(id)value forKey:(NSString *)key;
@end
#endif

// Two halves, and the honest reason they are not symmetric.
//
// The host half can answer one thing: what the system's own MetricKit writes for a value nothing has
// filled in. Measured on the host's MetricKit.framework, an MXCPUMetric and an MXMetricPayload that
// this process never measured write an empty object - -dictionaryRepresentation has no keys at all and
// -JSONRepresentation is four bytes that parse as {}. That is the whole of the host's answer, and it
// is a real one: the system fills those values and nothing does on the host, which is the same wall
// the device has.
//
// The port half answers the rest, and answers it against the port's own contract: a value the port
// filled in writes exactly the properties its header declares, the JSON is that dictionary, and the
// same value comes back out of the archiver. The port's key spelling is a choice, and the file
// records why: Apple's own keys for a *populated* value could not be measured on the host either,
// because nothing populates a value there.

static void recordRepresentation(CertificateRecorder record, id value)
{
    NSDictionary *dictionary = [value dictionaryRepresentation];
    record(@"empty.keyCount", [NSString stringWithFormat:@"%lu", (unsigned long)dictionary.count]);
    for (NSString *key in [dictionary.allKeys sortedArrayUsingSelector:@selector(compare:)])
        record(([NSString stringWithFormat:@"empty.key.%@", key]), ([dictionary[key] description] ?: @"(none)"));
    NSData *json = [value JSONRepresentation];
    record(@"empty.jsonIsObject", [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL] ? @"1" : @"0");
}

void metricvalue_run(CertificateRecorder record)
{
    recordRepresentation(record, [[MXCPUMetric alloc] init]);
    recordRepresentation(record, [[MXMetricPayload alloc] init]);

#ifdef CHARON_METRICVALUE_PORT

    // A value the port filled in, through the store the shared machinery keeps it in.
    MXCPUMetric *cpu = [[MXCPUMetric alloc] init];
    NSMeasurement *duration = [[NSMeasurement alloc] initWithDoubleValue:1.5
                                                                  unit:[NSUnitDuration seconds]];
    [cpu charon_setValue:duration forKey:@"cumulativeCPUTime"];
    NSDictionary *filled = [cpu dictionaryRepresentation];
    record(@"filled.keyCount", [NSString stringWithFormat:@"%lu", (unsigned long)filled.count]);
    record(@"filled.hasCumulativeCPUTime", (filled[@"cumulativeCPUTime"] ? @"1" : @"0"));
    record(@"filled.cumulativeCPUTime", ([filled[@"cumulativeCPUTime"] description] ?: @"(none)"));
    record(@"filled.unsetIsAbsent", (filled[@"cumulativeCPUInstructions"] ? @"1" : @"0"));
    NSData *json = [cpu JSONRepresentation];
    NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL];
    record(@"filled.jsonKeyCount", [NSString stringWithFormat:@"%lu", (unsigned long)parsed.count]);
    record(@"filled.jsonValue", ([parsed[@"cumulativeCPUTime"] description] ?: @"(none)"));

    // The date conversion, the measurement conversion and the archive round trip.
    MXDiagnosticPayload *payload = [[MXDiagnosticPayload alloc] init];
    NSDate *when = [NSDate dateWithTimeIntervalSinceReferenceDate:1000.5];
    [payload charon_setValue:when forKey:@"timeStampBegin"];
    NSDictionary *payloadDictionary = [payload dictionaryRepresentation];
    record(@"date.value", ([payloadDictionary[@"timeStampBegin"] description] ?: @"(none)"));
    record(@"date.endAbsent", (payloadDictionary[@"timeStampEnd"] ? @"1" : @"0"));

    // Secure coding on both sides, which is the port's declared contract (+supportsSecureCoding is YES)
    // and what decodeObjectOfClasses:forKey: requires: with requiresSecureCoding off it answers nil, and
    // the case would have been reading an empty archive as a round trip that worked.
    NSMutableData *archive = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:archive];
    archiver.requiresSecureCoding = YES;
    [archiver setClassName:NSStringFromClass([cpu class]) forClass:[MXCPUMetric class]];
    // Contained, not a root object: the port's encodeWithCoder: writes the properties and does not write
    // itself under NSKeyedArchiveRootObjectKey, because every archiver in this package stores its
    // objects as contained ones - CoreSpotlight's index does the same. Archiving it the way a caller
    // would is what the round trip is for.
    [archiver encodeObject:cpu forKey:@"payload"];
    [archiver finishEncoding];
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:archive];
    unarchiver.requiresSecureCoding = YES;
    record(@"archive.byteCount", [NSString stringWithFormat:@"%lu", (unsigned long)archive.length]);
    MXCPUMetric *read = nil;
    @try {
        read = [unarchiver decodeObjectOfClasses:[NSSet setWithArray:@[[MXCPUMetric class], [NSString class], [NSNumber class]]]
                                            forKey:@"payload"];
    } @catch (NSException *exception) {
        record(@"archive.raised", exception.reason ?: @"(none)");
    }
    [unarchiver finishDecoding];
    record(@"archive.class", read ? NSStringFromClass([read class]) : @"(nil)");
    NSDictionary *readBack = [read dictionaryRepresentation] ?: @{};
    record(@"archive.keyCount", [NSString stringWithFormat:@"%lu", (unsigned long)readBack.count]);
    record(@"archive.cumulativeCPUTime", ([readBack[@"cumulativeCPUTime"] description] ?: @"(none)"));
    // NOT -isEqual:, which the port does not promise: no MetricKit class in the SDK's headers declares
    // it, so the value objects inherit NSObject's identity and two equal metrics are not -isEqual:. What
    // the port does promise is the representation, and that is what is compared.
    record(@"archive.sameRepresentation",
           ([[read dictionaryRepresentation] isEqualToDictionary:[cpu dictionaryRepresentation]] ? @"1" : @"0"));

    // The walk the M-Z review asked for: the eight properties the port declares and the SDK it builds
    // against does not, plus one ordinary property, each read through KVC on the PORT's own class.
    //
    // The class is named by its SYMBOL, not by a string, and that is the whole difference: the rename
    // header is force-included into this file too, so `@"MXCPUMetric"` would look the HOST's class up -
    // which has an accessor of that name of its own - and the walk would report the port's eight
    // accessors while measuring Apple's nine. Naming the symbol makes the port's class a compile-time
    // requirement, so a class the port does not carry is a build error rather than a silent pass.
    NSArray *pairs = @[
#ifdef CHARON_METRICVALUE_PORT
        @[[MXAnimationMetric class], @"hitchTimeRatio"],
        @[[MXMetaData class], @"bundleIdentifier"],
        @[[MXMetaData class], @"lowPowerModeEnabled"],
        @[[MXMetaData class], @"isTestFlightApp"],
        @[[MXMetaData class], @"pid"],
        @[[MXMetricPayload class], @"diskSpaceUsageMetrics"],
        @[[MXCrashDiagnostic class], @"exceptionReason"],
        @[[MXDiagnostic class], @"signpostData"],
        // and one ordinary property, so the walk is not only about the gaps
        @[[MXCPUMetric class], @"cumulativeCPUTime"],
#endif
    ];
    for (NSArray *pair in pairs) {
        Class cls = pair[0];
        NSString *key = pair[1];
        NSString *who = NSStringFromClass(cls);
        record(([NSString stringWithFormat:@"kvc.%@.%@.class", who, key]), cls ? @"1" : @"0");
        SEL selector = NSSelectorFromString(key);
        BOOL answers = [cls instancesRespondToSelector:selector];
        record(([NSString stringWithFormat:@"kvc.%@.%@.answers", who, key]), answers ? @"1" : @"0");
        if (!answers)
            continue;
        // the read itself: this is the call that raised before, and the selector check is what makes a
        // missing accessor a recorded 0 rather than a crash
        id instance = [[cls alloc] init];
        (void)[instance valueForKey:key];
        record(([NSString stringWithFormat:@"kvc.%@.%@.read", who, key]), (instance ? @"1" : @"0"));
    }
#endif
}
