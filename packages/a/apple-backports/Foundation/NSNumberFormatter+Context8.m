#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

/* The minimum grouping digits of a number formatter, and its formatting context.

   The minimum grouping digits are applied: they decide which of the groups the release's formatter
   wrote are long enough to keep a separator. The host's own default is 1 (measured: a fresh formatter
   answers 1), so 1.234 keeps its separator, and a formatter that asks for 2 takes the separator off a
   three digit group.

   The formatting context is kept and answered, and is not applied to the digits: the line direction
   contexts that move a negative sign arrived with iOS 26 and the release's own number formatting has
   no such context, so a port that moved the sign would be writing something the release's formatter
   does not. The value the application sets is the value it reads back, which is the whole of what the
   property is on this release; facts/Foundation/NSNumberFormatterContext.md says so. */

static char CharonNumberFormatterContextKey;
static char CharonNumberFormatterGroupingKey;

static NSString *charon_grouped(NSString *text, NSUInteger minimum)
{
    /* Read from the back, so a group of digits is known before the separator that follows it is
       written or taken off. The release's own separator is the first character that is not a digit. */
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    NSString *separator = nil;
    for (NSUInteger index = 0; index < text.length && !separator; index++) {
        unichar character = [text characterAtIndex:index];
        if (![digits characterIsMember:character])
            separator = [text substringWithRange:NSMakeRange(index, 1)];
    }
    if (!separator)
        return text;
    NSMutableString *out = [NSMutableString stringWithCapacity:text.length];
    NSUInteger run = 0;
    for (NSUInteger index = text.length; index-- > 0;) {
        unichar character = [text characterAtIndex:index];
        if ([digits characterIsMember:character]) {
            run++;
            [out insertString:[NSString stringWithFormat:@"%C", character] atIndex:0];
            continue;
        }
        if (run >= minimum && run)
            [out insertString:separator atIndex:0];
        run = 0;
        [out insertString:[NSString stringWithFormat:@"%C", character] atIndex:0];
    }
    return out;
}

/* The release's own formatting, reached the way the runtime reaches a superclass's implementation: a
   category's [super] would be NSObject's. */
static NSString *charon_release_string(NSNumberFormatter *formatter, NSNumber *number)
{
    struct objc_super super = { .receiver = formatter, .super_class = [NSNumberFormatter class] };
    return ((NSString * (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&super, @selector(stringFromNumber:), number);
}

@implementation NSNumberFormatter (CharonContext)

- (NSFormattingContext)formattingContext
{
    NSNumber *stored = objc_getAssociatedObject(self, &CharonNumberFormatterContextKey);
    return (NSFormattingContext)(stored ? stored.integerValue : NSFormattingContextUnknown);
}

- (void)setFormattingContext:(NSFormattingContext)context
{
    objc_setAssociatedObject(self, &CharonNumberFormatterContextKey, @(context), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSUInteger)minimumGroupingDigits
{
    NSNumber *stored = objc_getAssociatedObject(self, &CharonNumberFormatterGroupingKey);
    return stored ? stored.unsignedIntegerValue : 1;
}

- (void)setMinimumGroupingDigits:(NSUInteger)digits
{
    objc_setAssociatedObject(self, &CharonNumberFormatterGroupingKey, @(digits), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

/* Read by name, for the same reason as the progress's handler: the rewriter renames the selector. */
- (NSUInteger)charon_numberFormatterMinimumGroupingDigits
{
    return [self minimumGroupingDigits];
}

- (NSString *)stringFromNumber:(NSNumber *)number
{
    NSString *text = charon_release_string(self, number);
    if (!text)
        return text;
    return charon_grouped(text, [self charon_numberFormatterMinimumGroupingDigits]);
}

@end
