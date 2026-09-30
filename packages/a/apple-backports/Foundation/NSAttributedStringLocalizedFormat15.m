#import <Foundation/Foundation.h>

/* The attributed formatting of iOS 15.0: five members over an NSAttributedString format.

   The format is an attributed string and not an NSString, which is the whole difference from the 2001
   API this sits beside: a conversion can stand inside a run of its own attributes, and those attributes
   are what the substituted text is drawn with. What the system's own Foundation does, measured by
   tests/backports/host/attributed15/run.sh, where the port's five members sit beside the system's in one
   process and every case compares:

     the format's own attributes at a conversion are MERGED with the argument's, the argument winning
     where the two name one key, and a literal takes the attributes of the format at its OWN place, so a
     coloured run keeps its colour and the substituted text beside it has none;
     NSAttributedStringFormattingInsertArgumentAttributesWithoutMerging keeps the argument's alone and
     drops the format's;
     NSAttributedStringFormattingApplyReplacementIndexAttribute puts NSReplacementIndexAttributeName on
     each substituted run, numbered from 1 in the order the conversions appear;
     the text a %@ is replaced with is an attributed argument's own string, anything else's -description,
     and a nil one's "(null)";
     a '%' that opens no conversion is consumed and leaves nothing: "100%% %@ %q" answers "100% v ", a
     trailing '%' and a bare '%' answer without it, and "a % b" answers "a  b" - the flags and the width
     before a character that is no conversion go with it.

   And the one that is not in the header: the two families differ in the locale they format numbers with.
   -initWithFormat:options:locale: formats CANONICALLY whatever locale it is handed - de_DE and fr_FR and
   nil all answer "1234 and 1234.50" - while +localizedAttributedStringWithFormat: formats with the
   current locale and answered "1.234 and 1.234,50" for the machine's en_US@rg=plzzzz. So the locale an
   explicit initialiser is given does not reach the arithmetic, and a nil there is what answers the
   measured string; the localized methods pass [NSLocale currentLocale] themselves.

   One object for this release and no other. The scan below is its own and not the one in
   NSString+ValidatedFormat.m: that one validates a format and refuses a specifier it cannot honour, this
   one walks a format to substitute into it and to know which attributes each conversion stands in, and a
   15.0 object may not call a C function a 16.0 one defines - the file that defines it is left out of
   every band below 16.0, so the call would be undefined there and nowhere else.

   What this object does not carry, measured and named: a positional conversion, "%1$@", which the system
   answers by taking its argument from the position it names ("%2$@-%1$@" answers "two-one") and which is
   consumed here with nothing in its place. facts/Foundation/AttributedStrings15.md says so with the
   reading. */

typedef struct {
    unichar flags[8];
    NSUInteger flagLength;
    NSUInteger width;         /* NSNotFound when the format wrote none */
    NSUInteger precision;     /* NSNotFound when the format wrote none */
    int length;               /* 'h', 'l', 'z', 'j', 't', 'q', or 0 */
    unichar conversion;
    NSUInteger end;           /* one past the last character the conversion took */
} CharonConversion;

static BOOL CharonFlag(unichar c)
{
    return c == '-' || c == '+' || c == ' ' || c == '#' || c == '0' || c == '\'';
}

static BOOL CharonLength(unichar c)
{
    return c == 'h' || c == 'l' || c == 'z' || c == 'j' || c == 't' || c == 'q';
}

static BOOL CharonUses(unichar c)
{
    return c != 0 && strchr("diouxXeEfFgGaAcCsSpn@", c) != NULL;
}

/* One conversion, starting at its '%'. What it returns is where the scan stopped, whether or not it
   found a conversion: a '%' whose last character is not one is consumed whole and emits nothing, which
   is the measured answer, so the caller never has to look at a character the scan already passed. */
