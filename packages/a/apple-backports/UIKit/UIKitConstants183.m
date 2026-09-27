// The URL of the settings of the system's own default applications, iOS 18.3
// (facts/UIKit/UIKitConstants183.md).
//
// No iOS release on this machine carries this one: the newest held cache is iOS 18.0. Its value
// is read out of the Mac Catalyst UIKit of macOS 27, in the system's own dyld shared cache.

#import <UIKit/UIKit.h>

NSString *const UIApplicationOpenDefaultApplicationsSettingsURLString = @"app-settings:default-applications";
