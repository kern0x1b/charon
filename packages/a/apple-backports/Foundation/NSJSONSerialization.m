#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <ctype.h>
#include <errno.h>
#include <stdlib.h>

// NSJSONSerialization arrived in iOS 5.0 (facts/Foundation/NSJSONSerialization.md); below that the class itself is missing, so
// this file carries it whole, from the 26.2 SDK header, every method at once: +isValidJSONObject:, +dataWithJSONObject:options:
// error:, +JSONObjectWithData:options:error:, +writeJSONObject:toStream:options:error: and +JSONObjectWithStream:options:error:
// (both from 7.0, in this same file since neither has an exported symbol of its own for band() to split on - only the class's own
// _OBJC_CLASS_$_NSJSONSerialization is, and that is native from 5.0). From 5.0 on, band() reexports the release's own class
// instead of this one, the same way it does for NSUUID and NSProgress; a caller on 5.0 and later gets the release's own answers,
// not this file's, including the release's own gap (registry/Foundation/ios11.json, NSJSONWritingSortedKeys ignored below iOS 11).
//
// Every reading/writing rule here is measured against the host's own Foundation (facts/Foundation/NSJSONSerialization.md),
// not read from the JSON RFC: trailing commas in arrays and objects are accepted unconditionally (not gated by any option), a
// number's NSNumber kind depends on how many significant digits it has and whether it fits an integer type, and the exact
// exception/error text below is the host's own wording, not invented.

// Encoding detection (the data may be in any of the 5 the header documents: UTF-8, UTF-16LE, UTF-16BE, UTF-32LE, UTF-32BE),
// by a byte-order mark first, else by the zero-byte pattern of the first four bytes - valid JSON always opens with an ASCII
// structural character below 0x80, so a zero in an odd position identifies a wide encoding and its endianness.
static NSStringEncoding CharonJSONDetectEncoding(NSData *data, NSUInteger *bomLength)
{
    const unsigned char *b = (const unsigned char *)data.bytes;
    NSUInteger n = data.length;
    *bomLength = 0;
    if (n >= 4 && b[0] == 0x00 && b[1] == 0x00 && b[2] == 0xFE && b[3] == 0xFF) { *bomLength = 4; return NSUTF32BigEndianStringEncoding; }
    if (n >= 4 && b[0] == 0xFF && b[1] == 0xFE && b[2] == 0x00 && b[3] == 0x00) { *bomLength = 4; return NSUTF32LittleEndianStringEncoding; }
    if (n >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) { *bomLength = 3; return NSUTF8StringEncoding; }
    if (n >= 2 && b[0] == 0xFE && b[1] == 0xFF) { *bomLength = 2; return NSUTF16BigEndianStringEncoding; }
    if (n >= 2 && b[0] == 0xFF && b[1] == 0xFE) { *bomLength = 2; return NSUTF16LittleEndianStringEncoding; }
    if (n >= 4) {
        BOOL z0 = b[0] == 0, z1 = b[1] == 0, z2 = b[2] == 0, z3 = b[3] == 0;
        if (z0 && z1 && z2 && !z3) return NSUTF32BigEndianStringEncoding;
        if (!z0 && z1 && z2 && z3) return NSUTF32LittleEndianStringEncoding;
        if (z0 && !z1 && z2 && !z3) return NSUTF16BigEndianStringEncoding;
        if (!z0 && z1 && !z2 && z3) return NSUTF16LittleEndianStringEncoding;
    } else if (n >= 2) {
        if (b[0] == 0 && b[1] != 0) return NSUTF16BigEndianStringEncoding;
        if (b[0] != 0 && b[1] == 0) return NSUTF16LittleEndianStringEncoding;
    }
    return NSUTF8StringEncoding;
}

static const NSUInteger CharonJSONMaximumDepth = 512; // measured: opening 512 arrays parses, 513 fails ("Too many nested arrays or dictionaries")

static NSError *CharonJSONError(NSUInteger line, NSUInteger column, NSUInteger index, NSString *reason)
{
    NSString *debug = [NSString stringWithFormat:@"%@ around line %lu, column %lu.", reason, (unsigned long)line, (unsigned long)column];
    return [NSError errorWithDomain:NSCocoaErrorDomain code:NSPropertyListReadCorruptError
                            userInfo:@{NSDebugDescriptionErrorKey: debug, @"NSJSONSerializationErrorIndex": @(index)}];
}

