#import <Foundation/Foundation.h>
#import <os/log.h>
#import <os/signpost.h>

// The signpost family of iOS 12, over this port's own os_log, and the store the intervals land in.
//
// A signpost is a software mark: an application says "this interval began" and "it ended", with a name
// and a format, and the system shows the intervals in Instruments. Nothing about it is hardware, and
// the release's cache carries none of it - `_os_signpost_emit_with_name_impl`, `os_signpost_enabled`,
// `os_signpost_id_generate` and `os_signpost_id_make_with_pointer` are all absent from the armv7 6.1.3
// cache - while this package already carries the log they sit on (registry/Foundation/oslog.json,
// Foundation/OSLog9.m and OSLog10.m). So the family is here, over that log, and it *records* what it
// is told: the intervals an application marks are kept, and MetricKit's signpost metrics are read out
// of the same store (MXMetricManager.m, -_MXSignpostMetricsSnapshot). That is what makes the family
// worth carrying rather than a set of stubs: the mark an application makes is measurable afterwards.

// The port's own record of one signpost interval, keyed by the id that began it. `name` is the
// signpost's name, `subsystem` and `category` the log's, and `seconds` the interval's length - a
// monotonic difference taken between the two emits, which is the whole of what an interval is.
@interface CharonSignpostInterval : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *subsystem;
@property (nonatomic, copy) NSString *category;
@property (nonatomic, assign) NSTimeInterval seconds;
@property (nonatomic, assign) NSUInteger count;
@end
@interface CharonSignpostInterval (CharonSynthesis)
@end

// Every interval the process has emitted, oldest first, and the store they are read from. This is the
// port's own API - a Charon-prefixed class and two functions - so the registry has nothing to describe
// and an application cannot mistake it for Apple's.
// The snapshot the private MetricKit function hands to the signpost stream: the intervals as they
// stand, as one object, so that the pointer `_MXSignpostMetricsSnapshot` returns is a real snapshot
// rather than a valid address. MetricKit's own macros append a public `signpost:metrics` field to
// every signpost it emits and pass this pointer as that field's one argument, so the port records the
// pointer on the intervals it takes and a snapshot and an interval are the same thing seen twice.
@interface CharonSignpostSnapshot : NSObject
@property (nonatomic, copy) NSArray<CharonSignpostInterval *> *intervals;
@end

@interface CharonSignpostStore : NSObject
+ (NSArray<CharonSignpostInterval *> *)intervals;
+ (CharonSignpostSnapshot *)snapshot;
+ (void *)snapshotPointer;
+ (void)takePointer:(void *)pointer forInterval:(CharonSignpostInterval *)interval;
+ (void)recordBeginFor:(os_signpost_id_t)spid log:(os_log_t)log name:(const char *)name;
+ (void)recordEndFor:(os_signpost_id_t)spid log:(os_log_t)log name:(const char *)name;
+ (void)recordEventFor:(os_signpost_id_t)spid log:(os_log_t)log name:(const char *)name;
+ (void)reset;
@end