static BOOL CharonConversionAt(NSString *format, NSUInteger percent, CharonConversion *out)
{
    NSUInteger length = format.length, index = percent + 1, digits;
    memset(out, 0, sizeof *out);
    out->width = NSNotFound;
    out->precision = NSNotFound;
    if (index >= length) {
        out->end = percent + 1;         /* a trailing '%' is consumed and emits nothing */
        return NO;
    }
    if ([format characterAtIndex:index] == '%') {
        out->conversion = '%';
        out->end = index + 1;
        return YES;
    }
    while (index < length && CharonFlag([format characterAtIndex:index]) && out->flagLength < sizeof out->flags / sizeof *out->flags)
        out->flags[out->flagLength++] = [format characterAtIndex:index++];
    if (index < length && [format characterAtIndex:index] == '*') {
        index++;                        /* a width taken from the argument list: this object takes none */
    } else {
        digits = 0;
        while (index < length && [format characterAtIndex:index] >= '0' && [format characterAtIndex:index] <= '9')
            digits = digits * 10 + (NSUInteger)([format characterAtIndex:index++] - '0');
        if (index > percent + 1 && [format characterAtIndex:index - 1] >= '0' && [format characterAtIndex:index - 1] <= '9')
            out->width = digits;
    }
    if (index < length && [format characterAtIndex:index] == '.') {
        index++;
        if (index < length && [format characterAtIndex:index] == '*') {
            index++;
        } else {
            digits = 0;
            while (index < length && [format characterAtIndex:index] >= '0' && [format characterAtIndex:index] <= '9')
                digits = digits * 10 + (NSUInteger)([format characterAtIndex:index++] - '0');
            out->precision = digits;
        }
    }
    while (index < length && CharonLength([format characterAtIndex:index])) {
        if ([format characterAtIndex:index] == 'l' && index + 1 < length && [format characterAtIndex:index + 1] == 'l') {
            out->length = 'q';
            index += 2;
            continue;
        }
        out->length = (int)[format characterAtIndex:index];
        index++;
    }
    if (index < length && CharonUses([format characterAtIndex:index])) {
        out->conversion = [format characterAtIndex:index];
        out->end = index + 1;
        return YES;
    }
    /* A '%' that opens no conversion is consumed together with the flags, the width and the length the
       scan read, and the character that is not a conversion is text again - unless it is the last
       character of the format and the scan read nothing, which is the whole of it: "a % b" answers
       "a  b" and "a %1 b" answers "a 1 b" with the space and the "1" kept, "x %q y" answers "x q y",
       and "%q", "%0", "%-" and the "%q" at the end of "100%% %@ %q" answer nothing at all (all
       measured). */
    if (index >= length)
        out->end = length;
    else if (index + 1 == length && index == percent + 1)
        out->end = length;
    else
        out->end = percent + 1;
    return NO;
}

/* The conversion on its own, for the release's own formatter: this one's flags, width, precision and
   length with this one's conversion character. The arithmetic and the grouping are then the system's,
   which is where they belong, and not a second implementation of them here. */
static NSString *CharonSpecifier(CharonConversion spec)
{
    NSMutableString *text = [NSMutableString stringWithString:@"%"];
    for (NSUInteger i = 0; i < spec.flagLength; i++)
        [text appendFormat:@"%C", spec.flags[i]];
    if (spec.width != NSNotFound)
        [text appendFormat:@"%lu", (unsigned long)spec.width];
    if (spec.precision != NSNotFound)
        [text appendFormat:@".%lu", (unsigned long)spec.precision];
    if (spec.length)
        [text appendFormat:@"%C", (unichar)spec.length];
    [text appendFormat:@"%C", spec.conversion];
    return text;
}

/* One argument, formatted on its own. The list a variadic member is given cannot be handed to the
   release's formatter twice: the second call reads the floating point register area as spent and answers
   0.00 where the first answered 1234.50 (measured, with %d and %.2f off one list). So each argument is
   taken out of the list here, with the type C promotes it to, and formatted on its own through this -
   a fresh list of one, which the release's own formatter reads whole. */
static NSString *CharonApply(NSLocale *locale, NSString *specifier, ...)
{
    va_list arguments;
    va_start(arguments, specifier);
    NSString *formatted = [[NSString alloc] initWithFormat:specifier locale:locale arguments:arguments];
    va_end(arguments);
    return formatted;
}

