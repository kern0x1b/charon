#import <UIKit/UIKit.h>
#import <UserNotificationsUI/UserNotificationsUI.h>
#import "../CharonSayOnce.h"
#import <objc/runtime.h>

// The notification content extension arrived with iOS 10, and it runs in a separate process the
// system starts; this release has no app extensions at all, so no host ever makes an NSExtensionContext
// for one and nothing reads what an extension puts in it. The NSExtensionContext the port carries is
// already recorded as inert for exactly that reason (registry/Foundation/ios8extensioncontext.json),
// and these five members answer as the same class does: what the extension can state about itself is
// kept and read back, and the three that are messages to the host say once that there is no host.

@implementation NSExtensionContext (UNNotificationContentExtension)

@dynamic notificationActions;

// The actions the extension wants offered. The array is the extension's own, kept and handed back as
// it is set; the system that would draw them, and the response that would come back through
// -didReceiveNotificationResponse:completionHandler:, belong to the extension host this release does
// not run.
- (NSArray<UNNotificationAction *> *)notificationActions
{
    return objc_getAssociatedObject(self, @selector(notificationActions)) ?: @[];
}

- (void)setNotificationActions:(NSArray<UNNotificationAction *> *)notificationActions
{
    objc_setAssociatedObject(self, @selector(notificationActions), notificationActions, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void)performNotificationDefaultAction
{
    charon_say_once_for(@"NSExtensionContext.performNotificationDefaultAction",
                        @"CharonUserNotificationsUI: there is no extension host on this release, so the notification's "
                        @"default action is not performed - the same answer the port's NSExtensionContext already gives "
                        @"for completing, cancelling and opening a URL.");
}

- (void)dismissNotificationContentExtension
{
    charon_say_once_for(@"NSExtensionContext.dismissNotificationContentExtension",
                        @"CharonUserNotificationsUI: there is no extension host on this release, so there is no content "
                        @"extension to dismiss; the port's NSExtensionContext holds no presented controller either.");
}

// The two halves of the extension telling the system that the media it is playing has started or
// paused, so the system can put playback controls in the notification and stop the sound with it.
// Both need that system, and the port keeps the state so that a host it does have would see it.
- (void)mediaPlayingStarted
{
    objc_setAssociatedObject(self, @selector(mediaPlayingStarted), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    charon_say_once_for(@"NSExtensionContext.mediaPlayingStarted",
                        @"CharonUserNotificationsUI: the media state is kept, but this release's system takes no playback "
                        @"controls in a notification, so nothing is shown for it.");
}

- (void)mediaPlayingPaused
{
    objc_setAssociatedObject(self, @selector(mediaPlayingPaused), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    charon_say_once_for(@"NSExtensionContext.mediaPlayingPaused",
                        @"CharonUserNotificationsUI: the media state is kept, but this release's system takes no playback "
                        @"controls in a notification, so nothing is stopped for it.");
}

@end
