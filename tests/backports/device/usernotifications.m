#import <UserNotifications/UserNotifications.h>
#import <objc/message.h>
#include <dlfcn.h>
#import "check.h"
#import "usernotifications-expectations.h"

static NSString *image_of(Class cls)
{
    Dl_info info;
    return dladdr((__bridge const void *)cls, &info) ? @(info.dli_fname).lastPathComponent : @"?";
}

static NSString *raised(void (^block)(void))
{
    @try {
        block();
    } @catch (NSException *exception) {
        return [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason];
    }
    return @"nothing";
}

static NSDate *next_after(id trigger, NSDate *after, NSDate *requested)
{
    return ((id (*)(id, SEL, id, id))objc_msgSend)(trigger, NSSelectorFromString(@"nextTriggerDateAfterDate:withRequestedDate:"),
                                                  after, requested);
}

static NSDateComponents *components_of(const char *spec, const char *zone)
{
    NSDateComponents *components = [[NSDateComponents alloc] init];
    for (NSString *pair in [@(spec) componentsSeparatedByString:@","]) {
        NSArray *parts = [pair componentsSeparatedByString:@"="];
        [components setValue:@([parts[1] integerValue]) forKey:parts[0]];
    }
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
    calendar.timeZone = [NSTimeZone timeZoneWithName:@(zone)];
    components.calendar = calendar;
    return components;
}

static void check_matching(void)
{
    NSUInteger count = sizeof(charon_matchings) / sizeof(*charon_matchings), wrong = 0;
    NSString *first = nil;
    NSMutableDictionary *byZone = [NSMutableDictionary dictionary];
    for (NSUInteger index = 0; index < count; index++) {
        const struct charon_matching *expected = &charon_matchings[index];
        UNCalendarNotificationTrigger *trigger =
            [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:components_of(expected->spec, expected->zone)
                                                                     repeats:expected->repeats != 0];
        NSDate *after = [NSDate dateWithTimeIntervalSinceReferenceDate:expected->after];
        NSDate *next = next_after(trigger, after, [after dateByAddingTimeInterval:-86400 * 3]);
        BOOL agrees = isnan(expected->next) ? next == nil : next.timeIntervalSinceReferenceDate == expected->next;
        if (!agrees) {
            NSString *zone = @(expected->zone);
            byZone[zone] = @([byZone[zone] unsignedIntegerValue] + 1);
            if (wrong++ == 0)
                first = [NSString stringWithFormat:@"%s in %s after %.17g, repeats %d: %@ where %.17g was expected",
                                                   expected->spec, expected->zone, expected->after, expected->repeats, next, expected->next];
        }
    }
    if (wrong)
        printf("differing by zone: %s\n", byZone.description.UTF8String);
    charon_check(wrong == 0,
                 [NSString stringWithFormat:@"the %lu next dates of calendar triggers are the ones the newest release gives",
                                            (unsigned long)count].UTF8String,
                 [NSString stringWithFormat:@"%lu differ, the first %@", (unsigned long)wrong, first]);
}

int main(void)
{
    @autoreleasepool {
        for (NSString *name in @[@"UNNotificationContent", @"UNMutableNotificationContent", @"UNNotificationSound",
                                 @"UNNotificationTrigger", @"UNTimeIntervalNotificationTrigger", @"UNCalendarNotificationTrigger",
                                 @"UNNotificationRequest", @"UNNotification", @"UNNotificationResponse"])
            CHECK_EQUAL(image_of(NSClassFromString(name)), @"libUIKitBackports.dylib",
                        [name stringByAppendingString:@" comes from the backports library"].UTF8String);

        check_matching();

        CHECK_EQUAL(raised(^{ [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0 repeats:NO]; }),
                    @"NSInternalInconsistencyException: time interval must be greater than 0", "a trigger of no time raises");
        CHECK_EQUAL(raised(^{ [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:30 repeats:YES]; }),
                    @"NSInternalInconsistencyException: time interval must be at least 60 if repeating",
                    "a trigger repeating sooner than a minute raises");
        UNTimeIntervalNotificationTrigger *interval = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:100 repeats:YES];
        NSDate *requested = [NSDate dateWithTimeIntervalSinceReferenceDate:1000];
        CHECK(next_after(interval, [NSDate dateWithTimeIntervalSinceReferenceDate:1150], requested).timeIntervalSinceReferenceDate == 1200,
              "a repeating interval fires on its multiples of the requested date");
        CHECK(next_after([UNTimeIntervalNotificationTrigger triggerWithTimeInterval:100 repeats:NO],
                         [NSDate dateWithTimeIntervalSinceReferenceDate:1150], requested) == nil,
              "one that does not repeat fires once");
        CHECK(fabs([interval.nextTriggerDate timeIntervalSinceNow] - 100) < 1, "the next date is the interval from now");

        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        CHECK(content.title == nil && [content.categoryIdentifier isEqual:@""] && [content.launchImageName isEqual:@""]
              && [content.userInfo isEqual:@{}] && [content.attachments isEqual:@[]], "a fresh content is empty as the newest one is");
        content.title = @"A title";
        content.subtitle = @"A subtitle";
        content.body = @"A body";
        content.badge = @3;
        content.sound = [UNNotificationSound defaultSound];
        content.userInfo = @{@"key": @[@1, @"two"]};
        content.categoryIdentifier = nil;
        CHECK([content.categoryIdentifier isEqual:@""], "a category set to nil reads as empty");
        UNNotificationContent *frozen = [content copy];
        CHECK([frozen class] == [UNNotificationContent class] && [frozen copy] == frozen, "a copy is immutable and its own copy");
        CHECK([frozen isEqual:content] && frozen.hash == content.hash, "and equals the content it came from");
        CHECK([frozen.title isEqual:@"A title"] && [frozen.subtitle isEqual:@"A subtitle"],
              "the title and subtitle are carried, though iOS 6 shows neither");
        UNNotificationContent *back = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:frozen]];
        CHECK([back isEqual:frozen], "a content survives an archive");
        for (NSString *later in @[@"interruptionLevel", @"relevanceScore", @"targetContentIdentifier", @"summaryArgument",
                                  @"filterCriteria"])
            charon_check(![frozen respondsToSelector:NSSelectorFromString(later)],
                         [later stringByAppendingString:@", which iOS 10 has not got, is not answered"].UTF8String, @"it is");

        CHECK_EQUAL(raised(^{ [UNNotificationRequest requestWithIdentifier:(id)nil content:frozen trigger:nil]; }),
                    @"NSInternalInconsistencyException: Invalid parameter not satisfying: identifier != nil",
                    "a request with no identifier raises");
        UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:@"one" content:frozen trigger:interval];
        UNNotificationRequest *requestBack = [NSKeyedUnarchiver unarchiveObjectWithData:
                                                 [NSKeyedArchiver archivedDataWithRootObject:request]];
        CHECK([requestBack isEqual:request], "a request survives an archive, trigger and all");

        printf("%d checks, %d failures\n", charon_checks, charon_failures);
        return charon_failures;
    }
}
