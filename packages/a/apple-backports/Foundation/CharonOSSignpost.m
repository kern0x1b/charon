#import "CharonOSSignpost.h"
#import "CharonOSLog.h"
#import <mach/mach_time.h>

// The four functions of signpost.h that a TU can call, and the store they record into. Everything else
// in that header is a macro over these, so carrying these four carries the whole family: the
// interval_begin / interval_end / event_emit macros, os_signpost_emit_with_type, and the
// _os_signpost_emit_with_name_impl shape the macros call.

@implementation CharonSignpostInterval

@synthesize name = _name;
@synthesize subsystem = _subsystem;
@synthesize category = _category;
@synthesize seconds = _seconds;
@synthesize count = _count;

@end

@implementation CharonSignpostSnapshot
@synthesize intervals = _intervals;
@end

@implementation CharonSignpostStore

// The intervals, in the order they ended, and the begins still open keyed by their id.
static NSMutableArray<CharonSignpostInterval *> *charon_intervals(void)
{
    static NSMutableArray *intervals;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        intervals = [NSMutableArray array];
    });
    return intervals;
}

static NSMutableDictionary<NSNumber *, NSMutableDictionary *> *charon_open(void)
{
    static NSMutableDictionary *open;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        open = [NSMutableDictionary dictionary];
    });
    return open;
}

// A monotonic reading, which is what an interval is a difference of. mach_absolute_time counts from the
// boot, and the timebase it counts in is one nanosecond on every release this port runs on; the
// conversion is done through the port's own log format, which already reads a monotonic clock.
static NSTimeInterval charon_monotonic(void)
{
    static mach_timebase_info_data_t info;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        mach_timebase_info(&info);
    });
    uint64_t now = mach_absolute_time();
    long double seconds = ((long double)now * info.numer) / (long double)info.denom / 1e9L;
    return (NSTimeInterval)seconds;
}

static CharonSignpostInterval *charon_begin_record(NSDictionary *begin, const char *name)
{
    CharonSignpostInterval *interval = [[CharonSignpostInterval alloc] init];
    interval.name = name && *name ? @(name) : @"";
    interval.subsystem = begin[@"subsystem"] ?: @"";
    interval.category = begin[@"category"] ?: @"";
    interval.seconds = 0.0;
    interval.count = 1;
    return interval;
}

// The snapshot, and the one pointer that is the snapshot: the same object every time, so a caller
// that keeps the pointer and reads it later reads a snapshot that is still the one it was given.
+ (CharonSignpostSnapshot *)snapshot
{
    static CharonSignpostSnapshot *snapshot;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        snapshot = [[CharonSignpostSnapshot alloc] init];
    });
    snapshot.intervals = [self intervals];
    return snapshot;
}

+ (void *)snapshotPointer
{
    return (__bridge void *)[[self snapshot] copy];
}

+ (void)takePointer:(void *)pointer forInterval:(CharonSignpostInterval *)interval
{
    // The public field the mark carries, kept with the interval so that a snapshot and a signpost are
    // the same fact: the signpost the application marked points at the snapshot the metrics came from.
    [interval setValue:(__bridge id)pointer forKey:@"CharonSignpostSnapshot"];
}

+ (NSArray<CharonSignpostInterval *> *)intervals
{
    @synchronized (charon_intervals()) {
        return [charon_intervals() copy];
    }
}

+ (void)recordBeginFor:(os_signpost_id_t)spid log:(os_log_t)log name:(const char *)name
{
    // The open record carries the log's own subsystem and category, so an interval is attributed to
    // the handle that marked it - which is where an interval belongs when it is read back.
    CharonOSLog *handle = (CHARON_OS_LOG_BRIDGE CharonOSLog *)log;
    NSMutableDictionary *begin = [NSMutableDictionary dictionary];
    begin[@"subsystem"] = handle && handle->_subsystem ? @(handle->_subsystem) : @"";
    begin[@"category"] = handle && handle->_category ? @(handle->_category) : @"";
    begin[@"at"] = @(charon_monotonic());
    begin[@"name"] = name && *name ? @(name) : @"";
    @synchronized (charon_open()) {
        charon_open()[@(spid)] = begin;
    }
}

