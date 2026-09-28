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
- (void)charon_setCumulativeCPUTime:(id)value;
@end

@interface MXDiagnosticPayload (CharonMetricValueCases)
- (void)charon_setTimeStampBegin:(id)value;
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
    [cpu charon_setCumulativeCPUTime:duration];
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
    [payload charon_setTimeStampBegin:when];
    NSDictionary *payloadDictionary = [payload dictionaryRepresentation];
    record(@"date.value", ([payloadDictionary[@"timeStampBegin"] description] ?: @"(none)"));
    record(@"date.endAbsent", (payloadDictionary[@"timeStampEnd"] ? @"1" : @"0"));

    NSMutableData *archive = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:archive];
    [archiver setClassName:NSStringFromClass([cpu class]) forClass:[MXCPUMetric class]];
    [cpu encodeWithCoder:archiver];
    [archiver finishEncoding];
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:archive];
    unarchiver.requiresSecureCoding = NO;
    MXCPUMetric *read = [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
    [unarchiver finishDecoding];
    NSDictionary *readBack = [read dictionaryRepresentation];
    record(@"archive.cumulativeCPUTime", ([readBack[@"cumulativeCPUTime"] description] ?: @"(none)"));
    record(@"archive.equal", ([read isEqual:cpu] ? @"1" : @"0"));
#endif
}
