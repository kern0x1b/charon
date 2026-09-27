/*
 * The few pieces of C every file of this library needs. See CharonNWSupport.h for why this is C.
 */

#include "CharonNWSupport.h"

#include <arpa/inet.h>
#include <netdb.h>
#include <mach/mach_time.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <ctype.h>
#include <string.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

char *charon_nw_copy_cstring(const char *text)
{
    if (!text)
        return NULL;
    size_t length = strlen(text) + 1;
    char *copy = malloc(length);
    if (copy)
        memcpy(copy, text, length);
    return copy;
}

CFStringRef charon_nw_cfstring(const char *text)
{
    if (!text)
        return NULL;
    return CFStringCreateWithCString(kCFAllocatorDefault, text, kCFStringEncodingUTF8);
}

CFDataRef charon_nw_sockaddr_data(const struct sockaddr *address, socklen_t length)
{
    if (!address || !length)
        return NULL;
    return CFDataCreate(kCFAllocatorDefault, (const UInt8 *)address, (CFIndex)length);
}

const struct sockaddr *charon_nw_sockaddr_of(CFDataRef data, socklen_t *length)
{
    if (!data)
        return NULL;
    CFIndex size = CFDataGetLength(data);
    if (size < (CFIndex)sizeof(struct sockaddr))
        return NULL;
    const struct sockaddr *address = malloc((size_t)size);
    if (!address)
        return NULL;
    CFDataGetBytes(data, CFRangeMake(0, size), (UInt8 *)address);
    if (length)
        *length = (socklen_t)size;
    return address;
}

socklen_t charon_nw_sockaddr_length(const struct sockaddr *address)
{
    if (!address)
        return 0;
    switch (address->sa_family) {
    case AF_INET:
        return sizeof(struct sockaddr_in);
    case AF_INET6:
        return sizeof(struct sockaddr_in6);
#ifdef AF_UNIX
    case AF_UNIX:
        return sizeof(struct sockaddr_un);
#endif
    default:
        return (socklen_t)address->sa_len;
    }
}

bool charon_nw_sockaddr_text(const struct sockaddr *address, char *out, size_t size)
{
    if (!address || !out || !size)
        return false;
    out[0] = 0;
    if (address->sa_family == AF_INET) {
        const struct sockaddr_in *v4 = (const struct sockaddr_in *)address;
        return inet_ntop(AF_INET, &v4->sin_addr, out, (socklen_t)size) != NULL;
    }
    if (address->sa_family == AF_INET6) {
        const struct sockaddr_in6 *v6 = (const struct sockaddr_in6 *)address;
        return inet_ntop(AF_INET6, &v6->sin6_addr, out, (socklen_t)size) != NULL;
    }
#ifdef AF_UNIX
    if (address->sa_family == AF_UNIX) {
        const struct sockaddr_un *unix = (const struct sockaddr_un *)address;
        if (!unix->sun_path[0])
            return false;
        snprintf(out, size, "%s", unix->sun_path);
        return true;
    }
#endif
    return false;
}

uint16_t charon_nw_sockaddr_port(const struct sockaddr *address)
{
    if (!address)
        return 0;
    if (address->sa_family == AF_INET)
        return ntohs(((const struct sockaddr_in *)address)->sin_port);
    if (address->sa_family == AF_INET6)
        return ntohs(((const struct sockaddr_in6 *)address)->sin6_port);
    return 0;
}

bool charon_nw_host_is_address(const char *host, uint16_t port, CFDataRef *out_address)
{
    if (!host || !*host)
        return false;
    struct in_addr v4;
    if (inet_pton(AF_INET, host, &v4) == 1) {
        struct sockaddr_in address;
        memset(&address, 0, sizeof address);
        address.sin_len = sizeof address;
        address.sin_family = AF_INET;
        address.sin_addr = v4;
        address.sin_port = htons(port);
        if (out_address)
            *out_address = charon_nw_sockaddr_data((const struct sockaddr *)&address, sizeof address);
        return true;
    }
    struct in6_addr v6;
    if (inet_pton(AF_INET6, host, &v6) == 1) {
        struct sockaddr_in6 address;
        memset(&address, 0, sizeof address);
        address.sin6_len = sizeof address;
        address.sin6_family = AF_INET6;
        address.sin6_addr = v6;
        address.sin6_port = htons(port);
        if (out_address)
            *out_address = charon_nw_sockaddr_data((const struct sockaddr *)&address, sizeof address);
        return true;
    }
    return false;
}

bool charon_nw_split_url(const char *url, CFStringRef *out_host, uint16_t *out_port)
{
    if (!url)
        return false;
    const char *rest = strstr(url, "://");
    rest = rest ? rest + 3 : url;
    const char *authority = rest;
    while (*rest && *rest != '/' && *rest != '?' && *rest != '#')
        rest++;
    size_t length = (size_t)(rest - authority);
    char *text = malloc(length + 1);
    if (!text)
        return false;
    memcpy(text, authority, length);
    text[length] = 0;

    char *userinfo = strchr(text, '@');
    char *host = userinfo ? userinfo + 1 : text;
    /* An IPv6 literal is written in brackets, and its colons are not the port's: the brackets are
       part of the text of the URL and not part of the host. */
    char *closing = host[0] == '[' ? strchr(host, ']') : NULL;
    char *port = NULL;
    if (closing) {
        *closing = 0;
        if (host[0] == '[')
            memmove(host, host + 1, strlen(host));
        port = closing[1] == ':' ? closing + 2 : NULL;
    } else {
        port = strrchr(host, ':');
        if (port)
            *port++ = 0;
    }
    bool ok = host[0] != 0;
    if (ok && out_host) {
        *out_host = charon_nw_cfstring(host);
        if (!*out_host)
            ok = false;
    }
    if (ok && out_port) {
        *out_port = port ? (uint16_t)atoi(port) : 0;
    }
    free(text);
    return ok;
}

