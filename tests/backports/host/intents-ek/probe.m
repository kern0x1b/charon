// probe.m - what the host RUNTIME does with -[INDateComponentsRange initWithEKRecurrenceRule:] and its getter
// -[INDateComponentsRange EKRecurrenceRule]: which object the getter answers, and what the recurrence rule the range
// keeps (INRecurrenceRule, the Intents type) holds.
//
// Every Intents selector is looked up by name at run time, so the header of the framework is not what decides the
// answer. EventKit is a real framework here: EKRecurrenceRule is built with its own public initialiser.
//
//   xcrun clang -fno-objc-arc -framework Foundation -framework Intents -framework EventKit probe.m -o probe   (macOS)
//   xcrun clang -fno-objc-arc -target arm64-apple-ios15.0-macabi -isysroot $(xcrun --show-sdk-path) \
//       -iframework $(xcrun --show-sdk-path)/System/iOSSupport/System/Library/Frameworks \
//       -framework Foundation -framework Intents -framework EventKit probe.m -o probe-catalyst
#import <Foundation/Foundation.h>
#import <EventKit/EventKit.h>
#import <objc/runtime.h>
#include <stdio.h>

static void show(const char *label, id value)
{
    if (!value) {
        printf("%s\tnil\n", label);
    } else if ([value isKindOfClass:[NSNumber class]]) {
        printf("%s\tnumber %ld\n", label, (long)[value integerValue]);
    } else if ([value isKindOfClass:[NSArray class]]) {
        printf("%s\tarray %lu\n", label, (unsigned long)[value count]);
    } else {
        printf("%s\t%s\n", label, class_getName([value class]));
    }
}

// The value of a property, read by its key where the object has one; "absent" where it has none.
static void key(const char *label, id owner, const char *name)
{
    if (!owner) {
        printf("%s\towner-nil\n", label);
        return;
    }
    SEL getter = NSSelectorFromString(@(name));
    if (![owner respondsToSelector:getter]) {
        printf("%s\tabsent\n", label);
        return;
    }
    show(label, [owner valueForKey:@(name)]);
}

static void properties(const char *label, Class cls)
{
    unsigned int count = 0;
    objc_property_t *list = class_copyPropertyList(cls, &count);
    printf("%s\t", label);
    for (unsigned int i = 0; i < count; i++) {
        printf("%s%s", i ? " " : "", property_getName(list[i]));
    }
    printf("\n");
    free(list);
}

static void rangeCase(const char *name, id rule, Class rangeClass, SEL initSel, SEL getSel)
{
    printf("case\t%s\n", name);
    id range = [[rangeClass alloc] performSelector:initSel withObject:rule];
    show("  range", range);
    if (!range) {
        return;
    }
    id back = nil;
    @try {
        back = [range performSelector:getSel];
        show("  EKRecurrenceRule", back);
        printf("  EKRecurrenceRule is the object given\t%s\n", back == rule ? "YES" : "NO");
        key("    frequency", back, "frequency");
        key("    interval", back, "interval");
        key("    daysOfTheWeek", back, "daysOfTheWeek");
        key("    recurrenceEnd", back, "recurrenceEnd");
    } @catch (NSException *e) {
        printf("  EKRecurrenceRule raises\t%s\n", [[e reason] UTF8String]);
    }
    key("  recurrenceRule", range, "recurrenceRule");
    id kept = [range valueForKey:@"recurrenceRule"];
    key("  recurrenceRule.frequency", kept, "frequency");
    key("  recurrenceRule.interval", kept, "interval");
    key("  recurrenceRule.weeklyRecurrenceDays", kept, "weeklyRecurrenceDays");
    id days = [kept respondsToSelector:NSSelectorFromString(@"weeklyRecurrenceDays")] ? [kept valueForKey:@"weeklyRecurrenceDays"] : nil;
    for (id day in [days isKindOfClass:[NSArray class]] ? days : @[]) {
        printf("  weeklyRecurrenceDays element\t%s\n", class_getName([day class]));
        key("    dayOfTheWeek", day, "dayOfTheWeek");
        key("    weekNumber", day, "weekNumber");
    }
    key("  startDateComponents", range, "startDateComponents");
    key("  endDateComponents", range, "endDateComponents");
}

int main(void)
{
    @autoreleasepool {
        Class rangeClass = NSClassFromString(@"INDateComponentsRange");
        SEL initSel = NSSelectorFromString(@"initWithEKRecurrenceRule:");
        SEL getSel = NSSelectorFromString(@"EKRecurrenceRule");
        Class ruleClass = NSClassFromString(@"INRecurrenceRule");
        printf("responds\tinit %d\tget %d\n", [rangeClass instancesRespondToSelector:initSel], [rangeClass instancesRespondToSelector:getSel]);
        properties("INRecurrenceRule.properties", ruleClass);
        properties("INRecurrenceEnd.properties", NSClassFromString(@"INRecurrenceEnd"));

        EKRecurrenceRule *daily = [[EKRecurrenceRule alloc] initRecurrenceWithFrequency:EKRecurrenceFrequencyDaily interval:2 end:nil];
        rangeCase("daily every two, no end", daily, rangeClass, initSel, getSel);

        EKRecurrenceDayOfWeek *monday = [EKRecurrenceDayOfWeek dayOfWeek:2];
        EKRecurrenceDayOfWeek *friday = [EKRecurrenceDayOfWeek dayOfWeek:6];
        EKRecurrenceEnd *fiveTimes = [EKRecurrenceEnd recurrenceEndWithOccurrenceCount:5];
        EKRecurrenceRule *weekly = [[EKRecurrenceRule alloc] initRecurrenceWithFrequency:EKRecurrenceFrequencyWeekly interval:1 daysOfTheWeek:@[monday, friday] daysOfTheMonth:nil monthsOfTheYear:nil weeksOfTheYear:nil daysOfTheYear:nil setPositions:nil end:fiveTimes];
        rangeCase("weekly on Monday and Friday, five times", weekly, rangeClass, initSel, getSel);

        rangeCase("nil rule", nil, rangeClass, initSel, getSel);

        // A range made by its plain initialiser, read through the EventKit getter: nothing to give it, so nothing back.
        id plain = [[rangeClass alloc] init];
        show("plain range", plain);
        key("  plain EKRecurrenceRule", plain, "EKRecurrenceRule");
    }
    return 0;
}