// A single parse over one buffer of UTF-16 code units: object/array/string/number/literal, trailing commas tolerated (measured
// unconditional, not an option), a 512-deep nesting limit (measured), and - only under NSJSONReadingJSON5Allowed - the wider
// grammar measured under that option (single-quoted strings, bare identifier keys, // and /* */ comments, a leading +, 0x hex
// integers, and the NaN/Infinity/-Infinity literals); NSJSONReadingTopLevelDictionaryAssumed wraps content with no top-level
// { or [ as if it were the body of one. What JSON5Allowed does not add here: escape sequences beyond the ones below (\0, \xHH,
// a backslash-newline continuation) - not reached by anything measured, so not claimed.
@interface CharonJSONReader : NSObject
@property (nonatomic) const unichar *buffer;
@property (nonatomic) NSUInteger length;
@property (nonatomic) NSUInteger position;
@property (nonatomic) NSUInteger line;
@property (nonatomic) NSUInteger lineStart;
@property (nonatomic) NSUInteger depth;
@property (nonatomic) NSJSONReadingOptions options;
@property (nonatomic, strong) NSError *error;
@end

@implementation CharonJSONReader
@synthesize buffer = _buffer, length = _length, position = _position, line = _line, lineStart = _lineStart,
            depth = _depth, options = _options, error = _error;

- (BOOL)json5 { return (self.options & (1UL << 3)) != 0; } // NSJSONReadingJSON5Allowed

- (unichar)peek { return self.position < self.length ? self.buffer[self.position] : 0; }

- (void)fail:(NSString *)reason
{
    if (self.error)
        return;
    NSUInteger index = self.position;
    self.error = CharonJSONError(self.line, index - self.lineStart + 1, index, reason);
}

- (void)advance
{
    if (self.buffer[self.position] == '\n') {
        self.line += 1;
        self.lineStart = self.position + 1;
    }
    self.position += 1;
}

- (void)skipWhitespaceAndComments
{
    while (self.position < self.length && !self.error) {
        unichar c = [self peek];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            [self advance];
        } else if (self.json5 && c == '/' && self.position + 1 < self.length && self.buffer[self.position + 1] == '/') {
            while (self.position < self.length && [self peek] != '\n')
                [self advance];
        } else if (self.json5 && c == '/' && self.position + 1 < self.length && self.buffer[self.position + 1] == '*') {
            [self advance]; [self advance];
            while (self.position + 1 < self.length && !(self.buffer[self.position] == '*' && self.buffer[self.position + 1] == '/'))
                [self advance];
            if (self.position + 1 >= self.length) { [self fail:@"Unterminated comment"]; return; }
            [self advance]; [self advance];
        } else {
            return;
        }
    }
}

- (id)parseValue
{
    [self skipWhitespaceAndComments];
    if (self.error)
        return nil;
    if (self.position >= self.length) { [self fail:@"Unexpected end of file"]; return nil; }
    unichar c = [self peek];
    if (c == '{') return [self parseObject];
    if (c == '[') return [self parseArray];
    if (c == '"') return [self parseString];
    if (self.json5 && c == '\'') return [self parseQuotedString:'\''];
    if (c == '-' || (c >= '0' && c <= '9')) return [self parseNumber];
    if (self.json5 && c == '+') return [self parseNumber];
    if ([self literal:@"true"]) return @YES;
    if ([self literal:@"false"]) return @NO;
    if ([self literal:@"null"]) return [NSNull null];
    if (self.json5 && [self literal:@"NaN"]) return @(NAN);
    if (self.json5 && [self literal:@"Infinity"]) return @(INFINITY);
    if (self.json5 && c == '-' ) {} // handled by parseNumber (covers -Infinity too, below)
    [self fail:@"Invalid value"];
    return nil;
}

- (BOOL)literal:(NSString *)word
{
    NSUInteger n = word.length;
    if (self.position + n > self.length)
        return NO;
    for (NSUInteger i = 0; i < n; i++)
        if (self.buffer[self.position + i] != [word characterAtIndex:i])
            return NO;
    for (NSUInteger i = 0; i < n; i++)
        [self advance];
    return YES;
}

