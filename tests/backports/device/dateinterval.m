// dateinterval.m - NSDateIntervalFormatter on the release the program runs on, against the golden file. A command-line
// program: build it as a daemon target that requires charon@apple-backports and run it with
// `xmake emulate -r 6.1.3 run /usr/libexec/dateinterval <path to expected.txt>`.
//
// Every expected answer in the file is the host's own NSDateIntervalFormatter's, written out by dateinterval/make-expected.m
// over fifteen locales x the twenty-five pairs of the five styles x three zones x three date pairs - 3375 cases. The class
// here is the port's, which is the release's own DateIntervalFormat underneath (udtitvfmt_*, exported by the release's
// libicucore from iOS 5.0 on, measured), so the answers are the release's and the golden file is what holds them.
//
// The class arrived in iOS 8.0 and the port carries it from 5.0, so on a release from 5.0 to 7.x the class is the port's and
// every case runs; from 8.0 on the release's own class is the one linked and the same comparison is the check that it
// behaves as the port says it does.
//
// The comparison is line by line and the order is the one make-expected.m wrote, so a line that differs names its own case.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>
#import "check.h"

static NSArray *SplitLine(NSString *line)
{
    return [line componentsSeparatedByString:@"\t"];
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        charon_log_to(argc > 1 ? [NSString stringWithUTF8String:argv[1]] : nil);
        NSString *path = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : nil;
        if (!path) {
            printf("dateinterval: no golden file given\n");
            return 1;
        }
        NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        CHECK(contents != nil, "the golden file is there");
        if (!contents)
            return 1;

        // One class, from whichever image the band linked: the port's below 8.0 and the release's from there.
        Class formatterClass = NSClassFromString(@"NSDateIntervalFormatter");
        if (!formatterClass) {
            // The class floor is 5.0 and below6's "ported" cell builds at 4.3, where band() leaves the
            // object out and the release's own Foundation has no such class. A 4.3 run has nothing to
            // compare and says so; it is not a failure of the port (the review's finding F).
            printf("dateinterval: no NSDateIntervalFormatter on this release, which is below the 5.0 floor\n");
            return 0;
        }
        BOOL ported = strstr(class_getImageName(formatterClass), "FoundationBackports") != NULL;

        NSArray *lines = [contents componentsSeparatedByString:@"\n"];
        NSUInteger compared = 0, differing = 0;
        for (NSString *line in lines) {
            if (!line.length)
                continue;
            NSArray *fields = SplitLine(line);
            if (fields.count < 7) {
                CHECK(NO, "a line of the golden file has its seven fields");
                continue;
            }
            NSLocale *locale = [NSLocale localeWithLocaleIdentifier:fields[0]];
            NSInteger dateStyle = [fields[1] integerValue], timeStyle = [fields[2] integerValue];
            NSTimeZone *zone = [NSTimeZone timeZoneWithName:fields[3]];
            NSDate *from = [NSDate dateWithTimeIntervalSinceReferenceDate:[fields[4] doubleValue]];
            NSDate *to = [NSDate dateWithTimeIntervalSinceReferenceDate:[fields[5] doubleValue]];
            NSArray *rest = [fields subarrayWithRange:NSMakeRange(6, fields.count - 6)];
            NSString *expected = [rest componentsJoinedByString:@"\t"];

            id formatter = [[formatterClass alloc] init];
            [formatter setValue:locale forKey:@"locale"];
            [formatter setValue:@(dateStyle) forKey:@"dateStyle"];
            [formatter setValue:@(timeStyle) forKey:@"timeStyle"];
            [formatter setValue:zone forKey:@"timeZone"];
            NSString *answer = [formatter stringFromDate:from toDate:to];
            compared++;
            if (![answer isEqualToString:expected]) {
                differing++;
                // The first twenty, so a systematic difference is readable and not a wall.
                if (differing <= 20) {
                    NSString *mine = [answer description];
                    NSString *note = [NSString stringWithFormat:@"%@ %ld %ld %@ expected [%@] got [%@]",
                                      fields[0], (long)dateStyle, (long)timeStyle, fields[3], expected, mine];
                    printf("  %s\n", [note UTF8String]);
                }
            }
            // The two methods, not one: the interval of the class carries the same answer as the pair of dates.
            SEL withInterval = NSSelectorFromString(@"stringFromDateInterval:");
            if ([formatter respondsToSelector:withInterval]) {
                Class intervalClass = NSClassFromString(@"NSDateInterval");
                id interval = [[intervalClass alloc] initWithStartDate:from endDate:to];
                NSString *viaInterval = [formatter performSelector:withInterval withObject:interval];
                if (viaInterval)
                    CHECK([viaInterval isEqualToString:answer], "the interval and the pair of dates agree");
            }
        }
        printf("dateinterval: %s, compared %lu cases, %lu differing\n", ported ? "the port's class" : "the release's class",
               (unsigned long)compared, (unsigned long)differing);
        CHECK(differing == 0, "every case is the answer the golden file holds");
        printf("checks=%d failures=%d\n", charon_checks, charon_failures);
        return charon_failures;
    }
}
