// locales-probe.m - the locale identifiers the release itself presents: +[NSLocale availableLocaleIdentifiers].
// Read on 6.1.3, because the table's locale set is the release's and not the host's.
#import <Foundation/Foundation.h>
#include <stdio.h>
int main(void) { @autoreleasepool {
    NSArray *identifiers = [NSLocale availableLocaleIdentifiers];
    printf("availableLocaleIdentifiers: %lu\n", (unsigned long)identifiers.count);
    for (NSString *identifier in [identifiers sortedArrayUsingSelector:@selector(compare:)])
        printf("%s\n", [identifier UTF8String]);
    printf("the current locale presents: %s\n", [[NSLocale currentLocale].localeIdentifier UTF8String]);
} return 0; }