- (id)parseObject
{
    if (++self.depth > CharonJSONMaximumDepth) { [self fail:@"Too many nested arrays or dictionaries"]; return nil; }
    [self advance]; // '{'
    NSMutableDictionary *dict = (self.options & NSJSONReadingMutableContainers) ? [NSMutableDictionary new] : [NSMutableDictionary new];
    [self skipWhitespaceAndComments];
    if (!self.error && [self peek] == '}') {
        [self advance]; self.depth -= 1;
        return (self.options & NSJSONReadingMutableContainers) ? dict : [dict copy];
    }
    for (;;) {
        [self skipWhitespaceAndComments];
        if (self.error) return nil;
        if (self.position >= self.length) { [self fail:@"Unexpected end of file"]; return nil; }
        NSString *key;
        if (self.json5 && [self peek] != '"' && [self peek] != '\'') {
            key = [self parseIdentifier];
        } else if ([self peek] == '\'') {
            key = self.json5 ? [self parseQuotedString:'\''] : nil;
            if (!self.json5) { [self fail:@"Invalid value"]; return nil; }
        } else {
            key = [self parseString];
        }
        if (self.error) return nil;
        [self skipWhitespaceAndComments];
        if (self.error) return nil;
        if ([self peek] != ':') { [self fail:@"Badly formed object"]; return nil; }
        [self advance];
        id value = [self parseValue];
        if (self.error) return nil;
        dict[key] = value;
        [self skipWhitespaceAndComments];
        if (self.error) return nil;
        unichar c = [self peek];
        if (c == ',') {
            [self advance];
            [self skipWhitespaceAndComments];
            if (!self.error && [self peek] == '}') { [self advance]; break; } // trailing comma (measured, unconditional)
            continue;
        }
        if (c == '}') { [self advance]; break; }
        [self fail:@"Badly formed object"];
        return nil;
    }
    self.depth -= 1;
    return (self.options & NSJSONReadingMutableContainers) ? dict : [dict copy];
}

- (id)parseArray
{
    if (++self.depth > CharonJSONMaximumDepth) { [self fail:@"Too many nested arrays or dictionaries"]; return nil; }
    [self advance]; // '['
    NSMutableArray *array = [NSMutableArray new];
    [self skipWhitespaceAndComments];
    if (!self.error && [self peek] == ']') {
        [self advance]; self.depth -= 1;
        return (self.options & NSJSONReadingMutableContainers) ? array : [array copy];
    }
    for (;;) {
        id value = [self parseValue];
        if (self.error) return nil;
        [array addObject:value];
        [self skipWhitespaceAndComments];
        if (self.error) return nil;
        unichar c = [self peek];
        if (c == ',') {
            [self advance];
            [self skipWhitespaceAndComments];
            if (!self.error && [self peek] == ']') { [self advance]; break; } // trailing comma (measured, unconditional)
            continue;
        }
        if (c == ']') { [self advance]; break; }
        [self fail:@"Badly formed array"];
        return nil;
    }
    self.depth -= 1;
    return (self.options & NSJSONReadingMutableContainers) ? array : [array copy];
}

// json5Allowed's bare object key: an identifier - a leading letter, '_' or '$', then letters, digits, '_' or '$'. Not the
// fuller ECMAScript IdentifierName (no Unicode escapes, no non-ASCII letters) - not reached by anything measured.
- (NSString *)parseIdentifier
{
    NSUInteger start = self.position;
    unichar c = [self peek];
    BOOL first = (c == '_' || c == '$' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'));
    if (!first) { [self fail:@"Invalid value"]; return nil; }
    [self advance];
    for (;;) {
        c = [self peek];
        if (c == '_' || c == '$' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))
            [self advance];
        else
            break;
    }
    return [NSString stringWithCharacters:self.buffer + start length:self.position - start];
}

- (NSString *)parseString { return [self parseQuotedString:'"']; }

