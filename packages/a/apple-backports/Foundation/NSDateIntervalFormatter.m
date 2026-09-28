#import <Foundation/Foundation.h>
#include <stdint.h>

/* NSDateIntervalFormatter, iOS 8.0, the class whole from the 26.2 header: the six properties that say
   how a range is written - the locale, the calendar and the zone it is written in, the template, and
   the two styles - and the two methods that write one.

   The class is the release's own DateIntervalFormat underneath. The four ICU entry points are
   exported by the release's libicucore from iOS 5.0 on and by none before it, measured over the whole
   armv7 cache ladder:

   | release | libicucore exports | _udtitvfmt_* |
   | --- | --- | --- |
   | 4.3 | 4727 | 0 |
   | 5.0 | 5187 | 4 |
   | 6.0 | 5311 | 4 |
   | 6.1.3 | 5311 | 4 |
   | 7.0 | 5459 | 4 |
   | 8.0 | 6195 | 4 |
   | 9.0 | 6472 | 4 |
   | 10.0.1 | 6710 | 4 |

   and 6.1.3 links icudt49_dat, so its udtitvfmt_open is ICU 49's six-argument form with a
   `const char *locale` first. So the joins, the collapse of a shared day, the way the two ends of a
   range are written and every locale's own choice of them are the release's answers and not a table
   here, which is why the class is a thin wrapper and why the header's own examples of what a skeleton
   produces need nothing reproduced: the release's DateIntervalFormat produces them.

   **device-unverified.** Every expected answer is the host's own NSDateIntervalFormatter's, written
   out by tests/backports/device/dateinterval/make-expected.m into
   tests/backports/device/dateinterval/expected.txt - fifteen locales, every pair of the five styles,
   the same-day, different-day and different-year pairs, and three zones - and
   tests/backports/device/dateinterval.m runs the port on a device and compares its output with that
   file line by line. **That device run has not happened.** The host's own libicucore refuses the
   call the port makes - it answers U_ILLEGAL_ARGUMENT_ERROR for every skeleton - so a macOS
   differential cannot hold this path and none is claimed: the port's answers are the release's ICU
   called the way the release's own class calls it, and the check that proves it is the device run.

   4.3 does not carry the class, and the reason is the table above: its libicucore exports no
   udtitvfmt_*. A 4.3 path would mean vendoring ICU, which is a later item. */

typedef double CharonUDate;
typedef void *CharonUDateIntervalFormat;
typedef int32_t CharonUErrorCode;

extern CharonUDateIntervalFormat udtitvfmt_open(const char *locale, const uint16_t *skeleton, int32_t skeletonLength,
                                               const uint16_t *tzID, int32_t tzIDLength, CharonUErrorCode *status);
extern void udtitvfmt_close(CharonUDateIntervalFormat *formatter);
extern int32_t udtitvfmt_format(const CharonUDateIntervalFormat *formatter, CharonUDate fromDate, CharonUDate toDate,
                                 uint16_t *result, int32_t resultCapacity, void *position, CharonUErrorCode *status);

/* The date and the time skeleton of each of the header's five styles, the way the release's own
   NSDateFormatter writes them. A style pair is the two skeletons joined, the date's fields first and
   each field letter once, which is what a skeleton is. The NoStyle style contributes nothing, so a
   pair with either half at NoStyle is a skeleton of the other half alone. */
static NSString *CharonDateSkeleton(NSInteger style)
{
    switch (style) {
        case 1: return @"yMd";
        case 2: return @"yMMMd";
        case 3: return @"yMMMMd";
        case 4: return @"yMMMMdE";
        default: return @"";
    }
}

static NSString *CharonTimeSkeleton(NSInteger style)
{
    switch (style) {
        case 1: return @"jm";
        case 2: return @"jmms";
        case 3: return @"jmmsz";
        case 4: return @"jmmszzzz";
        default: return @"";
    }
}

/* The two skeletons joined, each field letter once and the date's fields first. */
static NSString *CharonIntervalSkeleton(NSInteger dateStyle, NSInteger timeStyle, NSString *template)
{
    if (template.length)
        return template;
    NSString *date = CharonDateSkeleton(dateStyle), *time = CharonTimeSkeleton(timeStyle);
    NSMutableString *out = [NSMutableString string];
    for (NSString *half in @[date, time])
        for (NSUInteger index = 0; index < half.length; index++) {
            unichar field = [half characterAtIndex:index];
            NSString *letter = [NSString stringWithFormat:@"%C", field];
            if ([out rangeOfString:letter].location == NSNotFound)
                [out appendString:letter];
        }
    return out;
}

