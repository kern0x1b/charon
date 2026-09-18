# UNUserNotificationCenter

Introduced in iOS 10.0. Reconnaissance only - no implementation yet. The question
this answers is how much of the UserNotifications API iOS 6 can actually carry,
and where it has to stop.

Sources: UserNotifications and UserNotificationsServer of the armv7s cache of
iOS 10.3.4; UIKit, BulletinBoard and SpringBoard of iOS 6.0 and of an iPhone4,1
running 6.1.3.

## On iOS 10 it is a client of a daemon

`UserNotifications.framework` holds the API - `UNUserNotificationCenter`,
`UNNotificationRequest`, the triggers, the content, the settings - and talks over
XPC (`UNUserNotificationServiceConnection`, `UNUserNotificationService`) to a
second framework, `UserNotificationsServer`, which is where the work happens:
`UNSNotificationRepository`, `UNSPendingNotificationRepository`,
`UNSNotificationSchedulingService`, `UNSNotificationSettingsService`,
`UNSLocationMonitor`, `UNSUserNotificationServer`.

That daemon does not exist on iOS 6 and cannot be written for it. **But it does
not have to be.** Everything the daemon does for local notifications - keeping
the pending list, firing on a date, repeating on a calendar, delivering to the
notification centre, badging, sounding - SpringBoard already does on iOS 6,
through `-[UIApplication scheduleLocalNotification:]`. So the port is not a
daemon; it is a facade over the scheduler iOS 6 already has.

## What iOS 6 gives it

`UILocalNotification` is a class cluster; the real class is
`UIConcreteLocalNotification`, and it carries more than the iOS 6 header admits:

| member | note |
|---|---|
| `fireDate`, `timeZone` | the public pair |
| `repeatInterval` | an `NSCalendarUnit`, not an arbitrary interval |
| `repeatCalendar` | the calendar the repeat is counted in |
| `totalRepeatCount`, `remainingRepeatCount` | a **finite** number of repeats, which iOS 10's own API cannot express |
| `alertBody`, `alertAction`, `alertLaunchImage`, `hasAction` | the alert |
| `soundName`, `soundType` | the sound |
| `applicationIconBadgeNumber` | the badge |
| `userInfo` | free-form, and the only place a port can keep an identifier |
| `fireNotificationsWhenAppRunning` | shows the alert even in the foreground |
| `allowSnooze`, `snoozedNotificationName`, `firedNotificationName` | snoozing |
| `isSystemAlert`, `hideAlertTitle`, `customLockSliderLabel`, `interruptAudioAndLockDevice`, `resumeApplicationInBackground`, `showsAlarmStatusBarItem` | private |

SpringBoard refuses the private ones to an unentitled app - its own string is
`Ignoring UILocalNotification property change as '%@' entitlement is re...` - so
a port may not lean on them.

`UIApplication` gives `-scheduleLocalNotification:`, `-cancelLocalNotification:`,
`-cancelAllLocalNotifications`, `-scheduledLocalNotifications`,
`-presentLocalNotificationNow:`, `-registerForRemoteNotificationTypes:`,
`-enabledRemoteNotificationTypes` and `-unregisterForRemoteNotifications`.

## The mapping, member by member

