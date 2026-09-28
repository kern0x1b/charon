// make-expected.m - the host's own NSDateIntervalFormatter, asked the whole case table, written out as the golden file the
// device test compares the port against. Built and run on a macOS host, never on a device: the answers are the host's own
// class's, which is what tests/backports/host/ cannot hold because the host's libicucore refuses the call the port makes.
//
//   xcrun clang -fobjc-arc -Wno-deprecated-declarations -o make-expected make-expected.m -framework Foundation
//   ./make-expected > expected.txt
//
// One line per case, in a fixed order so a diff means something: the locale, the two styles, the zone and the pair, then a tab
// and the answer. Fifteen locales x the pairs of the five styles x three pairs x three zones.

#import <Foundation/Foundation.h>

static NSArray *kLocales(void)
{
    return @[@"en_US", @"en_GB", @"en_AU", @"en_CA", @"en_IN", @"de_DE", @"fr_FR", @"es_MX", @"it_IT",
              @"pt_BR", @"ja_JP", @"ko_KR", @"zh_CN", @"ru_RU", @"ar_EG"];
}

static NSArray *kZones(void)
{
    return @[@"UTC", @"America/New_York", @"Europe/Warsaw"];
}

/* Three pairs, chosen to reach the three shapes of answer: inside one day, across a day, across a year. */
static NSArray *kPairs(void)
{
    NSMutableArray *pairs = [NSMutableArray array];
    // The middle of 6 January 2020, 10:40 UTC, so the same-day pair is inside one day and the rest are not.
    NSDate *start = [NSDate dateWithTimeIntervalSinceReferenceDate:600000000];
    [pairs addObject:@[start, [start dateByAddingTimeInterval:3600]]];                        // one hour, same day
    [pairs addObject:@[start, [start dateByAddingTimeInterval:93600]]];                       // across midnight
    [pairs addObject:@[start, [start dateByAddingTimeInterval:31622400]]];                    // into the next year
    return pairs;
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        NSArray *zones = kZones(), *pairs = kPairs();
        NSUInteger cases = 0;
        for (NSString *identifier in kLocales()) {
            NSLocale *locale = [NSLocale localeWithLocaleIdentifier:identifier];
            for (NSInteger dateStyle = 0; dateStyle <= 4; dateStyle++) {
                for (NSInteger timeStyle = 0; timeStyle <= 4; timeStyle++) {
                    for (NSString *zone in zones) {
                        for (NSArray *pair in pairs) {
                            NSDateIntervalFormatter *formatter = [[NSDateIntervalFormatter alloc] init];
                            formatter.locale = locale;
                            formatter.dateStyle = (NSDateIntervalFormatterStyle)dateStyle;
                            formatter.timeStyle = (NSDateIntervalFormatterStyle)timeStyle;
                            formatter.timeZone = [NSTimeZone timeZoneWithName:zone];
                            NSString *answer = [formatter stringFromDate:pair[0] toDate:pair[1]];
                            // A tab and a newline are the only characters that would make a line ambiguous.
                            NSString *safe = [[answer stringByReplacingOccurrencesOfString:@"\t" withString:@" "]
                                                 stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
                            printf("%s\t%ld\t%ld\t%s\t%ld\t%ld\t%s\n", identifier.UTF8String, (long)dateStyle,
                                   (long)timeStyle, zone.UTF8String, (long)[pair[0] timeIntervalSinceReferenceDate],
                                   (long)[pair[1] timeIntervalSinceReferenceDate], safe.UTF8String);
                            cases++;
                        }
                    }
                }
            }
        }
        fprintf(stderr, "%lu cases\n", (unsigned long)cases);
    }
    return 0;
}
