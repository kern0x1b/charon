#import <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>

/* NSDateIntervalFormatter, iOS 8.0, the class whole from the 26.2 header: the six properties that say
   how a range is written - the locale, the calendar and the zone it is written in, the template, and
   the two styles - and the two methods that write one.

   Everything a written form is made of is the release's own: a date and a time are written by the
   release's own NSDateFormatter, under a pattern the release's own CFDateFormat derives from the
   locale and the skeleton, and the two are joined by the rule below. What is left to measure was
   measured, and what is not reproduced is named in facts/Foundation/NSDateIntervalFormatter.md.

   The rule is the release's and not a table: the two endpoints are written, and a part that is the
   same on both is written once. Measured, in the middle of 6 January 2020:

   | the range | what the system writes |
   | --- | --- |
   | under a minute | `1/6/20, 11:40 AM` - one form |
   | 12 hours | `1/6/20, 11:40 AM - 12:40 PM` - the date once, the times twice |
   | across midnight | `1/6/20, 11:40 AM - 1/7/20, 11:40 AM` - both, twice |
   | the same at the long style | `January 6, 2020 at 11:40:00 AM GMT+1 - January 7, 2020 at ...` |

   and the two are separated by U+2009 THIN SPACE, U+2013 EN DASH, U+2009 THIN SPACE, while a date
   and a time of one endpoint keep the release's own U+202F NARROW NO-BREAK SPACE before an am/pm
   marker or a zone. */

@implementation NSDateIntervalFormatter {
    NSLocale *_locale;
    NSCalendar *_calendar;
    NSTimeZone *_timeZone;
    NSString *_dateTemplate;
    NSDateIntervalFormatterStyle _dateStyle;
    NSDateIntervalFormatterStyle _timeStyle;
}

/* The release expands a skeleton itself: +[NSDateFormatter dateFormatFromTemplate:options:locale:],
   which the 26.2 header gives as iOS 4.0, so every release the port carries has it and it is called
   directly. CFDateFormatCreateDateFormatFromTemplate would be the other way in and is deliberately
   not used - it is in no public SDK, so it is a private entry point.

   The separator between the two forms, as the system writes it. The two thin spaces and the en dash
   are the locale's own interval pattern; they are the same in every locale measured. */
static NSString *CharonDateIntervalSeparator(void)
{
    return @"\u2009\u2013\u2009";
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        // The header says both styles are NSDateIntervalFormatterNoStyle and the template is the
        // empty string; the system reads both back as the short style, and its template as the short
        // date and time joined (measured).
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
        // The calendar of the locale, which is what the header documents as the default. The
        // initialiser that takes a locale is not on every release the port carries, so the identifier
        // is read and the locale set.
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
    // The calendar follows the zone, as it does in the system: a formatter given a zone and then asked
    // for its calendar has a calendar in that zone.
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

/* A date and a time, each written by the release's own NSDateFormatter. The formatter is configured
   from a style and not from a pattern where a style is what was asked for, because -[NSDateFormatter
   dateFormat] answers nil for a formatter that was set up with a style: reading the pattern back and
   assigning it is what made every answer here the empty string. The four styles of the header are the
   four date styles of NSDateFormatter, and the NoStyle style writes nothing at all (measured: with both
   styles at NoStyle every answer is the empty string). A template names the date, and the time beside
   it then comes from the locale's short style, which is what the system writes. */
- (NSDateFormatter *)charon_formatterFor:(BOOL)date
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = self.locale;
    // The calendar first and the zone after it: -[NSDateFormatter setCalendar:] adopts the
    // calendar's own zone, so setting the zone first and the calendar second let the calendar's zone
    // win, and a caller that set a zone on the formatter got the machine's instead. The other way
    // round the zone the caller asked for is the one in force.
    formatter.calendar = self.calendar;
    formatter.timeZone = self.timeZone;
    if (_dateTemplate.length) {
        if (date) {
            NSString *pattern = [NSDateFormatter dateFormatFromTemplate:_dateTemplate options:0 locale:self.locale];
            if (pattern.length)
                formatter.dateFormat = pattern;
            else
                formatter.dateStyle = NSDateFormatterShortStyle;
        } else {
            formatter.timeStyle = NSDateFormatterShortStyle;
        }
    } else if (date) {
        // The halves come from the release's own style, which is what answers them exactly: the
        // combined pattern supplies the glue and not the halves, because a skeleton that carries the
        // locale's glue does not always carry its styles - "yMMMdjjm" is "MMM d, y 'at' h:mm a" where
        // the medium time is "h:mm:ss a" (measured).
        formatter.dateStyle = (NSDateFormatterStyle)(_dateStyle ? _dateStyle : NSDateFormatterShortStyle);
    } else {
        formatter.timeStyle = (NSDateFormatterStyle)(_timeStyle ? _timeStyle : NSDateFormatterShortStyle);
    }
    return formatter;
}

