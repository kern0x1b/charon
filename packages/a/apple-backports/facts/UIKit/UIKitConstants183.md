# `UIApplicationOpenDefaultApplicationsSettingsURLString`, iOS 18.3

`UIKit/UIKitConstants183.m`: the URL of the page where the user picks which application opens links.

## Where the value comes from

No iOS release on this machine carries this symbol: the held ladder ends at iOS 18.0. It is read out
of the Mac Catalyst UIKit of macOS 27, in the system's own dyld shared cache
(`/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e`), with this
repository's own reader:

| constant | the image that exports it | the value |
| --- | --- | --- |
| `UIApplicationOpenDefaultApplicationsSettingsURLString` | `/System/iOSSupport/System/Library/PrivateFrameworks/UIKitCore.framework/Versions/A/UIKitCore` | `app-settings:default-applications` |

It follows the shape of the two constants of iOS 8 that this package already carries and whose
values were measured the same way - `app-settings:` (`UIApplicationOpenSettingsURLString`) and
`app-settings:notifications` (`UIApplicationOpenNotificationSettingsURLString`,
`UIKit/UIApplicationConstants15_4.m`) - so it is a third page of the same scheme, not a new one.

iOS 6 has no page that picks the default application, and nothing handles the scheme, so
`-openURL:` on it answers NO on this release, which an application that checks `-canOpenURL:` first
already handles. The name is carried so that the reference links; the answer is the release's own.
