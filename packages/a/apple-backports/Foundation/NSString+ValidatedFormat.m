#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, CharonFormatKind) {
    CharonFormatNone,
    CharonFormatObject,
    CharonFormatInteger,
    CharonFormatFloating,
    CharonFormatCString,
    CharonFormatPointer,
};

static CharonFormatKind charon_format_kind(unichar conversion)
{
    switch (conversion) {
        case '@': return CharonFormatObject;
        case 'd': case 'D': case 'i': case 'o': case 'O': case 'u': case 'U': case 'x': case 'X':
        case 'c': case 'C': return CharonFormatInteger;
        case 'f': case 'F': case 'e': case 'E': case 'g': case 'G': case 'a': case 'A': return CharonFormatFloating;
        case 's': case 'S': return CharonFormatCString;
        case 'p': return CharonFormatPointer;
        default: return CharonFormatNone;
    }
}

static BOOL charon_format_specifiers(NSString *format, NSMutableArray *kinds)
{
    NSUInteger length = format.length, next = 0;
    for (NSUInteger index = 0; index < length; index++) {
        if ([format characterAtIndex:index] != '%')
            continue;
        if (++index >= length)
            return NO;
        if ([format characterAtIndex:index] == '%')
            continue;
        NSUInteger position = 0, digits = index;
        while (digits < length && [format characterAtIndex:digits] >= '0' && [format characterAtIndex:digits] <= '9')
            position = position * 10 + ([format characterAtIndex:digits++] - '0');
        BOOL positional = digits < length && digits > index && [format characterAtIndex:digits] == '$';
        if (positional)
            index = digits + 1;
        while (index < length && [@"-+ #'0" rangeOfString:[format substringWithRange:NSMakeRange(index, 1)]].location != NSNotFound)
            index++;
        while (index < length && (([format characterAtIndex:index] >= '0' && [format characterAtIndex:index] <= '9') ||
                                  [format characterAtIndex:index] == '.' || [format characterAtIndex:index] == '*'))
            index++;
        while (index < length && [@"hlLqjzt" rangeOfString:[format substringWithRange:NSMakeRange(index, 1)]].location != NSNotFound)
            index++;
        if (index >= length)
            return NO;
        CharonFormatKind kind = charon_format_kind([format characterAtIndex:index]);
        if (kind == CharonFormatNone)
            continue;
        NSUInteger slot = positional ? (position ? position - 1 : 0) : next++;
        while (kinds.count <= slot)
            [kinds addObject:@(CharonFormatNone)];
        kinds[slot] = @(kind);
    }
    return YES;
}

static BOOL charon_format_allowed(NSString *format, NSString *valid)
{
    NSMutableArray *wanted = [NSMutableArray array], *allowed = [NSMutableArray array];
    if (!charon_format_specifiers(format, wanted) || !charon_format_specifiers(valid, allowed))
        return NO;
    if (wanted.count > allowed.count)
        return NO;
    for (NSUInteger index = 0; index < wanted.count; index++) {
        NSNumber *kind = wanted[index];
        if (kind.unsignedIntegerValue == CharonFormatNone)
            continue;
        if (![kind isEqual:allowed[index]])
            return NO;
    }
    return YES;
}

@implementation NSString (CharonValidatedFormat)

- (instancetype)initWithValidatedFormat:(NSString *)format validFormatSpecifiers:(NSString *)validFormatSpecifiers
                                  error:(NSError **)error, ...
{
    va_list arguments;
    va_start(arguments, error);
    self = [self initWithValidatedFormat:format validFormatSpecifiers:validFormatSpecifiers locale:nil arguments:arguments error:error];
    va_end(arguments);
    return self;
}

- (instancetype)initWithValidatedFormat:(NSString *)format validFormatSpecifiers:(NSString *)validFormatSpecifiers
                                 locale:(id)locale error:(NSError **)error, ...
{
    va_list arguments;
    va_start(arguments, error);
    self = [self initWithValidatedFormat:format validFormatSpecifiers:validFormatSpecifiers locale:locale arguments:arguments error:error];
    va_end(arguments);
    return self;
}

- (instancetype)initWithValidatedFormat:(NSString *)format validFormatSpecifiers:(NSString *)validFormatSpecifiers
                                 locale:(id)locale arguments:(va_list)arguments error:(NSError **)error
{
    if (!format || !validFormatSpecifiers)
        [NSException raise:NSInvalidArgumentException format:@"*** -[%@ %@]: nil argument", [self class], NSStringFromSelector(_cmd)];
    if (!charon_format_allowed(format, validFormatSpecifiers)) {
        if (error)
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFormattingError
                                     userInfo:@{NSDebugDescriptionErrorKey: [NSString stringWithFormat:@"Format '%@' does not match expected '%@'", format, validFormatSpecifiers]}];
        return nil;
    }
    return [self initWithFormat:format locale:locale arguments:arguments];
}

+ (instancetype)stringWithValidatedFormat:(NSString *)format validFormatSpecifiers:(NSString *)validFormatSpecifiers
                                    error:(NSError **)error, ...
{
    va_list arguments;
    va_start(arguments, error);
    NSString *made = [[self alloc] initWithValidatedFormat:format validFormatSpecifiers:validFormatSpecifiers locale:nil arguments:arguments error:error];
    va_end(arguments);
    return made;
}

+ (instancetype)localizedStringWithValidatedFormat:(NSString *)format validFormatSpecifiers:(NSString *)validFormatSpecifiers
                                             error:(NSError **)error, ...
{
    va_list arguments;
    va_start(arguments, error);
    NSString *made = [[self alloc] initWithValidatedFormat:format validFormatSpecifiers:validFormatSpecifiers
                                                    locale:[NSLocale currentLocale] arguments:arguments error:error];
    va_end(arguments);
    return made;
}

@end