+ (void)recordEndFor:(os_signpost_id_t)spid log:(os_log_t)log name:(const char *)name
{
    NSDictionary *begin = nil;
    @synchronized (charon_open()) {
        begin = charon_open()[@(spid)];
        if (begin)
            [charon_open() removeObjectForKey:@(spid)];
    }
    if (!begin)
        return;
    CharonSignpostInterval *interval = charon_begin_record(begin, [begin[@"name"] UTF8String]);
    interval.seconds = charon_monotonic() - [begin[@"at"] doubleValue];
    interval.name = name && *name ? @(name) : interval.name;
    @synchronized (charon_intervals()) {
        [charon_intervals() addObject:interval];
    }
}

+ (void)recordEventFor:(os_signpost_id_t)spid log:(os_log_t)log name:(const char *)name
{
    CharonOSLog *handle = (CHARON_OS_LOG_BRIDGE CharonOSLog *)log;
    NSDictionary *begin = @{ @"subsystem": handle && handle->_subsystem ? @(handle->_subsystem) : @"",
                             @"category": handle && handle->_category ? @(handle->_category) : @"" };
    CharonSignpostInterval *event = charon_begin_record(begin, name);
    event.seconds = 0.0;
    event.count = 1;
    @synchronized (charon_intervals()) {
        [charon_intervals() addObject:event];
    }
}

+ (void)reset
{
    @synchronized (charon_open()) {
        [charon_open() removeAllObjects];
    }
    @synchronized (charon_intervals()) {
        [charon_intervals() removeAllObjects];
    }
}

@end

// The ids. OS_SIGNPOST_ID_NULL is zero and must never come back from a generate, so the counter starts
// at one and every value carries the high bit that distinguishes a generated id from a pointer's - the
// distinction signpost.h draws between the two id sources, and one the emit path below relies on.
static os_signpost_id_t charon_next_id(void)
{
    static uint64_t counter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        counter = 1;
    });
    uint64_t value;
    @synchronized ([CharonSignpostStore class]) {
        value = counter++;
    }
    return (os_signpost_id_t)(value | (1ull << 63));
}

os_signpost_id_t os_signpost_id_generate(os_log_t log)
{
    return charon_next_id();
}

os_signpost_id_t os_signpost_id_make_with_pointer(os_log_t log, const void *ptr)
{
    if (!ptr)
        return OS_SIGNPOST_ID_NULL;
    return (os_signpost_id_t)((uintptr_t)ptr & ~(1ull << 63));
}

bool os_signpost_enabled(os_log_t log)
{
    // A signpost is a developer mark, and the port's log records everything it is handed at fault and
    // above and keeps every signpost interval, so a mark is always worth making. Returning true is
    // also what the macros above us: with this false, os_signpost_emit_with_type would compile the
    // format away and nothing would ever be recorded.
    return true;
}

void _os_signpost_emit_with_name_impl(void *dso, os_log_t log, os_signpost_type_t type, os_signpost_id_t spid,
                                     const char *name, const char *format, uint8_t *buf, uint32_t size)
{
    if (spid == OS_SIGNPOST_ID_NULL)
        return;
    switch (type) {
        case OS_SIGNPOST_INTERVAL_BEGIN:
            [CharonSignpostStore recordBeginFor:spid log:log name:name];
            break;
        case OS_SIGNPOST_INTERVAL_END:
            [CharonSignpostStore recordEndFor:spid log:log name:name];
            break;
        case OS_SIGNPOST_EVENT:
            [CharonSignpostStore recordEventFor:spid log:log name:name];
            break;
        default:
            break;
    }
}