static NSString *CharonNumericArgument(CharonConversion spec, NSLocale *locale, va_list *arguments)
{
    NSString *specifier = CharonSpecifier(spec);
    switch (spec.conversion) {
    case 'd': case 'i':
        if (spec.length == 'l')
            return CharonApply(locale, specifier, va_arg(*arguments, long));
        if (spec.length == 'q')
            return CharonApply(locale, specifier, va_arg(*arguments, long long));
        if (spec.length == 'z')
            return CharonApply(locale, specifier, (long)va_arg(*arguments, ptrdiff_t));
        if (spec.length == 'j')
            return CharonApply(locale, specifier, (long)va_arg(*arguments, intmax_t));
        if (spec.length == 't')
            return CharonApply(locale, specifier, (long)va_arg(*arguments, ptrdiff_t));
        return CharonApply(locale, specifier, va_arg(*arguments, int));
    case 'u': case 'o': case 'x': case 'X':
        if (spec.length == 'l')
            return CharonApply(locale, specifier, va_arg(*arguments, unsigned long));
        if (spec.length == 'q')
            return CharonApply(locale, specifier, va_arg(*arguments, unsigned long long));
        if (spec.length == 'z')
            return CharonApply(locale, specifier, (unsigned long)va_arg(*arguments, size_t));
        if (spec.length == 'j')
            return CharonApply(locale, specifier, (unsigned long)va_arg(*arguments, uintmax_t));
        if (spec.length == 't')
            return CharonApply(locale, specifier, (unsigned long)va_arg(*arguments, ptrdiff_t));
        return CharonApply(locale, specifier, va_arg(*arguments, unsigned int));
    case 'f': case 'F': case 'e': case 'E': case 'g': case 'G': case 'a': case 'A':
        if (spec.length == 'L')
            return CharonApply(locale, specifier, va_arg(*arguments, long double));
        return CharonApply(locale, specifier, va_arg(*arguments, double));
    case 'c':
        return CharonApply(locale, specifier, va_arg(*arguments, int));
    case 's':
        return CharonApply(locale, specifier, va_arg(*arguments, char *));
    case 'p':
        return CharonApply(locale, specifier, va_arg(*arguments, void *));
    default:
        return @"";
    }
}

/* The attributes one substituted range is drawn with: the format's own at the conversion, the
   argument's over the top, and the replacement index when the options ask for it. */
static NSDictionary *CharonAttributes(NSDictionary *formatAttributes, NSDictionary *argumentAttributes,
                                      NSUInteger options, NSUInteger replacement)
{
    NSMutableDictionary *attributes;
    if (options & NSAttributedStringFormattingInsertArgumentAttributesWithoutMerging) {
        attributes = [NSMutableDictionary dictionaryWithDictionary:argumentAttributes ?: [NSDictionary dictionary]];
    } else {
        attributes = [NSMutableDictionary dictionaryWithDictionary:formatAttributes ?: [NSDictionary dictionary]];
        if (argumentAttributes)
            [attributes addEntriesFromDictionary:argumentAttributes];
    }
    if (options & NSAttributedStringFormattingApplyReplacementIndexAttribute)
        attributes[NSReplacementIndexAttributeName] = @(replacement);
    return attributes;
}

static void CharonAppend(NSMutableAttributedString *result, NSString *text, NSDictionary *attributes)
{
    if (text.length)
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:attributes]];
}

static void CharonAppendText(NSMutableAttributedString *result, NSAttributedString *format, NSString *text, NSUInteger index)
{
    NSDictionary *attributes = [format attributesAtIndex:index effectiveRange:NULL] ?: [NSDictionary dictionary];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:attributes]];
}

static void CharonAppendLiteral(NSMutableAttributedString *result, NSAttributedString *format, NSString *text,
                                NSUInteger start, NSUInteger end)
{
    /* Literal text takes the attributes of the format at its OWN place, so a coloured run of the format
       keeps its colour and the text after it does not: "pre %@ mid %@ post" with the colour over "%@ "
       answers a coloured "ARG" and a coloured " " and an uncoloured "mid ". One run per effective range,
       which is what the enumeration below asks the format for. */
    NSUInteger at = start;
    while (at < end) {
        NSRange effective;
        [format attributesAtIndex:at effectiveRange:&effective];
        NSUInteger stop = MIN(effective.location + effective.length, end);
        if (stop <= at)
            stop = at + 1;
        CharonAppendText(result, format, [text substringWithRange:NSMakeRange(at, stop - at)], at);
        at = stop;
    }
}

