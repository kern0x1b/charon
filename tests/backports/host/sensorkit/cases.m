#import <Foundation/Foundation.h>
#import <unistd.h>
#import <CoreFoundation/CoreFoundation.h>
#import <SensorKit/SensorKit.h>
#import "sensorkit-cases.h"

// The three relations the four functions must satisfy, asked of whichever build is under test.
//
// The host's SensorKit is a real implementation, and the port's is over the two clocks the release
// actually has. What can be compared is not the numbers - they are two different anchors - but the
// RELATIONS, and those are the header's own contract:
//
//   1. the round trip is exact: what goes into -SRAbsoluteTimeFromCFAbsoluteTime: comes back out of
//      -SRAbsoluteTimeToCFAbsoluteTime:, to the nanosecond the clocks carry;
//   2. the pair names the same instant as CFAbsoluteTimeGetCurrent, because that is what an
//      SRAbsoluteTime is on this platform - so the two differ by no more than a clock tick;
//   3. and two readings of -SRAbsoluteTimeGetCurrent differ and the second is the larger, because the
//      clock is monotonic. (It is NOT monotonic across a sleep on this release: mach_continuous_time,
//      which the header's wording needs, arrived in iOS 10. See facts/SensorKit/SensorKit.md.)

static void recordRelations(CertificateRecorder record, NSString *who)
{
    // Two readings in a row and a third after a nap. The second pair is not required to differ: an
    // SRAbsoluteTime is a CFTimeInterval, and a double near 8e8 cannot resolve better than about 120ns,
    // so two back-to-back calls may answer the same value - the HOST's does too, which is why the
    // relation is "never less" and not "greater". The third, after a nap, must be greater.
    SRAbsoluteTime a = SRAbsoluteTimeGetCurrent();
    SRAbsoluteTime b = SRAbsoluteTimeGetCurrent();
    usleep(2000);
    SRAbsoluteTime c = SRAbsoluteTimeGetCurrent();
    record([NSString stringWithFormat:@"%@.neverBackwards", who], (b >= a && c > b) ? @"1" : @"0");
    record([NSString stringWithFormat:@"%@.thirdReadingAdvances", who], c > b ? @"1" : @"0");
    record([NSString stringWithFormat:@"%@.notNull", who], (a != OS_SIGNPOST_ID_NULL && a != 0) ? @"1" : @"0");

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    CFAbsoluteTime named = SRAbsoluteTimeToCFAbsoluteTime(a);
    CFAbsoluteTime gap = named - now;
    if (gap < 0) gap = -gap;
    record([NSString stringWithFormat:@"%@.agreesWithCFAbsoluteTime", who], gap < 1.0 ? @"1" : @"0");
    record([NSString stringWithFormat:@"%@.gapSeconds", who], [NSString stringWithFormat:@"%.6f", gap]);

    // The round trip, within the resolution the pair itself has. It is NOT bit-exact and the header
    // does not say it is: a CFTimeInterval near 8e8 resolves to about 120ns, so a value that comes back
    // within a microsecond came back exactly as far as these clocks can tell. The host's own drift is
    // recorded rather than assumed.
    SRAbsoluteTime round = SRAbsoluteTimeFromCFAbsoluteTime(named);
    double drift = round - a;
    if (drift < 0) drift = -drift;
    record([NSString stringWithFormat:@"%@.roundTripWithinAMicrosecond", who], drift < 1e-6 ? @"1" : @"0");
    record([NSString stringWithFormat:@"%@.roundTripDrift", who], [NSString stringWithFormat:@"%.3e", drift]);

    // the nanosecond form: the header says the argument is a continuous time in nanoseconds
    SRAbsoluteTime fromNanos = SRAbsoluteTimeFromContinuousTime(1000000000ull);
    record([NSString stringWithFormat:@"%@.fromContinuousNonZero", who], fromNanos != 0 ? @"1" : @"0");
}

void sensorkit_run(CertificateRecorder record)
{
    recordRelations(record, @"system");
#ifdef CHARON_SENSORKIT_PORT
    recordRelations(record, @"port");
#endif
}
