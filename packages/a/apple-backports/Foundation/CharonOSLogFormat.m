#import "CharonOSLog.h"
#include <errno.h>
#include <signal.h>
#include <sys/stat.h>
#include <time.h>
#include <wchar.h>

typedef struct {
    char *bytes;
    size_t length;
    size_t capacity;
} CharonText;

typedef struct {
    char flags[8];
    int width;
    int precision;
    char length[3];
    BOOL isBool, isBOOL, isErrno, isTime, isMode, isSignal, isUUID;
} CharonSpec;

static void text_append(CharonText *text, const char *bytes, size_t length)
{
    if (text->length + length + 1 > text->capacity) {
        text->capacity = (text->length + length + 1) * 2;
        text->bytes = realloc(text->bytes, text->capacity);
    }
    memcpy(text->bytes + text->length, bytes, length);
    text->length += length;
    text->bytes[text->length] = 0;
}

static void text_appendf(CharonText *text, const char *format, ...)
{
    char buffer[256];
    va_list arguments, again;
    va_start(arguments, format);
    va_copy(again, arguments);
    int written = vsnprintf(buffer, sizeof buffer, format, arguments);
    va_end(arguments);
    if (written > 0 && (size_t)written < sizeof buffer) {
        text_append(text, buffer, (size_t)written);
    } else if (written > 0) {
        char *large = malloc((size_t)written + 1);
        vsnprintf(large, (size_t)written + 1, format, again);
        text_append(text, large, (size_t)written);
        free(large);
    }
    va_end(again);
}

static BOOL has_flag(const CharonSpec *spec, char flag)
{
    return strchr(spec->flags, flag) != NULL;
}

static void text_padded(CharonText *text, const CharonSpec *spec, const char *bytes)
{
    size_t length = strlen(bytes);
    if (spec->precision > 0 && (size_t)spec->precision < length)
        length = (size_t)spec->precision;
    size_t padding = spec->width > 0 && (size_t)spec->width > length ? (size_t)spec->width - length : 0;
    char fill = has_flag(spec, '0') && !has_flag(spec, '-') ? '0' : ' ';
    for (size_t index = 0; !has_flag(spec, '-') && index < padding; index++)
        text_append(text, &fill, 1);
    text_append(text, bytes, length);
    for (size_t index = 0; has_flag(spec, '-') && index < padding; index++)
        text_append(text, " ", 1);
}

static long long fetch_signed(va_list *arguments, const CharonSpec *spec)
{
    if (!strcmp(spec->length, "hh"))
        return (signed char)va_arg(*arguments, int);
    if (!strcmp(spec->length, "h"))
        return (short)va_arg(*arguments, int);
    if (!strcmp(spec->length, "l"))
        return va_arg(*arguments, long);
    if (!strcmp(spec->length, "z") || !strcmp(spec->length, "t"))
        return va_arg(*arguments, long);
    if (!strcmp(spec->length, "ll") || !strcmp(spec->length, "q") || !strcmp(spec->length, "j"))
        return va_arg(*arguments, long long);
    return va_arg(*arguments, int);
}

static unsigned long long fetch_unsigned(va_list *arguments, const CharonSpec *spec)
{
    if (!strcmp(spec->length, "hh"))
        return (unsigned char)va_arg(*arguments, int);
    if (!strcmp(spec->length, "h"))
        return (unsigned short)va_arg(*arguments, int);
    if (!strcmp(spec->length, "l") || !strcmp(spec->length, "z") || !strcmp(spec->length, "t"))
        return va_arg(*arguments, unsigned long);
    if (!strcmp(spec->length, "ll") || !strcmp(spec->length, "q") || !strcmp(spec->length, "j"))
        return va_arg(*arguments, unsigned long long);
    return va_arg(*arguments, unsigned int);
}

