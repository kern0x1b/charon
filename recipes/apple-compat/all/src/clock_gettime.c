#include <errno.h>
#include <mach/clock.h>
#include <mach/mach.h>
#include <time.h>

__attribute__((visibility("hidden")))
int charon_clock_gettime(clockid_t which, struct timespec *now)
{
    clock_id_t source;
    if (which == CLOCK_REALTIME) {
        source = CALENDAR_CLOCK;
    } else if (which == CLOCK_MONOTONIC || which == CLOCK_MONOTONIC_RAW || which == CLOCK_MONOTONIC_RAW_APPROX ||
               which == CLOCK_UPTIME_RAW || which == CLOCK_UPTIME_RAW_APPROX) {
        source = SYSTEM_CLOCK;
    } else {
        errno = EINVAL;
        return -1;
    }
    host_t host = mach_host_self();
    clock_serv_t service;
    kern_return_t got = host_get_clock_service(host, source, &service);
    mach_port_deallocate(mach_task_self(), host);
    if (got != KERN_SUCCESS) {
        errno = EINVAL;
        return -1;
    }
    mach_timespec_t time;
    kern_return_t read = clock_get_time(service, &time);
    mach_port_deallocate(mach_task_self(), service);
    if (read != KERN_SUCCESS) {
        errno = EINVAL;
        return -1;
    }
    now->tv_sec = time.tv_sec;
    now->tv_nsec = time.tv_nsec;
    return 0;
}
