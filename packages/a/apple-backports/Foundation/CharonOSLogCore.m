#import "CharonOSLog.h"
#include <asl.h>
#import <objc/runtime.h>

@implementation CharonOSLog

- (instancetype)initWithSubsystem:(const char *)subsystem category:(const char *)category
{
    if ((self = [super init])) {
        _subsystem = strdup(subsystem);
        _category = strdup(category);
    }
    return self;
}

@end

static void *charon_os_log_self(id self, SEL command)
{
    return (__bridge void *)self;
}

static void charon_os_log_keep(id self, SEL command)
{
}

static NSUInteger charon_os_log_count(id self, SEL command)
{
    return NSUIntegerMax;
}

__attribute__((constructor)) static void charon_os_log_prepare(void)
{
    Class cls = [CharonOSLog class];
    class_replaceMethod(cls, sel_registerName("retain"), (IMP)charon_os_log_self, "@@:");
    class_replaceMethod(cls, sel_registerName("autorelease"), (IMP)charon_os_log_self, "@@:");
    class_replaceMethod(cls, sel_registerName("release"), (IMP)charon_os_log_keep, "Vv@:");
    class_replaceMethod(cls, sel_registerName("retainCount"), (IMP)charon_os_log_count, "I@:");
}

os_log_t charon_os_log_named(const char *subsystem, const char *category)
{
    static NSMutableDictionary *logs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        logs = [NSMutableDictionary dictionary];
    });
    NSString *key = [NSString stringWithFormat:@"%s%c%s", subsystem, 0, category];
    @synchronized (logs) {
        CharonOSLog *log = logs[key];
        if (!log) {
            log = [[CharonOSLog alloc] initWithSubsystem:subsystem category:category];
            logs[key] = log;
        }
        return log;
    }
}

BOOL charon_os_log_type_enabled(os_log_t log, os_log_type_t type)
{
    return log && type != OS_LOG_TYPE_INFO && type != OS_LOG_TYPE_DEBUG;
}

void charon_os_log_send(os_log_t log, os_log_type_t type, const char *format, va_list arguments, int error)
{
    char *text = charon_os_log_format(format, arguments, error);
    CharonOSLog *named = (CharonOSLog *)log;
    const char *category = named->_category && *named->_category ? named->_category : NULL;
    int level = type == OS_LOG_TYPE_FAULT ? ASL_LEVEL_CRIT : type == OS_LOG_TYPE_ERROR ? ASL_LEVEL_ERR : ASL_LEVEL_NOTICE;
    aslmsg message = asl_new(ASL_TYPE_MSG);
    if (named->_subsystem && *named->_subsystem)
        asl_set(message, ASL_KEY_FACILITY, named->_subsystem);
    asl_log(NULL, message, level, "%s%s%s%s", category ? "[" : "", category ?: "", category ? "] " : "", text);
    asl_free(message);
    free(text);
}