static void spec_string(const CharonSpec *spec, char conversion, char *out, size_t size, const char *length)
{
    size_t used = (size_t)snprintf(out, size, "%%%s", spec->flags);
    if (spec->width > 0)
        used += (size_t)snprintf(out + used, size - used, "%d", spec->width);
    if (spec->precision >= 0)
        used += (size_t)snprintf(out + used, size - used, ".%d", spec->precision);
    snprintf(out + used, size - used, "%s%c", length, conversion);
}

static void append_mode(CharonText *text, unsigned mode)
{
    char string[11] = "----------";
    switch (mode & S_IFMT) {
    case S_IFDIR: string[0] = 'd'; break;
    case S_IFLNK: string[0] = 'l'; break;
    case S_IFCHR: string[0] = 'c'; break;
    case S_IFBLK: string[0] = 'b'; break;
    case S_IFSOCK: string[0] = 's'; break;
    case S_IFIFO: string[0] = 'p'; break;
    default: break;
    }
    static const unsigned bits[9] = {S_IRUSR, S_IWUSR, S_IXUSR, S_IRGRP, S_IWGRP, S_IXGRP, S_IROTH, S_IWOTH, S_IXOTH};
    static const char letters[9] = {'r', 'w', 'x', 'r', 'w', 'x', 'r', 'w', 'x'};
    for (int index = 0; index < 9; index++)
        if (mode & bits[index])
            string[index + 1] = letters[index];
    if (mode & S_ISUID)
        string[3] = string[3] == 'x' ? 's' : 'S';
    if (mode & S_ISGID)
        string[6] = string[6] == 'x' ? 's' : 'S';
    if (mode & S_ISVTX)
        string[9] = string[9] == 'x' ? 't' : 'T';
    text_append(text, string, 10);
}

static void append_integer(CharonText *text, const CharonSpec *spec, char conversion, va_list *arguments, int error)
{
    BOOL isSigned = conversion == 'd' || conversion == 'i';
    long long signedValue = isSigned ? fetch_signed(arguments, spec) : 0;
    unsigned long long unsignedValue = isSigned ? 0 : fetch_unsigned(arguments, spec);
    if (spec->isBool || spec->isBOOL) {
        BOOL truth = isSigned ? signedValue != 0 : unsignedValue != 0;
        text_padded(text, &(CharonSpec){.width = spec->width, .precision = -1},
                    spec->isBool ? (truth ? "true" : "false") : (truth ? "YES" : "NO"));
        return;
    }
    if (spec->isErrno) {
        int code = (int)(isSigned ? signedValue : unsignedValue);
        text_appendf(text, "[%d: %s]", code, code == 0 ? "Success" : strerror(code));
        return;
    }
    if (spec->isTime) {
        time_t seconds = (time_t)(isSigned ? signedValue : unsignedValue);
        struct tm local;
        char formatted[64];
        if (localtime_r(&seconds, &local) && strftime(formatted, sizeof formatted, "%Y-%m-%d %H:%M:%S%z", &local))
            text_append(text, formatted, strlen(formatted));
        return;
    }
    if (spec->isMode) {
        append_mode(text, (unsigned)(isSigned ? signedValue : unsignedValue));
        return;
    }
    if (spec->isSignal) {
        int code = (int)(isSigned ? signedValue : unsignedValue);
        if (code > 0 && code < NSIG)
            text_appendf(text, "[sig%s: %s]", sys_signame[code], sys_siglist[code]);
        else
            text_appendf(text, "[%d: Unknown signal]", code);
        return;
    }
    char format[32];
    spec_string(spec, conversion, format, sizeof format, "ll");
    if (isSigned)
        text_appendf(text, format, signedValue);
    else
        text_appendf(text, format, unsignedValue);
    (void)error;
}

static void append_bytes(CharonText *text, const CharonSpec *spec, const unsigned char *bytes, int length)
{
    if (spec->isUUID && length == 16) {
        text_appendf(text, "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X", bytes[0], bytes[1], bytes[2], bytes[3], bytes[4],
                     bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]);
        return;
    }
    text_append(text, "'", 1);
    for (int index = 0; index < length; index++)
        text_appendf(text, index ? " %02X" : "%02X", bytes[index]);
    text_append(text, "'", 1);
}