/* The date pattern, the glue and the time pattern of one of the header's styles, all three from the
   release's own +[NSDateFormatter dateFormatFromTemplate:options:locale:], which is iOS 4.0 and which
   answers the locale's *combined* pattern with its own glue in it - CLDR's dateTimeFormat - and not a
   pattern this file had to guess. Measured in en_US:

   | the style | the skeleton | what the release answers |
   | --- | --- | --- |
   | short | `yMdjm` | `M/d/y, h:mm a` |
   | medium | `yMMMdjmm` | `MMM d, y 'at' h:mm a` |
   | long | `yMMMMdjmmss` | `MMMM d, y 'at' h:mm:ss a` |
   | full | `yMMMMMMMMdEjmmss` | `EEEE, MMMM d, y 'at' h:mm:ss a zzzz` |

   The combined pattern is split at the first field of the time, keeping whatever is between the two
   halves as the glue - the comma and the space, or the quoted `at` - so the glue is the release's and
   not a rule here. A skeleton the release will not take falls back to its short date. */
static NSString *charon_splitCombined(NSString *combined, NSString **date, NSString **glue, NSString **time)
{
    // The fields that belong to a time. M is not among them: an upper-case M is a month, and the
    // minute is the lower-case m, so with M in the set the split landed inside the MMM of a date and
    // left the join out of the answer entirely.
    static NSString *fields = @"hHkKmsSaAB";
    NSUInteger length = combined.length, index = 0;
    BOOL quoted = NO;
    for (; index < length; index++) {
        unichar c = [combined characterAtIndex:index];
        if (c == '\'') { quoted = !quoted; continue; }
        if (quoted)
            continue;
        if ([[NSCharacterSet characterSetWithCharactersInString:fields] characterIsMember:c] && index > 0)
            break;
    }
    if (index == 0 || index >= length) {
        // Nothing but a time, or nothing at all.
        *date = @"";
        *glue = @"";
        *time = combined;
        return combined;
    }
    // The glue is whatever stands between the end of the last field of the date and the first field
    // of the time, quoted literals included whole. Walking back from the time one character at a time
    // stopped at the first letter, which for a locale that *names* the join - en_US writes
    // "MMM d, y 'at' h:mm a" - is inside the literal and left the join out of the answer.
    NSUInteger lastField = 0;
    quoted = NO;
    for (NSUInteger scan = 0; scan < index; scan++) {
        unichar c = [combined characterAtIndex:scan];
        if (c == '\'') { quoted = !quoted; continue; }
        if (quoted)
            continue;
        if (c != ' ' && c != '\'' && c != ',' && c != ';' && c != 0x3001)
            lastField = scan + 1;
    }
    NSUInteger start = lastField;
    while (start > 0 && [combined characterAtIndex:start - 1] == ' ')
        start--;
    *date = [combined substringToIndex:start];
    // A quoted run in a pattern is a literal, so its quotes are markers and not part of what the
    // pattern writes: en_US's medium join is 'at' in the pattern and " at " in the answer.
    NSMutableString *join = [NSMutableString string];
    for (NSUInteger scan = start; scan < index; scan++) {
        unichar c = [combined characterAtIndex:scan];
        if (c != '\'')
            [join appendFormat:@"%C", c];
    }
    *glue = join;
    *time = [combined substringFromIndex:index];
    return combined;
}

- (void)charon_patternsWithDate:(NSString **)date glue:(NSString **)glue time:(NSString **)time
{
    static NSString *skeletons[] = {@"yMd", @"yMdjm", @"yMMMdjmm", @"yMMMMdjmmss", @"yMMMMMMMMdEjmmss"};
    NSInteger which = (NSInteger)_dateStyle;
    if (which < 0 || which > 4)
        which = 1;
    NSString *combined = [NSDateFormatter dateFormatFromTemplate:skeletons[which] options:0 locale:self.locale];
    if (!combined.length)
        combined = [NSDateFormatter dateFormatFromTemplate:@"yMdjm" options:0 locale:self.locale];
    charon_splitCombined(combined, date, glue, time);
    if (!(*time).length) {
        *date = @"";
        *glue = @"";
    }
}

