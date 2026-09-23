#import <Foundation/Foundation.h>
#import <os/log.h>
#include <stdarg.h>

// os/object.h makes os_log_t an Objective-C object, and declares the protocol
// OS_os_log, only where OS_OBJECT_USE_OBJC is on: from a deployment target of
// iOS 6.0. Below it os_log_t is a plain struct os_log_s pointer, and a
// CharonOSLog crosses it with a __bridge cast. No ownership moves either way:
// every CharonOSLog lives as long as the process.
#if OS_OBJECT_USE_OBJC
#define CHARON_OS_LOG_BRIDGE
@interface CharonOSLog : NSObject <OS_os_log> {
#else
#define CHARON_OS_LOG_BRIDGE __bridge
@interface CharonOSLog : NSObject {
#endif
@public
    const char *_subsystem;
    const char *_category;
}
@end

os_log_t charon_os_log_named(const char *subsystem, const char *category);
BOOL charon_os_log_type_enabled(os_log_t log, os_log_type_t type);
void charon_os_log_send(os_log_t log, os_log_type_t type, const char *format, va_list arguments, int error);
char *charon_os_log_format(const char *format, va_list arguments, int error);
