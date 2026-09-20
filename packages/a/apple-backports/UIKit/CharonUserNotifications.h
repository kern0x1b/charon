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
- (instancetype)initCharonWithNotification:(UNNotification *)notification actionIdentifier:(NSString *)actionIdentifier;
@end

@interface UNNotificationAction (CharonUserNotifications)
- (instancetype)initCharonWithIdentifier:(NSString *)identifier title:(NSString *)title options:(UNNotificationActionOptions)options;
- (NSString *)charon_description;
@end

@interface UNTextInputNotificationAction (CharonUserNotifications)
- (instancetype)initCharonWithIdentifier:(NSString *)identifier title:(NSString *)title options:(UNNotificationActionOptions)options
                    textInputButtonTitle:(NSString *)buttonTitle textInputPlaceholder:(NSString *)placeholder;
@end