static NSAttributedString *CharonFormat(NSAttributedString *format, NSUInteger options, NSLocale *locale, va_list arguments)
{
    NSString *text;
    NSMutableAttributedString *result;
    NSUInteger index = 0, length, replacement = 0;
    CharonConversion spec;
    if (!format) {
        /* A nil format is the release's own refusal and keeps its own wording and its own class: the
           concrete class raises from -initWithString: ("NSConcreteAttributedString initWithString:: nil
           value", measured), and asking it there is what answers with that text rather than this
           object's own guess at it. The argument is nil on purpose, so the warning is silenced where
           the reason is written. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        return [[NSAttributedString alloc] initWithString:nil];
#pragma clang diagnostic pop
    }
    text = [format string];
    length = text.length;
    result = [[NSMutableAttributedString alloc] init];
    while (index < length) {
        if ([text characterAtIndex:index] != '%') {
            NSUInteger start = index;
            while (index < length && [text characterAtIndex:index] != '%')
                index++;
            CharonAppendLiteral(result, format, text, start, index);
            continue;
        }
        if (!CharonConversionAt(text, index, &spec)) {
            index = MAX(spec.end, index + 1);
            continue;
        }
        if (spec.conversion == '%') {
            CharonAppendText(result, format, @"%", index);
            index = spec.end;
            continue;
        }
        {
            NSDictionary *formatAttributes = [format attributesAtIndex:index effectiveRange:NULL];
            replacement++;
            if (spec.conversion == '@') {
                id argument = va_arg(arguments, id);
                if ([argument isKindOfClass:[NSAttributedString class]]) {
                    NSAttributedString *attributed = argument;
                    NSString *attributedText = [attributed string];
                    [attributed enumerateAttributesInRange:NSMakeRange(0, attributed.length) options:0
                                                 usingBlock:^(NSDictionary *attributes, NSRange range, BOOL *stop) {
                        CharonAppend(result, [attributedText substringWithRange:range],
                                     CharonAttributes(formatAttributes, attributes, options, replacement));
                    }];
                } else {
                    CharonAppend(result, argument ? [argument description] : @"(null)",
                                 CharonAttributes(formatAttributes, nil, options, replacement));
                }
            } else {
                CharonAppend(result, CharonNumericArgument(spec, locale, &arguments),
                             CharonAttributes(formatAttributes, nil, options, replacement));
            }
        }
        index = spec.end;
    }
    return result;
}

@implementation NSAttributedString (CharonAttributedFormat15)

- (instancetype)initWithFormat:(NSAttributedString *)format
                       options:(NSAttributedStringFormattingOptions)options
                        locale:(NSLocale *)locale
                     arguments:(va_list)arguments
{
    /* The locale is not passed on, and that is the measured answer rather than an omission: an explicit
       locale formats canonically (de_DE, fr_FR and nil all answer "1234 and 1234.50"), so handing it to
       the release's formatter would localise where the release does not. */
    (void)locale;
    return [self initWithAttributedString:CharonFormat(format, options, nil, arguments)];
}

- (instancetype)initWithFormat:(NSAttributedString *)format
                       options:(NSAttributedStringFormattingOptions)options
                        locale:(NSLocale *)locale, ...
{
    va_list arguments;
    va_start(arguments, locale);
    NSAttributedString *result = CharonFormat(format, options, nil, arguments);
    va_end(arguments);
    return [self initWithAttributedString:result];
}

+ (instancetype)localizedAttributedStringWithFormat:(NSAttributedString *)format, ...
{
    va_list arguments;
    va_start(arguments, format);
    NSAttributedString *result = CharonFormat(format, 0, [NSLocale currentLocale], arguments);
    va_end(arguments);
    return result;
}

+ (instancetype)localizedAttributedStringWithFormat:(NSAttributedString *)format
                                            options:(NSAttributedStringFormattingOptions)options, ...
{
    va_list arguments;
    va_start(arguments, options);
    NSAttributedString *result = CharonFormat(format, options, [NSLocale currentLocale], arguments);
    va_end(arguments);
    return result;
}

@end

@implementation NSMutableAttributedString (CharonAttributedFormat15)

- (void)appendLocalizedFormat:(NSAttributedString *)format, ...
{
    va_list arguments;
    va_start(arguments, format);
    NSAttributedString *result = CharonFormat(format, 0, [NSLocale currentLocale], arguments);
    va_end(arguments);
    [self appendAttributedString:result];
}

@end