- (NSString *)parseQuotedString:(unichar)quote
{
    [self advance]; // opening quote
    NSMutableString *out = [NSMutableString new];
    for (;;) {
        if (self.position >= self.length) { [self fail:@"Unterminated string"]; return nil; }
        unichar c = self.buffer[self.position];
        if (c == quote) { [self advance]; return out; }
        if (c < 0x20) { [self fail:@"Unescaped control character"]; return nil; }
        if (c != '\\') { [out appendFormat:@"%C", c]; [self advance]; continue; }
        [self advance]; // backslash
        if (self.position >= self.length) { [self fail:@"Unterminated string"]; return nil; }
        unichar e = self.buffer[self.position];
        switch (e) {
            case '"': [out appendString:@"\""]; [self advance]; break;
            case '\'': [out appendString:@"'"]; [self advance]; break;
            case '\\': [out appendString:@"\\"]; [self advance]; break;
            case '/': [out appendString:@"/"]; [self advance]; break;
            case 'b': [out appendFormat:@"%C", (unichar)0x08]; [self advance]; break;
            case 'f': [out appendFormat:@"%C", (unichar)0x0C]; [self advance]; break;
            case 'n': [out appendString:@"\n"]; [self advance]; break;
            case 'r': [out appendString:@"\r"]; [self advance]; break;
            case 't': [out appendString:@"\t"]; [self advance]; break;
            case 'u': {
                [self advance];
                unichar u1 = [self readHex4];
                if (self.error) return nil;
                if (u1 >= 0xD800 && u1 <= 0xDBFF) {
                    if (self.position + 1 >= self.length || self.buffer[self.position] != '\\' || self.buffer[self.position + 1] != 'u') {
                        [self fail:@"Unexpected end of file during string parse (expected low-surrogate code point but did not find one)."];
                        return nil;
                    }
                    [self advance]; [self advance];
                    unichar u2 = [self readHex4];
                    if (self.error) return nil;
                    if (u2 < 0xDC00 || u2 > 0xDFFF) { [self fail:@"Unexpected low-surrogate code point"]; return nil; }
                    [out appendFormat:@"%C%C", u1, u2];
                } else {
                    [out appendFormat:@"%C", u1];
                }
                break;
            }
            default:
                [self fail:@"Invalid escape sequence"];
                return nil;
        }
    }
}

- (unichar)readHex4
{
    if (self.position + 4 > self.length) { [self fail:@"Unterminated string"]; return 0; }
    unichar value = 0;
    for (int i = 0; i < 4; i++) {
        unichar c = self.buffer[self.position + i];
        int digit;
        if (c >= '0' && c <= '9') digit = c - '0';
        else if (c >= 'a' && c <= 'f') digit = 10 + c - 'a';
        else if (c >= 'A' && c <= 'F') digit = 10 + c - 'A';
        else { [self fail:@"Invalid \\u escape"]; return 0; }
        value = (unichar)(value * 16 + digit);
    }
    self.position += 4;
    return value;
}

// Number classification (facts/Foundation/NSJSONSerialization.md, measured against the host): an integer literal becomes a
// long long if it fits, else an unsigned long long if it fits, else an NSDecimalNumber; a literal with a '.' or an exponent
// becomes a double when it has 17 or fewer significant digits (int-part and fraction-part digits, not counting a lone
// leading "0"), else an NSDecimalNumber - measured at the exact boundary (17 stays double, 18 becomes NSDecimalNumber).
- (id)parseNumber
{
    NSUInteger start = self.position;
    if (self.json5 && ([self peek] == '-' || [self peek] == '+') &&
        (self.position + 1 < self.length) && [self literalAt:self.position + 1 word:@"Infinity"]) {
        BOOL negative = self.buffer[self.position] == '-';
        [self advance];
        [self literal:@"Infinity"];
        return @(negative ? -INFINITY : INFINITY);
    }
    BOOL negative = NO;
    if ([self peek] == '-') { negative = YES; [self advance]; }
    else if (self.json5 && [self peek] == '+') { [self advance]; }
    if (self.json5 && [self peek] == '0' && self.position + 1 < self.length &&
        (self.buffer[self.position + 1] == 'x' || self.buffer[self.position + 1] == 'X')) {
        [self advance]; [self advance];
        NSUInteger hexStart = self.position;
        while (self.position < self.length && isxdigit(self.buffer[self.position]))
            [self advance];
        if (self.position == hexStart) { [self fail:@"Invalid number"]; return nil; }
        NSString *hex = [NSString stringWithCharacters:self.buffer + hexStart length:self.position - hexStart];
        unsigned long long v = strtoull(hex.UTF8String, NULL, 16);
        return @(negative ? -(long long)v : (long long)v);
    }
    NSUInteger intDigits = 0;
    if ([self peek] == '0') {
        [self advance];
    } else if ([self peek] >= '1' && [self peek] <= '9') {
        while ([self peek] >= '0' && [self peek] <= '9') { intDigits++; [self advance]; }
    } else {
        [self fail:@"Invalid number"];
        return nil;
    }
    BOOL isFractional = NO;
    NSUInteger fracDigits = 0;
    if ([self peek] == '.') {
        isFractional = YES;
        [self advance];
        NSUInteger before = self.position;
        while ([self peek] >= '0' && [self peek] <= '9') { fracDigits++; [self advance]; }
        if (self.position == before) { [self fail:@"Invalid number"]; return nil; }
    }
    if ([self peek] == 'e' || [self peek] == 'E') {
        isFractional = YES;
        [self advance];
        if ([self peek] == '+' || [self peek] == '-') [self advance];
        NSUInteger before = self.position;
        while ([self peek] >= '0' && [self peek] <= '9') [self advance];
        if (self.position == before) { [self fail:@"Invalid number"]; return nil; }
    }
    NSString *literal = [NSString stringWithCharacters:self.buffer + start length:self.position - start];
    if (!isFractional) {
        const char *cstr = literal.UTF8String;
        errno = 0;
        char *end = NULL;
        long long ll = strtoll(cstr, &end, 10);
        if (errno == 0 && end && *end == 0)
            return @(ll);
        errno = 0;
        end = NULL;
        unsigned long long ull = strtoull(cstr, &end, 10);
        if (!negative && errno == 0 && end && *end == 0)
            return @(ull);
        return [NSDecimalNumber decimalNumberWithString:literal locale:nil];
    }
    NSUInteger significant = intDigits + fracDigits;
    if (significant <= 17)
        return @(strtod(literal.UTF8String, NULL));
    return [NSDecimalNumber decimalNumberWithString:literal locale:nil];
}