static NSString *description_of(id object)
{
    @try {
        return [object description];
    } @catch (NSException *exception) {
        return nil;
    }
}

static void parse_decorators(const char **cursor, CharonSpec *spec)
{
    const char *close = strchr(*cursor, '}');
    if (!close)
        return;
    const char *token = *cursor + 1;
    while (token <= close) {
        const char *end = token;
        while (end < close && *end != ',')
            end++;
        size_t length = (size_t)(end - token);
        if (length == 4 && !strncmp(token, "bool", 4))
            spec->isBool = YES;
        else if (length == 4 && !strncmp(token, "BOOL", 4))
            spec->isBOOL = YES;
        else if (length == 5 && !strncmp(token, "errno", 5))
            spec->isErrno = YES;
        else if (length == 12 && !strncmp(token, "darwin.errno", 12))
            spec->isErrno = YES;
        else if (length == 6 && !strncmp(token, "time_t", 6))
            spec->isTime = YES;
        else if (length == 11 && !strncmp(token, "darwin.mode", 11))
            spec->isMode = YES;
        else if (length == 13 && !strncmp(token, "darwin.signal", 13))
            spec->isSignal = YES;
        else if (length == 6 && !strncmp(token, "uuid_t", 6))
            spec->isUUID = YES;
        token = end + 1;
    }
    *cursor = close + 1;
}

static void escape_into(CharonText *out, const unsigned char *bytes, size_t length)
{
    size_t index = 0;
    while (index < length) {
        unsigned char byte = bytes[index];
        size_t sequence = 0;
        if (byte < 0x80)
            sequence = 1;
        else if (byte >= 0xC2 && byte <= 0xDF)
            sequence = 2;
        else if (byte >= 0xE0 && byte <= 0xEF)
            sequence = 3;
        else if (byte >= 0xF0 && byte <= 0xF4)
            sequence = 4;
        BOOL valid = sequence > 0 && index + sequence <= length;
        for (size_t follow = 1; valid && follow < sequence; follow++)
            valid = (bytes[index + follow] & 0xC0) == 0x80;
        if (valid && sequence == 1) {
            if ((byte >= 0x20 && byte < 0x7F) || byte == '\t' || byte == '\n') {
                text_append(out, (const char *)&byte, 1);
            } else {
                char escape[4] = {'\\', '^', byte == 0x7F ? '?' : (char)(byte + '@'), 0};
                text_append(out, escape, 3);
            }
            index++;
        } else if (valid) {
            text_append(out, (const char *)bytes + index, sequence);
            index += sequence;
        } else {
            unsigned char low = byte & 0x7F;
            char escape[6] = {'\\', 'M', 0, 0, 0, 0};
            if (low >= 0x20 && low < 0x7F) {
                escape[2] = '-';
                escape[3] = (char)low;
            } else {
                escape[2] = '^';
                escape[3] = low == 0x7F ? '?' : (char)(low + '@');
            }
            text_append(out, escape, 4);
            index++;
        }
    }
}

