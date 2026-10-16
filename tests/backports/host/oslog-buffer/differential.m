// differential.m - the os_log macros' packed buffer, decoded by the port and written as the host's own
// developer output is. The same battery as host/oslog runs in both builds:
//
//   -DCHARON_PORT   the port's decoder answers. The macros call _os_log_impl, which this file defines to
//                   decode the buffer the compiler packed with charon_os_log_format_buffer, and os_log_type_enabled
//                   is the port's answer for the log objects the port makes.
//   (no define)     the host's own os_log answers, through its own _os_log_impl, and writes the developer
//                   output the comparator reads.
//
// The log of each case is named by its index, so the two outputs are read case by case.
#import <Foundation/Foundation.h>
#import <os/log.h>
#include <errno.h>
#include <stdio.h>
#include "battery.h"

#ifdef CHARON_PORT
#include "CharonOSLog.h"

static FILE *ours_file;
static int current_index;

bool os_log_type_enabled(os_log_t log, os_log_type_t type)
{
    return charon_os_log_type_enabled(log, type);
}

void _os_log_impl(void *dso, os_log_t log, os_log_type_t type, const char *format, uint8_t *buffer, uint32_t size)
{
    int error = errno;
    if (!charon_os_log_type_enabled(log, type))
        return;
    char *text = charon_os_log_format_buffer(format, buffer, size, error);
    fprintf(ours_file, "%d\x1f%s%c", current_index, text, 0);
    free(text);
}

#define LOG_FOR(category) charon_os_log_named("probe", category)
#else
#define LOG_FOR(category) os_log_create("probe", category)
#endif

int main(int argc, char **argv)
{
    @autoreleasepool {
#ifdef CHARON_PORT
        ours_file = fopen(argv[1], "wb");
#else
        (void)argc;
        (void)argv;
#endif
        const char *s = "dyn", *nul = NULL;
        NSString *o = @"obj";
        id nilo = nil;
        int i = -7;
        unsigned u = 4000000000u;
        short sh = -5;
        signed char ch = -3;
        long long ll = 1234567890123LL;
        double d = 3.14159265;
        float f = 2.5f;
        void *p = (void *)0x1234;
        size_t z = 99;
        char c = 'q';
        unsigned char uu[16] = {0xde, 0xad, 0xbe, 0xef, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12};
        int index = 0;
#define CASE(format, ...) \
        do { \
            char category[16]; \
            snprintf(category, sizeof category, "c%d", ++index); \
            os_log_t log = LOG_FOR(category); \
            errno = 0; \
            CHARON_CURRENT(index) \
            os_log(log, format, ##__VA_ARGS__); \
        } while (0);
#ifdef CHARON_PORT
#define CHARON_CURRENT(n) current_index = (n);
#else
#define CHARON_CURRENT(n)
#endif
        OSLOG_BATTERY(CASE)
        OSLOG_BATTERY_HOST(CASE)
#ifdef CHARON_PORT
        fclose(ours_file);
#endif
        printf("%d cases\n", index);
    }
    return 0;
}
