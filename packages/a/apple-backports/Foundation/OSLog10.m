#import "CharonOSLog.h"

#undef os_log_create

os_log_t os_log_create(const char *subsystem, const char *category)
{
    return charon_os_log_named(subsystem, category);
}

bool os_log_type_enabled(os_log_t log, os_log_type_t type)
{
    return charon_os_log_type_enabled(log, type);
}