CFStringRef charon_nw_url_host(const char *url)
{
    CFStringRef host = NULL;
    if (!charon_nw_split_url(url, &host, NULL))
        return NULL;
    return host;
}

uint16_t charon_nw_url_port(const char *url)
{
    uint16_t port = 0;
    if (!charon_nw_split_url(url, NULL, &port))
        return 0;
    return port;
}

bool charon_nw_resolve_port(const char *text, uint16_t *out)
{
    if (!text || !*text)
        return false;
    char *end = NULL;
    long number = strtol(text, &end, 10);
    if (end && *end == 0 && number >= 0 && number <= UINT16_MAX) {
        if (out)
            *out = (uint16_t)number;
        return true;
    }
    /* A name: the system's own services file is what says what "http" is, and it is the same file the
       system's resolver uses, so the answer here is the one a release that has Network gives. */
    struct servent *service = getservbyname(text, "tcp");
    if (!service)
        return false;
    long value = ntohs((uint16_t)service->s_port);
    if (value < 0 || value > UINT16_MAX)
        return false;
    if (out)
        *out = (uint16_t)value;
    return true;
}

uint16_t charon_nw_default_port_for_scheme(const char *url)
{
    if (!url)
        return 0;
    const char *separator = strstr(url, "://");
    if (!separator)
        return 0;
    size_t length = (size_t)(separator - url);
    if (!length || length > 31)
        return 0;
    char scheme[32];
    memcpy(scheme, url, length);
    scheme[length] = 0;
    for (size_t index = 0; index < length; index++)
        scheme[index] = (char)tolower((unsigned char)scheme[index]);
    struct servent *service = getservbyname(scheme, "tcp");
    if (!service)
        return 0;
    return ntohs((uint16_t)service->s_port);
}

uint64_t charon_nw_uptime_milliseconds(void)
{
    static mach_timebase_info_data_t base;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        mach_timebase_info(&base);
    });
    uint64_t ticks = mach_absolute_time();
    if (base.denom == 0)
        return 0;
    /* nanoseconds -> milliseconds, without a 128-bit multiply: the quotient and the remainder are
       scaled apart, which is exact and cannot overflow before the device has run for years. */
    uint64_t quotient = ticks / base.denom, remainder = ticks % base.denom;
    uint64_t nanoseconds = quotient * base.numer + (remainder * base.numer) / base.denom;
    return nanoseconds / 1000000;
}

void charon_nw_set_number(CFMutableDictionaryRef values, const char *key, double value)
{
    if (!values || !key)
        return;
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, kCFNumberDoubleType, &value);
    if (!number)
        return;
    CFDictionarySetValue(values, charon_nw_cfstring(key), number);
    CFRelease(number);
}

double charon_nw_number(CFDictionaryRef values, const char *key, double fallback)
{
    if (!values || !key)
        return fallback;
    CFStringRef name = charon_nw_cfstring(key);
    if (!name)
        return fallback;
    CFTypeRef held = CFDictionaryGetValue(values, name);
    CFRelease(name);
    double value = fallback;
    if (!held || CFGetTypeID(held) != CFNumberGetTypeID())
        return fallback;
    CFNumberGetValue((CFNumberRef)held, kCFNumberDoubleType, &value);
    return value;
}

void charon_nw_set_flag(CFMutableDictionaryRef values, const char *key, bool value)
{
    charon_nw_set_number(values, key, value ? 1.0 : 0.0);
}

bool charon_nw_flag(CFDictionaryRef values, const char *key, bool fallback)
{
    return charon_nw_number(values, key, fallback ? 1.0 : 0.0) != 0.0;
}

void charon_nw_set_integer(CFMutableDictionaryRef values, const char *key, int64_t value)
{
    if (!values || !key)
        return;
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &value);
    if (!number)
        return;
    CFDictionarySetValue(values, charon_nw_cfstring(key), number);
    CFRelease(number);
}

int64_t charon_nw_integer(CFDictionaryRef values, const char *key, int64_t fallback)
{
    if (!values || !key)
        return fallback;
    CFStringRef name = charon_nw_cfstring(key);
    if (!name)
        return fallback;
    CFTypeRef held = CFDictionaryGetValue(values, name);
    CFRelease(name);
    int64_t value = 0;
    if (!held || CFGetTypeID(held) != CFNumberGetTypeID())
        return fallback;
    if (!CFNumberGetValue((CFNumberRef)held, kCFNumberSInt64Type, &value))
        return fallback;
    return value;
}
