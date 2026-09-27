#import <UIKit/UIKit.h>

// The exported string constants and the one dimension this backport has to carry, with the value
// each one holds. Every value here was read, not chosen: 24 of them out of a real dyld shared cache
// (tools/cfconst.py over ~/.charon/dyld/7.0 and ~/.charon/dyld/11.0, UIKit.framework/UIKit) and
// all 45 out of the host's own UIKit under Mac Catalyst, the two agreeing on every one they both
// could give. tests/backports/host/uikitconst holds the backport to the host's values.
//
// The other 439 constant rows of this framework in this range are enum cases and macros, which the
// lift's headers already carry with no symbol of their own; see facts/UIKit/ExportedConstants.md.

NSString * const NSTextListMarkerBox = @"{box}";
NSString * const NSTextListMarkerCheck = @"{check}";
NSString * const NSTextListMarkerCircle = @"{circle}";
NSString * const NSTextListMarkerDecimal = @"{decimal}";
NSString * const NSTextListMarkerDiamond = @"{diamond}";
NSString * const NSTextListMarkerDisc = @"{disc}";
NSString * const NSTextListMarkerHyphen = @"{hyphen}";
NSString * const NSTextListMarkerLowercaseAlpha = @"{lower-alpha}";
NSString * const NSTextListMarkerLowercaseHexadecimal = @"{lower-hexadecimal}";
NSString * const NSTextListMarkerLowercaseLatin = @"{lower-latin}";
NSString * const NSTextListMarkerLowercaseRoman = @"{lower-roman}";
NSString * const NSTextListMarkerOctal = @"{octal}";
NSString * const NSTextListMarkerSquare = @"{square}";
NSString * const NSTextListMarkerUppercaseAlpha = @"{upper-alpha}";
NSString * const NSTextListMarkerUppercaseHexadecimal = @"{upper-hexadecimal}";
NSString * const NSTextListMarkerUppercaseLatin = @"{upper-latin}";
NSString * const NSTextListMarkerUppercaseRoman = @"{upper-roman}";
NSString * const NSTextStorageDidProcessEditingNotification = @"NSTextStorageDidProcessEditingNotification";
NSString * const NSTextStorageWillProcessEditingNotification = @"NSTextStorageWillProcessEditingNotification";
NSString * const NSUserActivityDocumentURLKey = @"NSUserActivityDocumentURL";
NSString * const UIAccessibilityAssistiveTouchStatusDidChangeNotification = @"UIAccessibilityAssistiveTouchStatusDidChangeNotification";
NSString * const UIAccessibilityHearingDevicePairedEarDidChangeNotification = @"UIAccessibilityHearingDevicePairedEarDidChangeNotification";
NSString * const UIActivityTypeAirDrop = @"com.apple.UIKit.activity.AirDrop";
NSString * const UIApplicationKeyboardExtensionPointIdentifier = @"com.apple.keyboard-service";
NSString * const UIApplicationLaunchOptionsBluetoothCentralsKey = @"UIApplicationLaunchOptionsBluetoothCentralsKey";
NSString * const UIApplicationLaunchOptionsBluetoothPeripheralsKey = @"UIApplicationLaunchOptionsBluetoothPeripheralsKey";
NSString * const UIApplicationLaunchOptionsCloudKitShareMetadataKey = @"UIApplicationLaunchOptionsCloudKitShareMetadataKey";
NSString * const UIApplicationLaunchOptionsUserActivityDictionaryKey = @"UIApplicationLaunchOptionsUserActivityDictionaryKey";
NSString * const UIApplicationLaunchOptionsUserActivityTypeKey = @"UIApplicationLaunchOptionsUserActivityTypeKey";
NSString * const UIApplicationStateRestorationSystemVersionKey = @"UIApplicationStateRestorationSystemVersion";
NSString * const UIApplicationStateRestorationTimestampKey = @"UIApplicationStateRestorationTimestamp";
NSString * const UIContentSizeCategoryDidChangeNotification = @"UIContentSizeCategoryDidChangeNotification";
NSString * const UIContentSizeCategoryNewValueKey = @"UIContentSizeCategoryNewValueKey";
NSString * const UIDocumentBrowserErrorDomain = @"com.apple.DocumentManager";
NSString * const UIFocusDidUpdateNotification = @"UIFocusDidUpdateNotification";
NSString * const UIFocusMovementDidFailNotification = @"UIFocusMovementDidFailNotification";
NSString * const UIFocusUpdateAnimationCoordinatorKey = @"UIFocusUpdateAnimationCoordinatorKey";
NSString * const UIFocusUpdateContextKey = @"UIFocusUpdateContextKey";
NSString * const UIImagePickerControllerLivePhoto = @"UIImagePickerControllerLivePhoto";
NSString * const UIPasteboardTypeAutomatic = @"com.apple.uikit.type-automatic";
NSString * const UITextFieldDidEndEditingReasonKey = @"UITextFieldEndEditingReasonKey";
NSString * const UIUserNotificationActionResponseTypedTextKey = @"UIUserNotificationActionResponseTypedTextKey";
NSString * const UIUserNotificationTextInputActionButtonTitleKey = @"UIUserNotificationTextInputActionButtonTitleKey";
NSString * const UIViewControllerShowDetailTargetDidChangeNotification = @"UIViewControllerShowDetailTargetDidChangeNotification";
CGFloat const UISplitViewControllerAutomaticDimension = -3.40282e+38;
