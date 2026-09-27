#import <Foundation/Foundation.h>
#import <objc/runtime.h>

/* The two ways of reading a URL string that percent-encode what a URL cannot carry. The rule is the
   one the release's own URL grammar uses, and the answer for a string that still cannot be read
   afterwards is nil, which is what the host answers with the flag off (measured: "https://
   example.com/a b" is nil, "https://example.com/a%20b" is a URL). */

static NSString *charon_url_escaped(NSString *text)
{
    NSMutableString *out = [NSMutableString stringWithCapacity:text.length];
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        if ((character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') ||
            (character >= '0' && character <= '9') || character == '-' || character == '.' ||
            character == '_' || character == '~' || character == ':' || character == '/' ||
            character == '?' || character == '#' || character == '[' || character == ']' ||
            character == '@' || character == '!' || character == '$' || character == '&' ||
            character == '\'' || character == '(' || character == ')' || character == '*' ||
            character == '+' || character == ',' || character == ';' || character == '=' || character == '%') {
            [out appendFormat:@"%C", character];
            continue;
        }
        [out appendFormat:@"%%%02X", character];
    }
    return out;
}

@implementation NSURL (CharonEncoding)

+ (NSURL *)URLWithString:(NSString *)string encodingInvalidCharacters:(BOOL)encoding
{
    if (encoding)
        string = charon_url_escaped(string);
    return [self URLWithString:string];
}

- (instancetype)initWithString:(NSString *)string encodingInvalidCharacters:(BOOL)encoding
{
    if (encoding)
        string = charon_url_escaped(string);
    return [self initWithString:string];
}

@end
