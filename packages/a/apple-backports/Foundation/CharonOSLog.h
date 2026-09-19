#import <Foundation/Foundation.h>
#import <os/log.h>
#include <stdarg.h>

@interface CharonOSLog : NSObject <OS_os_log> {
@public
    const char *_subsystem;
    const char *_category;
}
@end

os_log_t charon_os_log_named(const char *subsystem, const char *category);
BOOL charon_os_log_type_enabled(os_log_t log, os_log_type_t type);
void charon_os_log_send(os_log_t log, os_log_type_t type, const char *format, va_list arguments, int error);
char *charon_os_log_format(const char *format, va_list arguments, int error);
