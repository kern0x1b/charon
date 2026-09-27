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

/* The minimum grouping digits are ICU's rule, and it is all or nothing: the integer part is grouped
   at all when it has at least `grouping size + minimum` digits, and then every separator the release
   wrote stays. Which is what the host answers, measured over five numbers, five thresholds and three
   locales by tests/backports/host/foundationbatch: 1,234 is four digits and is not grouped at a
   minimum of two (4 < 3 + 2), while 1,234,567 is seven digits and keeps both of its separators at
   every threshold (7 >= 3 + 4 at four). The grouping size is the release's own, three, which is what
   the separators it wrote show. */
/* The digits of the integer part, which is everything before the locale's own decimal separator --
   and not before a grouping separator, which is part of the integer part too. */
static NSUInteger charon_integer_digits(NSString *text, NSString *decimal)
{
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    NSString *integer = text;
    NSRange point = decimal.length ? [text rangeOfString:decimal] : NSMakeRange(NSNotFound, 0);
    if (point.location != NSNotFound)
        integer = [text substringToIndex:point.location];
    NSUInteger seen = 0;
    for (NSUInteger index = 0; index < integer.length; index++)
        if ([digits characterIsMember:[integer characterAtIndex:index]])
            seen++;
    return seen;
}

static NSString *charon_grouped(NSString *text, NSLocale *locale, NSUInteger minimum)
{
    NSString *decimal = locale.decimalSeparator;
    if (charon_integer_digits(text, decimal) >= 3 + minimum)
        return text; /* enough digits for every group, so every separator the release wrote stays */
    /* Not enough digits to group at all, so the release's grouping separators come off. Which
       character those are is the locale's own answer rather than a guess: en_US groups with a comma
       and de_DE with a full stop, and a full stop is also the decimal separator in de_DE, so the two
       cannot be told apart by looking at the number. */
    NSString *grouping = locale.groupingSeparator;
    if (!grouping.length)
        return text;
    NSArray *parts = [text componentsSeparatedByString:grouping];
    if (parts.count < 2)
        return text;
    return [parts componentsJoinedByString:@""];
}

/* The release's own formatting, reached the way the runtime reaches a superclass's implementation: a
   category's [super] would be NSObject's. */
static NSString *charon_release_string(NSNumberFormatter *formatter, NSNumber *number)
{
    struct objc_super super = { .receiver = formatter, .super_class = [NSNumberFormatter class] };
    return ((NSString * (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&super, @selector(stringFromNumber:), number);
}



@interface NSNumberFormatter (CharonGrouping)
/* The locale whose separators the grouping reads, read by name so that the selector rewriter can
   rename it: a category cannot reach a method through dot syntax when the method is renamed. */
- (NSLocale *)charon_groupingLocale;
@end

@implementation NSNumberFormatter (CharonContext)

- (NSLocale *)charon_groupingLocale
{
    return self.locale ?: [NSLocale currentLocale];
}

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
    return charon_grouped(text, [self charon_groupingLocale], [self charon_numberFormatterMinimumGroupingDigits]);
}

@end
