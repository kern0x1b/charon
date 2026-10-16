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
#include <string.h>
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

// The formats of the buffers the macros never make (see CRAFT in main). Each is one call, one category.
#define OSLOG_CRAFTED(CASE) \
    CASE("a %d b %d c") \
    CASE("a %s b") \
    CASE("a %@ b") \
    CASE("a %f b") \
    CASE("a %m b") \
    CASE("a %.2s b") \
    CASE("a %c b")

/* A buffer built item by item at run time, for the buffers the macros never make. A pointer item points at this
   process's own data, so both runs read the same bytes. The host decodes the buffer with its own _os_log_impl. */
static uint8_t crafted[256];
static uint32_t crafted_size;

static void craft_begin(void)
{
    crafted[0] = 0x02;
    crafted[1] = 0;
    crafted_size = 2;
}

static void craft_item(unsigned type, unsigned privacy, const void *data, uint8_t length)
{
    crafted[crafted_size++] = (uint8_t)((type << 4) | privacy);
    crafted[crafted_size++] = length;
    memcpy(crafted + crafted_size, data, length);
    crafted_size += length;
    crafted[1]++;
}

static void craft_value(unsigned type, unsigned privacy, uint64_t value, uint8_t length)
{
    craft_item(type, privacy, &value, length);
}

static void craft_pointer(unsigned type, unsigned privacy, const void *target)
{
    craft_item(type, privacy, &target, sizeof target);
}

static void craft_count(uint32_t count)
{
    craft_item(1, 0, &count, sizeof count);
}

/* Sets the item count the buffer claims, whatever items it holds. */
static void craft_claim(uint8_t count)
{
    crafted[1] = count;
}

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
        /* A buffer that holds no item, which no os_log macro makes: the host writes its markers for it, and the
           port's decoder must write the same. The call is made on _os_log_impl directly, as a caller would. */
#define CRAFT(format) \
        do { \
            char category[16]; \
            snprintf(category, sizeof category, "c%d", ++index); \
            os_log_t log = LOG_FOR(category); \
            static const uint8_t empty[2] = {0x00, 0x00}; \
            CHARON_CURRENT(index) \
            _os_log_impl(&__dso_handle, log, OS_LOG_TYPE_DEFAULT, format, (uint8_t *)empty, sizeof empty); \
        } while (0);
        OSLOG_BATTERY(CASE)
        OSLOG_BATTERY_HOST(CASE)
        OSLOG_CRAFTED(CRAFT)
        /* Items of a kind the conversion does not take: the host writes its mismatch marker, consumes the item, and
           goes on to the next conversion, which takes the next item. The privacy nibbles, the sizes and the labels
           are the ones measured on the host. The arguments after the format are the items, in order. */
#define CRAFT_CASE(format, ...) \
        do { \
            char category[16]; \
            snprintf(category, sizeof category, "c%d", ++index); \
            os_log_t log = LOG_FOR(category); \
            errno = 0; \
            craft_begin(); \
            __VA_ARGS__; \
            CHARON_CURRENT(index) \
            _os_log_impl(&__dso_handle, log, OS_LOG_TYPE_DEFAULT, format, crafted, crafted_size); \
        } while (0);
        /* A string the host writes as private at nibble 0 is one in writable memory: the array below is on the stack. */
        char writable[] = "dyn";
        CRAFT_CASE("v %d w", craft_pointer(2, 0, writable))
        CRAFT_CASE("v %m w", craft_value(6, 0, 0, 4))
        CRAFT_CASE("v %d w", craft_value(0, 0, 1, 8))
        CRAFT_CASE("v %d w", craft_value(0, 0, 7, 4))
        CRAFT_CASE("v %d w %d x", craft_pointer(2, 0, s), craft_value(0, 0, 7, 4))
        CRAFT_CASE("v %d w %d x", craft_value(0, 0, 9, 8), craft_value(0, 0, 7, 4))
        CRAFT_CASE("v %s w", craft_pointer(2, 0, s))
        CRAFT_CASE("v %s w", craft_pointer(4, 0, (__bridge const void *)o))
        CRAFT_CASE("v %s w", craft_value(0, 0, 4, 4))
        CRAFT_CASE("v %s w", craft_pointer(3, 0, uu))
        CRAFT_CASE("v %@ w", craft_pointer(2, 0, s))
        CRAFT_CASE("v %@ w", craft_value(0, 0, 9, 8))
        CRAFT_CASE("v %d w", craft_pointer(2, 2, s))
        CRAFT_CASE("v %d w", craft_pointer(2, 3, s))
        CRAFT_CASE("v %d w", craft_pointer(2, 4, s))
        CRAFT_CASE("v %d w", craft_pointer(4, 1, (__bridge const void *)o))
        CRAFT_CASE("v %d w", craft_value(0, 3, 1, 8))
        CRAFT_CASE("v %d w", craft_count(3))
        CRAFT_CASE("v %.3P w", craft_count(3), craft_pointer(2, 0, s))
        CRAFT_CASE("v %.3P w", craft_count(3), craft_pointer(3, 0, uu))
        CRAFT_CASE("v %P w", craft_pointer(3, 0, uu))
        CRAFT_CASE("v %P w", (void)0)
        CRAFT_CASE("v %s w", craft_value(6, 0, 1, 4))
        CRAFT_CASE("v %d w", craft_value(6, 0, 1, 8))
        CRAFT_CASE("v %{public}s w", craft_value(0, 0, 1, 4))
        CRAFT_CASE("v %5d w", craft_pointer(3, 0, uu))
        CRAFT_CASE("v %d w %d x", craft_value(7, 0, 1, 8), craft_value(0, 0, 7, 4))
        /* A zero-length scalar is an item with no value; a zero-length errno item is still errno. */
        CRAFT_CASE("v %d w", craft_value(0, 0, 0, 0))
        CRAFT_CASE("v %d w %d x", craft_value(0, 0, 0, 0), craft_value(0, 0, 7, 4))
        CRAFT_CASE("v %d w %d x", craft_value(0, 0, 7, 4), craft_value(0, 0, 0, 0))
        CRAFT_CASE("v %d w", craft_value(6, 0, 0, 0))
        CRAFT_CASE("v %m w", craft_value(6, 0, 0, 0))
        /* NULL strings and objects: the size is 0, and a NULL string at nibble 0 has no privacy word. */
        CRAFT_CASE("v %d w", craft_pointer(2, 0, NULL))
        CRAFT_CASE("v %d w", craft_pointer(2, 2, NULL))
        CRAFT_CASE("v %s w", craft_pointer(2, 0, NULL))
        CRAFT_CASE("v %d w", craft_pointer(4, 0, NULL))
        CRAFT_CASE("v %s w", craft_pointer(4, 0, NULL))
        /* A buffer that claims more items than it holds: the decoder stops at the bytes it has. */
        CRAFT_CASE("v %d w %d x", craft_value(0, 0, 7, 4), craft_claim(2))
        CRAFT_CASE("v %d w %d x", craft_value(0, 0, 7, 4), craft_claim(3))
        CRAFT_CASE("v %d w %d x", craft_value(0, 0, 7, 4), craft_value(0, 0, 0, 0), craft_claim(2))
        CRAFT_CASE("v %d w", craft_value(7, 0, 1, 8))
#ifdef CHARON_PORT
        fclose(ours_file);
#endif
        printf("%d cases\n", index);
    }
    return 0;
}
