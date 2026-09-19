#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>

NSDate *charon_next_date_matching(NSCalendar *calendar, NSDateComponents *components, NSDate *after);

@interface UNNotificationSound (CharonUserNotifications)
- (NSString *)charon_fileName;
@end

@interface UNNotification (CharonUserNotifications)
+ (instancetype)notificationWithRequest:(UNNotificationRequest *)request date:(NSDate *)date;
@end

@interface UNNotificationResponse (CharonUserNotifications)
+ (instancetype)responseWithNotification:(UNNotification *)notification actionIdentifier:(NSString *)actionIdentifier;
@end