- (void)charon_date:(NSString **)date time:(NSString **)time of:(NSDate *)when
{
    *date = _dateStyle == NSDateIntervalFormatterNoStyle ? @"" : [[self charon_formatterFor:YES] stringFromDate:when];
    *time = _timeStyle == NSDateIntervalFormatterNoStyle ? @"" : [[self charon_formatterFor:NO] stringFromDate:when];
}

/* The day period a written time ends with - " AM", " PM", " in the afternoon" - or the empty string
   when the style writes none. It is the last whitespace-delimited word of the time, which the release
   writes after a U+202F NARROW NO-BREAK SPACE. */
static NSString *charon_dayPeriod(NSString *time)
{
    NSRange space = [time rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] options:NSBackwardsSearch];
    if (space.location == NSNotFound)
        return @"";
    return [time substringFromIndex:space.location];
}

- (NSString *)charon_write:(NSDate *)from to:(NSDate *)to
{
    if (!from || !to)
        return nil;
    NSString *firstDate = nil, *firstTime = nil, *secondDate = nil, *secondTime = nil;
    [self charon_date:&firstDate time:&firstTime of:from];
    [self charon_date:&secondDate time:&secondTime of:to];
    NSString *separator = CharonDateIntervalSeparator();
    BOOL sameDate = [firstDate isEqualToString:secondDate];
    BOOL sameTime = [firstTime isEqualToString:secondTime];
    BOOL one = sameDate && sameTime;
    NSString *patternDate = nil, *patternGlue = nil, *patternTime = nil;
    [self charon_patternsWithDate:&patternDate glue:&patternGlue time:&patternTime];
    // Where the two endpoints are one form the join is the release's own, the literal of its combined
    // pattern; where the range is written as a range every join is a comma and a space, which is the
    // release's answer there too ("Jan 6, 2020 at 10:40:00 AM" and "Jan 6, 2020, 10:40:00 AM -
    // 10:41:00 AM", measured).
    // The release's own join, the literal of its combined pattern, wherever the range spans a date or
    // is one form; and a comma and a space where the two endpoints are on one day and only the times
    // differ, which is what the release writes there ("Jan 6, 2020 at 10:40:00 AM -
    // 10:41:00 AM" against "Jan 6, 2020, 10:40:00 AM - 10:41:00 AM", measured).
    NSString *glue = firstDate.length ? ((sameDate && !one) ? @", " : patternGlue) : @"";
    if (one)
        return [NSString stringWithFormat:@"%@%@%@", firstDate, glue, firstTime];
    if (sameDate) {
        /* A field that is the same on both endpoints is written once, and the day period is such a
           field: the host writes an hour apart in the short style as "1/6/20, 10:40 - 10:41 AM" and
           not as "10:40 AM - 10:41 AM" (measured), so the marker moves off the first time and onto
           the second. Two times whose periods differ keep both, which is what a range that crosses
           noon does. */
        // Only the short style moves it: the host's short interval pattern is "h:mm - h:mm a" and its
        // medium and long ones are "h:mm:ss a - h:mm:ss a" (measured), so the marker stays on both
        // wherever the style writes it on both.
        NSString *period = _dateStyle == NSDateIntervalFormatterShortStyle ? charon_dayPeriod(firstTime) : @"";
        if (period.length && period.length == charon_dayPeriod(secondTime).length &&
            [[firstTime substringFromIndex:firstTime.length - period.length]
                isEqualToString:[secondTime substringFromIndex:secondTime.length - period.length]]) {
            firstTime = [firstTime substringToIndex:firstTime.length - period.length];
            while (firstTime.length && [firstTime hasSuffix:@"\u202f"])
                firstTime = [firstTime substringToIndex:firstTime.length - 6];
        }
        return [NSString stringWithFormat:@"%@%@%@%@%@", firstDate, glue, firstTime, separator, secondTime];
    }
    return [NSString stringWithFormat:@"%@%@%@%@%@%@%@", firstDate, glue, firstTime, separator, secondDate,
                                                  secondDate.length ? patternGlue : @"", secondTime];
}

- (NSString *)stringFromDate:(NSDate *)fromDate toDate:(NSDate *)toDate
{
    return [self charon_write:fromDate to:toDate];
}

- (NSString *)stringFromDateInterval:(NSDateInterval *)dateInterval
{
    if (!dateInterval)
        return nil;
    return [self charon_write:dateInterval.startDate to:dateInterval.endDate];
}

@end