- (BOOL)literalAt:(NSUInteger)index word:(NSString *)word
{
    NSUInteger n = word.length;
    if (index + n > self.length)
        return NO;
    for (NSUInteger i = 0; i < n; i++)
        if (self.buffer[index + i] != [word characterAtIndex:i])
            return NO;
    return YES;
}

@end

static id CharonJSONParse(NSData *data, NSJSONReadingOptions opt, NSError **error)
{
    NSUInteger bom = 0;
    NSStringEncoding encoding = CharonJSONDetectEncoding(data, &bom);
    NSData *body = bom > 0 ? [data subdataWithRange:NSMakeRange(bom, data.length - bom)] : data;
    NSString *string = [[NSString alloc] initWithData:body encoding:encoding];
    if (!string) {
        if (error) *error = CharonJSONError(1, 1, 0, @"The data isn't in the correct text encoding");
        return nil;
    }
    NSUInteger length = string.length;
    unichar *buffer = length > 0 ? malloc(length * sizeof(unichar)) : NULL;
    if (length > 0)
        [string getCharacters:buffer range:NSMakeRange(0, length)];
    CharonJSONReader *reader = [CharonJSONReader new];
    reader.buffer = buffer;
    reader.length = length;
    reader.position = 0;
    reader.line = 1;
    reader.lineStart = 0;
    reader.depth = 0;
    reader.options = opt;

    [reader skipWhitespaceAndComments];
    BOOL topLevelDictionaryAssumed = (opt & (1UL << 4)) != 0;
    id result = nil;
    if (topLevelDictionaryAssumed && reader.position < reader.length && reader.buffer[reader.position] != '{' && reader.buffer[reader.position] != '[') {
        NSString *rest = [string substringFromIndex:reader.position];
        NSString *wrapped = [NSString stringWithFormat:@"{%@}", rest];
        free(buffer);
        NSData *rewrapped = [wrapped dataUsingEncoding:NSUTF8StringEncoding];
        return CharonJSONParse(rewrapped, opt & ~(NSJSONReadingOptions)(1UL << 4), error);
    }
    if (!reader.error) {
        BOOL fragmentsOK = (opt & NSJSONReadingFragmentsAllowed) != 0; // == the deprecated NSJSONReadingAllowFragments, same bit
        if (!fragmentsOK && reader.position < reader.length && reader.buffer[reader.position] != '{' && reader.buffer[reader.position] != '[') {
            [reader fail:@"Invalid value"];
        } else {
            result = [reader parseValue];
        }
    }
    if (!reader.error && result) {
        [reader skipWhitespaceAndComments];
        if (reader.position < reader.length)
            [reader fail:@"Garbage after JSON"];
    }
    free(buffer);
    if (reader.error) {
        if (error) *error = reader.error;
        return nil;
    }
    return result;
}