| iOS 10 | iOS 6 | verdict |
|---|---|---|
| `+currentNotificationCenter` | a singleton over `+[UIApplication sharedApplication]` | carries |
| `-addNotificationRequest:withCompletionHandler:` | build a `UILocalNotification`, put the identifier in `userInfo`, cancel any pending one with that identifier, `-scheduleLocalNotification:` | carries |
| `-getPendingNotificationRequestsWithCompletionHandler:` | `-scheduledLocalNotifications` filtered to the ones carrying our key, rebuilt into requests | carries |
| `-removePendingNotificationRequestsWithIdentifiers:` | find by identifier, `-cancelLocalNotification:` | carries |
| `-removeAllPendingNotificationRequests` | cancel ours, one by one - **not** `-cancelAllLocalNotifications`, which would also throw away notifications the app scheduled itself | carries |
| `-requestAuthorizationWithOptions:completionHandler:` | local notifications need no permission on iOS 6; the remote bits map onto `-registerForRemoteNotificationTypes:` | carries, with the caveat below |
| `-getNotificationSettingsWithCompletionHandler:` | `-enabledRemoteNotificationTypes` answers alert, badge and sound honestly | carries in part; see below |
| `-setDelegate:` / `willPresentNotification:` | `application:didReceiveLocalNotification:` while the app is active | carries |
| `-setDelegate:` / `didReceiveNotificationResponse:` | the same callback when the app was launched or resumed by the notification, with `UNNotificationDefaultActionIdentifier` | carries |
| `UNTimeIntervalNotificationTrigger` | `fireDate = now + interval` | carries when it does not repeat |
| ... repeating | `repeatInterval` is a calendar unit, so only intervals that *are* a calendar unit can repeat | partial - refuse the rest |
| `UNCalendarNotificationTrigger` | the next date matching the components, plus `repeatInterval` / `repeatCalendar` | carries for the usual cases (daily, weekly, monthly at a time) |
| `UNPushNotificationTrigger` | built when a notification arrives through `application:didReceiveRemoteNotification:` | carries |
| `UNLocationNotificationTrigger` | iOS 6 has no region trigger for notifications | absent |
| `UNNotificationSound.defaultSound` | `UILocalNotificationDefaultSoundName` | carries |
| content `body`, `badge`, `sound`, `userInfo`, `launchImageName` | `alertBody`, `applicationIconBadgeNumber`, `soundName`, `userInfo`, `alertLaunchImage` | carries |
| content `title`, `subtitle` | iOS 6 has no title on a local notification - it was added in iOS 8 | **no substrate** |
| content `attachments` | rich notifications | absent |
| content `categoryIdentifier`, `UNNotificationAction`, `UNNotificationCategory`, `-setNotificationCategories:` | actionable notifications arrived in iOS 8 | absent |
| content `threadIdentifier` | grouping arrived in iOS 10 | absent |
| `-getDeliveredNotificationsWithCompletionHandler:`, `-removeDeliveredNotificationsWithIdentifiers:`, `-removeAllDeliveredNotifications` | needs BulletinBoard; see below | **unproven** |

`title` is the one place where a port would be tempted to invent: folding the
title into the body would change the text the user sees, and nothing in iOS 6
does that. It should be left out until the owner decides.

## BulletinBoard, and why it is not settled

iOS 6 has the whole notification backend as a framework: `BBBulletin`,
`BBBulletinRequest`, `BBObserver`, `BBServer`, `BBSectionInfo`, `BBSound`,
`BBAction`, `BBButton`, `BBSettingsGateway`. Two pieces would answer exactly what
the mapping table leaves open:

- `BBObserver` - `-requestListBulletinsForSectionID:`, `-clearBulletins:inSection:`,
  `-clearSection:` - is what `getDeliveredNotifications` and
  `removeDeliveredNotifications` would ride on.
- `BBSectionInfo` carries `alertType`, `showsInNotificationCenter`,
  `showsInLockScreen`, `showsMessagePreview`, `pushSettings`, `enabled`,
  `notificationCenterLimit` - which is nearly field for field what
  `UNNotificationSettings` reports.

The services are vended by SpringBoard as `com.apple.bulletinboard.settings`,
`.observer`, `.utilities` and `.systemstate`, and SpringBoard carries a plist
naming those same four strings as the entitlements it requires.

Measured on the iPhone4,1: a process that dlopens BulletinBoard gets the classes
and can construct `BBSettingsGateway` and `BBObserver`, but every call comes back
empty and the log says `Unexpected error on BBServer connection ... XPCObjectsErrorDomain Code=2`.
That happened as root, as `mobile`, and with all four entitlements applied by
`ldid`. SpringBoard's own failure string for this path is
`Unable to get entitlements for client task`, which suggests it validates through
`SecTaskCopyValueForEntitlement` and does not accept an `ldid` pseudo-signature.
It is not a bootstrap namespace problem: other SpringBoard services answer this
same SSH session.

So: whether a properly installed application can reach BulletinBoard on this
jailbreak is **not established**. Until it is, the delivered-notification methods
and the full `UNNotificationSettings` must not exist rather than answer emptily.
Proving it needs code running inside an application SpringBoard launched, which
is the same thing that blocks the A5 scrubbing measurement.
