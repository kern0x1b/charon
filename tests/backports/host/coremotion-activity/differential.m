// The activity classes of CoreMotion, asked one question per process: the host's own CoreMotion (Catalyst) when built
// without -DPORT, and the port's CMMotionActivity.m and CMMotionActivityManager.m when built with it. The two sides are
// separate processes because both define the same classes; in one process the second to load would win and the port
// would be compared with itself.
//
// Each case is one argv[1] value and prints a fixed set of lines, so run.sh can compare the two sides case by case and a
// crash of one side is attributed to that case alone. Nothing here calls a sensor: the host has none, and the port has
// none to call.
#import <Foundation/Foundation.h>
#import <CoreMotion/CoreMotion.h>
#import <objc/runtime.h>

static NSString *queueKind(NSOperationQueue *passed)
{
    if ([NSOperationQueue currentQueue] == passed)
        return @"passed-queue";
    if ([NSThread isMainThread])
        return @"main-thread";
    return @"other-thread";
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    int which = argc > 1 ? atoi(argv[1]) : -1;
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    __block int calls = 0;
    __block NSString *kind = @"never";
    __block NSError *error = nil;

    switch (which) {
    case 0:
        printf("isActivityAvailable=%d\n", [CMMotionActivityManager isActivityAvailable]);
        printf("authorizationStatus=%ld\n", (long)[CMMotionActivityManager authorizationStatus]);
        break;
    case 1: {
        CMMotionActivityManager *manager = [[CMMotionActivityManager alloc] init];
        [manager startActivityUpdatesToQueue:queue withHandler:^(CMMotionActivity *activity) {
            calls++;
            kind = queueKind(queue);
        }];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:4.0]];
        [manager stopActivityUpdates];
        printf("startActivityUpdates: calls=%d queue=%s\n", calls, [kind UTF8String]);
        break;
    }
    case 2: {
        CMMotionActivityManager *manager = [[CMMotionActivityManager alloc] init];
        [manager queryActivityStartingFromDate:[NSDate dateWithTimeIntervalSinceNow:-3600] toDate:[NSDate date] toQueue:queue
            withHandler:^(NSArray<CMMotionActivity *> *activities, NSError *e) {
                calls++;
                error = e;
                kind = queueKind(queue);
            }];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:4.0]];
        printf("queryActivity: calls=%d queue=%s error=%s\n", calls, [kind UTF8String],
               error ? [[NSString stringWithFormat:@"%@/%ld", error.domain, (long)error.code] UTF8String] : "none");
        break;
    }
    case 3: {
        CMMotionActivityManager *manager = [[CMMotionActivityManager alloc] init];
        [manager stopActivityUpdates];
        printf("stopActivityUpdates: returned\n");
        break;
    }
    case 4: {
        CMMotionActivity *activity = [[CMMotionActivity alloc] init];
        printf("startDate=%.1f\n", [activity.startDate timeIntervalSinceReferenceDate]);
        printf("confidence=%ld\n", (long)activity.confidence);
        printf("unknown=%d stationary=%d walking=%d running=%d automotive=%d cycling=%d\n", activity.unknown,
               activity.stationary, activity.walking, activity.running, activity.automotive, activity.cycling);
        break;
    }
    case 5:
        printf("CMMotionActivity supportsSecureCoding=%d\n", [CMMotionActivity supportsSecureCoding]);
        break;
    case 6: {
        CMMotionActivity *activity = [[CMMotionActivity alloc] init];
        CMMotionActivity *copy = [activity copy];
        printf("copy class=%s startDate=%.1f confidence=%ld unknown=%d\n", class_getName([copy class]),
               [copy.startDate timeIntervalSinceReferenceDate], (long)copy.confidence, copy.unknown);
        break;
    }
    case 7: {
        CMMotionActivity *activity = [[CMMotionActivity alloc] init];
        NSError *e = nil;
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:activity requiringSecureCoding:YES error:&e];
        CMMotionActivity *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[CMMotionActivity class] fromData:data error:&e];
        printf("round trip class=%s unknown=%d confidence=%ld\n", decoded ? class_getName([decoded class]) : "nil",
               decoded.unknown, (long)decoded.confidence);
        break;
    }
    default:
        printf("no such case %d\n", which);
        return 2;
    }
    return 0;
}