@implementation NSDateIntervalFormatter {
    NSLocale *_locale;
    NSCalendar *_calendar;
    NSTimeZone *_timeZone;
    NSString *_dateTemplate;
    NSDateIntervalFormatterStyle _dateStyle;
    NSDateIntervalFormatterStyle _timeStyle;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        // The header says both styles are NSDateIntervalFormatterNoStyle and the template is the
        // empty string; the host reads both styles back as the short style, and an empty template.
        _dateStyle = NSDateIntervalFormatterShortStyle;
        _timeStyle = NSDateIntervalFormatterShortStyle;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    NSDateIntervalFormatter *copy = [[[self class] allocWithZone:zone] init];
    copy->_locale = [_locale copy];
    copy->_calendar = [_calendar copy];
    copy->_timeZone = [_timeZone copy];
    copy->_dateTemplate = [_dateTemplate copy];
    copy->_dateStyle = _dateStyle;
    copy->_timeStyle = _timeStyle;
    return copy;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self)
        return nil;
    _locale = [[coder decodeObjectForKey:@"NS.locale"] copy];
    _calendar = [[coder decodeObjectForKey:@"NS.calendar"] copy];
    _timeZone = [[coder decodeObjectForKey:@"NS.timeZone"] copy];
    _dateTemplate = [[coder decodeObjectForKey:@"NS.dateTemplate"] copy];
    _dateStyle = (NSDateIntervalFormatterStyle)[coder decodeIntegerForKey:@"NS.dateStyle"];
    _timeStyle = (NSDateIntervalFormatterStyle)[coder decodeIntegerForKey:@"NS.timeStyle"];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_locale forKey:@"NS.locale"];
    [coder encodeObject:_calendar forKey:@"NS.calendar"];
    [coder encodeObject:_timeZone forKey:@"NS.timeZone"];
    [coder encodeObject:_dateTemplate forKey:@"NS.dateTemplate"];
    [coder encodeInteger:(NSInteger)_dateStyle forKey:@"NS.dateStyle"];
    [coder encodeInteger:(NSInteger)_timeStyle forKey:@"NS.timeStyle"];
}

- (NSLocale *)locale
{
    return _locale ?: [NSLocale currentLocale];
}

- (void)setLocale:(NSLocale *)locale
{
    _locale = [locale copy];
}

- (NSCalendar *)calendar
{
    if (!_calendar) {
        _calendar = [[NSCalendar alloc] initWithCalendarIdentifier:self.locale.calendarIdentifier];
        _calendar.locale = self.locale;
        _calendar.timeZone = self.timeZone;
    }
    return _calendar;
}

- (void)setCalendar:(NSCalendar *)calendar
{
    _calendar = [calendar copy];
}

- (NSTimeZone *)timeZone
{
    return _timeZone ?: [NSTimeZone defaultTimeZone];
}

- (void)setTimeZone:(NSTimeZone *)timeZone
{
    _timeZone = [timeZone copy];
    if (_calendar && ![_calendar.timeZone isEqual:timeZone])
        _calendar.timeZone = timeZone;
}

- (NSString *)dateTemplate
{
    return _dateTemplate ?: @"";
}

- (void)setDateTemplate:(NSString *)dateTemplate
{
    _dateTemplate = [dateTemplate copy];
}

- (NSDateIntervalFormatterStyle)dateStyle
{
    return _dateStyle;
}

- (void)setDateStyle:(NSDateIntervalFormatterStyle)dateStyle
{
    _dateStyle = dateStyle;
}

- (NSDateIntervalFormatterStyle)timeStyle
{
    return _timeStyle;
}

- (void)setTimeStyle:(NSDateIntervalFormatterStyle)timeStyle
{
    _timeStyle = timeStyle;
}

- (NSString *)charon_intervalFrom:(NSDate *)from to:(NSDate *)to
{
    NSString *skeleton = CharonIntervalSkeleton((NSInteger)_dateStyle, (NSInteger)_timeStyle, _dateTemplate);
    if (!skeleton.length)
        return @"";
    /* The zone is the formatter's, in the UChar form the entry point takes; the locale is the
       formatter's locale as the NUL-terminated bytes it takes. */
    NSString *zone = self.timeZone.name ?: @"GMT";
    uint16_t skeletonChars[256], zoneChars[256];
    int32_t skeletonLength = 0, zoneLength = 0;
    for (NSUInteger index = 0; index < skeleton.length && index < 255; index++)
        skeletonChars[skeletonLength++] = (uint16_t)[skeleton characterAtIndex:index];
    for (NSUInteger index = 0; index < zone.length && index < 255; index++)
        zoneChars[zoneLength++] = (uint16_t)[zone characterAtIndex:index];

    CharonUErrorCode status = 0;
    CharonUDateIntervalFormat formatter =
        udtitvfmt_open(self.locale.localeIdentifier.UTF8String, skeletonChars, skeletonLength,
                       zoneChars, zoneLength, &status);
    if (status != 0 || !formatter)
        return nil;
    uint16_t buffer[512];
    status = 0;
    int32_t written = udtitvfmt_format(&formatter, (CharonUDate)from.timeIntervalSinceReferenceDate,
                                       (CharonUDate)to.timeIntervalSinceReferenceDate, buffer, 512, NULL, &status);
    CharonUDateIntervalFormat closing = formatter;
    udtitvfmt_close(&closing);
    if (status != 0 || written <= 0)
        return nil;
    return [[NSString alloc] initWithCharacters:(const unichar *)buffer length:(NSUInteger)written];
}

- (NSString *)stringFromDate:(NSDate *)fromDate toDate:(NSDate *)toDate
{
    if (!fromDate || !toDate)
        return nil;
    return [self charon_intervalFrom:fromDate to:toDate];
}

- (NSString *)stringFromDateInterval:(NSDateInterval *)dateInterval
{
    if (!dateInterval)
        return nil;
    return [self charon_intervalFrom:dateInterval.startDate to:dateInterval.endDate];
}

@end