char *charon_os_log_format(const char *format, va_list arguments, int error)
{
    CharonText text = {NULL, 0, 0};
    text_append(&text, "", 0);
    va_list list;
    va_copy(list, arguments);
    va_list *ap = &list;
    const char *cursor = format;
    while (*cursor) {
        if (*cursor != '%') {
            const char *next = strchr(cursor, '%');
            size_t run = next ? (size_t)(next - cursor) : strlen(cursor);
            text_append(&text, cursor, run);
            cursor += run;
            continue;
        }
        cursor++;
        if (!*cursor)
            break;
        if (*cursor == '%') {
            text_append(&text, "%", 1);
            cursor++;
            continue;
        }
        CharonSpec spec = {.width = 0, .precision = -1};
        if (*cursor == '{')
            parse_decorators(&cursor, &spec);
        size_t flagCount = 0;
        while (*cursor && strchr("-+ #0'", *cursor) && flagCount < sizeof spec.flags - 1)
            spec.flags[flagCount++] = *cursor++;
        if (*cursor == '*') {
            int width = va_arg(*ap, int);
            if (width < 0 && flagCount < sizeof spec.flags - 1) {
                spec.flags[flagCount++] = '-';
                width = -width;
            }
            spec.width = width;
            cursor++;
        } else {
            while (*cursor >= '0' && *cursor <= '9')
                spec.width = spec.width * 10 + (*cursor++ - '0');
        }
        if (*cursor == '.') {
            cursor++;
            spec.precision = 0;
            if (*cursor == '*') {
                spec.precision = va_arg(*ap, int);
                cursor++;
            } else {
                while (*cursor >= '0' && *cursor <= '9')
                    spec.precision = spec.precision * 10 + (*cursor++ - '0');
            }
        }
        if (*cursor == 'h' || *cursor == 'l') {
            spec.length[0] = *cursor++;
            if (*cursor == spec.length[0])
                spec.length[1] = *cursor++;
        } else if (*cursor && strchr("Lqjzt", *cursor)) {
            spec.length[0] = *cursor++;
        }
        char conversion = *cursor;
        if (!conversion)
            break;
        cursor++;
        switch (conversion) {
        case 'd': case 'i': case 'u': case 'o': case 'x': case 'X':
            append_integer(&text, &spec, conversion, ap, error);
            break;
        case 'c': {
            if (spec.isBool || spec.isBOOL) {
                append_integer(&text, &spec, 'd', ap, error);
                break;
            }
            char string[2] = {(char)va_arg(*ap, int), 0};
            spec.precision = -1;
            if (string[0])
                text_padded(&text, &spec, string);
            break;
        }
        case 'C': {
            char string[16];
            wint_t value = va_arg(*ap, wint_t);
            snprintf(string, sizeof string, "%lc", value);
            text_append(&text, string, strlen(string));
            break;
        }
        case 'e': case 'E': case 'f': case 'F': case 'g': case 'G': case 'a': case 'A': {
            double value = va_arg(*ap, double);
            char spec_format[32];
            spec_string(&spec, conversion, spec_format, sizeof spec_format, "");
            text_appendf(&text, spec_format, value);
            break;
        }
        case 'p': {
            void *value = va_arg(*ap, void *);
            char spec_format[32];
            spec_string(&spec, conversion, spec_format, sizeof spec_format, "");
            text_appendf(&text, spec_format, value);
            break;
        }
        case 's': case 'S': {
            if (conversion == 'S' || !strcmp(spec.length, "l")) {
                const wchar_t *wide = va_arg(*ap, const wchar_t *);
                char spec_format[32];
                spec_string(&spec, 's', spec_format, sizeof spec_format, "l");
                if (wide)
                    text_appendf(&text, spec_format, wide);
                else
                    text_padded(&text, &spec, "(null)");
                break;
            }
            const char *string = va_arg(*ap, const char *);
            text_padded(&text, &spec, string ?: "(null)");
            break;
        }
        case '@': {
            id object = va_arg(*ap, id);
            NSString *description = object ? description_of(object) : nil;
            spec.precision = -1;
            text_padded(&text, &spec, description ? description.UTF8String : "(null)");
            break;
        }
        case 'P': {
            const unsigned char *bytes = va_arg(*ap, const unsigned char *);
            append_bytes(&text, &spec, bytes, spec.precision > 0 ? spec.precision : 0);
            break;
        }
        case 'm':
            text_append(&text, strerror(error), strlen(strerror(error)));
            break;
        default:
            text_append(&text, &conversion, 1);
            break;
        }
    }
    va_end(list);
    while (text.length && strchr(" \t\n\r", text.bytes[text.length - 1]))
        text.bytes[--text.length] = 0;
    CharonText escaped = {NULL, 0, 0};
    text_append(&escaped, "", 0);
    escape_into(&escaped, (const unsigned char *)text.bytes, text.length);
    free(text.bytes);
    return escaped.bytes;
}