static BOOL CharonJSONValidValue(id obj, BOOL topLevel)
{
    if (obj == nil)
        return NO;
    if ([obj isKindOfClass:[NSNull class]])
        return !topLevel;
    if ([obj isKindOfClass:[NSNumber class]]) {
        if (topLevel)
            return NO;
        if (CFGetTypeID((CFTypeRef)obj) == CFBooleanGetTypeID())
            return YES;
        const char *type = ((NSNumber *)obj).objCType;
        if ((strcmp(type, @encode(double)) == 0 || strcmp(type, @encode(float)) == 0)) {
            double v = ((NSNumber *)obj).doubleValue;
            return !isnan(v) && !isinf(v);
        }
        return YES;
    }
    if ([obj isKindOfClass:[NSString class]])
        return !topLevel;
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj)
            if (!CharonJSONValidValue(item, NO))
                return NO;
        return YES;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = obj;
        for (id key in dict) {
            if (![key isKindOfClass:[NSString class]] || !CharonJSONValidValue(dict[key], NO))
                return NO;
        }
        return YES;
    }
    return NO;
}

static void CharonJSONWriteString(NSString *s, NSMutableString *out, NSJSONWritingOptions opt)
{
    BOOL escapeSlashes = !(opt & NSJSONWritingWithoutEscapingSlashes);
    [out appendString:@"\""];
    NSUInteger len = s.length;
    if (len > 0) {
        unichar *buf = malloc(len * sizeof(unichar));
        [s getCharacters:buf range:NSMakeRange(0, len)];
        for (NSUInteger i = 0; i < len; i++) {
            unichar c = buf[i];
            switch (c) {
                case '"': [out appendString:@"\\\""]; break;
                case '\\': [out appendString:@"\\\\"]; break;
                case '\n': [out appendString:@"\\n"]; break;
                case '\r': [out appendString:@"\\r"]; break;
                case '\t': [out appendString:@"\\t"]; break;
                case 0x08: [out appendString:@"\\b"]; break;
                case 0x0C: [out appendString:@"\\f"]; break;
                case '/': if (escapeSlashes) [out appendString:@"\\/"]; else [out appendFormat:@"%C", c]; break;
                default:
                    if (c < 0x20)
                        [out appendFormat:@"\\u%04x", c];
                    else
                        [out appendFormat:@"%C", c];
            }
        }
        free(buf);
    }
    [out appendString:@"\""];
}

static void CharonJSONWriteNumber(NSNumber *n, NSMutableString *out)
{
    if (CFGetTypeID((CFTypeRef)n) == CFBooleanGetTypeID()) {
        [out appendString:n.boolValue ? @"true" : @"false"];
        return;
    }
    if ([n isKindOfClass:[NSDecimalNumber class]]) {
        [out appendString:[n descriptionWithLocale:nil]];
        return;
    }
    const char *type = n.objCType;
    if (strcmp(type, @encode(double)) == 0 || strcmp(type, @encode(float)) == 0) {
        double v = n.doubleValue;
        char buf[64];
        snprintf(buf, sizeof buf, "%.17g", v);
        [out appendFormat:@"%s", buf];
        return;
    }
    if (strcmp(type, @encode(unsigned long long)) == 0 || strcmp(type, @encode(unsigned long)) == 0) {
        [out appendFormat:@"%llu", n.unsignedLongLongValue];
        return;
    }
    [out appendFormat:@"%lld", n.longLongValue];
}

