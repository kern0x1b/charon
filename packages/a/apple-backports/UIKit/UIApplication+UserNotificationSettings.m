#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static NSString *const CharonRegisteredTypesKey = @"org.charon.apple-backports.UIUserNotificationTypes";
static char charon_remote_registered_key;

static UIUserNotificationType charon_registered_types(void)
{
    return (UIUserNotificationType)[[[NSUserDefaults standardUserDefaults] objectForKey:CharonRegisteredTypesKey] unsignedIntegerValue];
}

@implementation UIApplication (CharonUserNotificationSettings)

- (void)registerUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings
{
    UIUserNotificationType types = notificationSettings.types & (UIUserNotificationTypeBadge | UIUserNotificationTypeSound | UIUserNotificationTypeAlert);
    if (notificationSettings.categories.count)
        NSLog(@"registerUserNotificationSettings: iOS %@ shows no actions on notifications, so the categories %@ are not registered and currentUserNotificationSettings reports none", [UIDevice currentDevice].systemVersion, [notificationSettings.categories valueForKey:@"identifier"]);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@(types) forKey:CharonRegisteredTypesKey];
    [defaults synchronize];
    if ([objc_getAssociatedObject(self, &charon_remote_registered_key) boolValue])
        [self registerForRemoteNotificationTypes:(UIRemoteNotificationType)types];
    dispatch_async(dispatch_get_main_queue(), ^{
        id<UIApplicationDelegate> delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(application:didRegisterUserNotificationSettings:)])
            [delegate application:self didRegisterUserNotificationSettings:self.currentUserNotificationSettings];
    });
}

- (UIUserNotificationSettings *)currentUserNotificationSettings
{
    UIUserNotificationType types = charon_registered_types();
    UIRemoteNotificationType enabled = [self enabledRemoteNotificationTypes];
    if (enabled != UIRemoteNotificationTypeNone)
        types &= (UIUserNotificationType)enabled;
    return [UIUserNotificationSettings settingsForTypes:types categories:nil];
}

- (void)registerForRemoteNotifications
{
    objc_setAssociatedObject(self, &charon_remote_registered_key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self registerForRemoteNotificationTypes:(UIRemoteNotificationType)charon_registered_types()];
}

@end
