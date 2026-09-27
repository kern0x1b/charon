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
    /* The release's formatter has already grouped by its own rule. What the minimum asks for on top of
       that is which of the separators it wrote belong to a group long enough: a separator whose group
       is shorter than the minimum is taken off, and none is ever added, because a number the release
       wrote without a separator has no group to decide about. A separator is a character with digits
       on both sides of it -- so a sign, which has none before it, and a point, which the locale put
       there, are copied as they are. */
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    NSMutableString *out = [NSMutableString stringWithCapacity:text.length];
    NSUInteger run = 0;
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        if ([digits characterIsMember:character]) {
            run++;
            [out appendFormat:@"%C", character];
            continue;
        }
        /* A grouping separator always has whole groups of three after it; the locale's own decimal
           separator has one digit after it, and a sign has no digits before it, so neither of those
           is mistaken for one. */
        NSUInteger after = 0;
        while (index + 1 + after < text.length && [digits characterIsMember:[text characterAtIndex:index + 1 + after]])
            after++;
        if (run > 0 && after > 0 && (after % 3) == 0 && run < minimum) {
            run = 0;
            continue; /* a separator whose group is too short to keep one */
        }
        run = 0;
        [out appendFormat:@"%C", character];
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