static void CharonJSONWriteValue(id obj, NSMutableString *out, NSJSONWritingOptions opt, NSUInteger depth)
{
    if (obj == nil || [obj isKindOfClass:[NSNull class]]) { [out appendString:@"null"]; return; }
    if ([obj isKindOfClass:[NSNumber class]]) {
        if (!(CFGetTypeID((CFTypeRef)obj) == CFBooleanGetTypeID()) && ![obj isKindOfClass:[NSDecimalNumber class]]) {
            const char *type = ((NSNumber *)obj).objCType;
            if (strcmp(type, @encode(double)) == 0 || strcmp(type, @encode(float)) == 0) {
                double v = ((NSNumber *)obj).doubleValue;
                if (isnan(v))
                    [NSException raise:NSInvalidArgumentException format:@"Invalid number value (NaN) in JSON write"];
                if (isinf(v))
                    [NSException raise:NSInvalidArgumentException format:@"Invalid number value (Infinity) in JSON write"];
            }
        }
        CharonJSONWriteNumber(obj, out);
        return;
    }
    if ([obj isKindOfClass:[NSString class]]) { CharonJSONWriteString(obj, out, opt); return; }
    BOOL pretty = (opt & NSJSONWritingPrettyPrinted) != 0;
    NSString *indent = pretty ? [@"" stringByPaddingToLength:(depth + 1) * 2 withString:@" " startingAtIndex:0] : @"";
    NSString *closeIndent = pretty ? [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0] : @"";
    if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *array = obj;
        if (array.count == 0) { [out appendString:@"[]"]; return; }
        [out appendString:pretty ? @"[\n" : @"["];
        NSUInteger i = 0;
        for (id item in array) {
            [out appendString:indent];
            CharonJSONWriteValue(item, out, opt, depth + 1);
            if (++i < array.count) [out appendString:pretty ? @",\n" : @","];
            else if (pretty) [out appendString:@"\n"];
        }
        [out appendString:closeIndent];
        [out appendString:@"]"];
        return;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = obj;
        NSArray *keys = dict.allKeys;
        for (id key in keys)
            if (![key isKindOfClass:[NSString class]])
                [NSException raise:NSInvalidArgumentException format:@"Invalid (non-string) key in JSON dictionary"];
        if ((opt & NSJSONWritingSortedKeys) != 0)
            keys = [keys sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
        if (keys.count == 0) { [out appendString:@"{}"]; return; }
        [out appendString:pretty ? @"{\n" : @"{"];
        NSUInteger i = 0;
        for (NSString *key in keys) {
            [out appendString:indent];
            CharonJSONWriteString(key, out, opt);
            [out appendString:pretty ? @" : " : @":"];
            CharonJSONWriteValue(dict[key], out, opt, depth + 1);
            if (++i < keys.count) [out appendString:pretty ? @",\n" : @","];
            else if (pretty) [out appendString:@"\n"];
        }
        [out appendString:closeIndent];
        [out appendString:@"}"];
        return;
    }
    [NSException raise:NSInvalidArgumentException format:@"Invalid type in JSON write (%@)", NSStringFromClass([obj class])];
}

@implementation NSJSONSerialization

+ (BOOL)isValidJSONObject:(id)obj
{
    return CharonJSONValidValue(obj, YES);
}

+ (nullable NSData *)dataWithJSONObject:(id)obj options:(NSJSONWritingOptions)opt error:(NSError **)error
{
    BOOL fragmentsOK = (opt & NSJSONWritingFragmentsAllowed) != 0;
    if (!(([obj isKindOfClass:[NSArray class]] || [obj isKindOfClass:[NSDictionary class]]) || (fragmentsOK && CharonJSONValidValue(obj, NO))))
        [NSException raise:NSInvalidArgumentException format:@"*** +[NSJSONSerialization dataWithJSONObject:options:error:]: Invalid top-level type in JSON write"];
    NSMutableString *out = [NSMutableString new];
    CharonJSONWriteValue(obj, out, opt, 0);
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}

+ (nullable id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error
{
    return CharonJSONParse(data, opt, error);
}

+ (NSInteger)writeJSONObject:(id)obj toStream:(NSOutputStream *)stream options:(NSJSONWritingOptions)opt error:(NSError **)error
{
    NSData *data = [self dataWithJSONObject:obj options:opt error:error];
    if (!data)
        return 0;
    NSInteger total = 0;
    const uint8_t *bytes = data.bytes;
    NSInteger remaining = (NSInteger)data.length;
    while (remaining > 0) {
        NSInteger written = [stream write:bytes + total maxLength:(NSUInteger)remaining];
        if (written <= 0) {
            if (error) *error = stream.streamError ?: [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil];
            return total;
        }
        total += written;
        remaining -= written;
    }
    return total;
}

+ (nullable id)JSONObjectWithStream:(NSInputStream *)stream options:(NSJSONReadingOptions)opt error:(NSError **)error
{
    NSMutableData *data = [NSMutableData new];
    uint8_t buffer[4096];
    NSInteger read;
    while ((read = [stream read:buffer maxLength:sizeof(buffer)]) > 0)
        [data appendBytes:buffer length:(NSUInteger)read];
    if (read < 0) {
        if (error) *error = stream.streamError ?: [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
        return nil;
    }
    return CharonJSONParse(data, opt, error);
}

@end
