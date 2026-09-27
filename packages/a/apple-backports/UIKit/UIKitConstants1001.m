// The UIKit constants first exported by iOS 10.0.1
// (facts/UIKit/UIKitConstants1001.md).
//
// One object carries one release: every symbol here is first exported by the oldest
// held release that has it, so a band from 10.0.1 on re-exports the release's own and the
// bands below keep this one.
//
// Every value below was read out of a real dyld shared cache, /System/Library/Frameworks/UIKit.framework/UIKit,
// never from a header and never from a host framework.

#import <UIKit/UIKit.h>

const NSNotificationName UIAccessibilityAssistiveTouchStatusDidChangeNotification = @"UIAccessibilityAssistiveTouchStatusDidChangeNotification";
const NSNotificationName UIAccessibilityHearingDevicePairedEarDidChangeNotification = @"UIAccessibilityHearingDevicePairedEarDidChangeNotification";
const UIApplicationLaunchOptionsKey UIApplicationLaunchOptionsCloudKitShareMetadataKey = @"UIApplicationLaunchOptionsCloudKitShareMetadataKey";
const CGFloat UICollectionViewLayoutAutomaticDimension = CGFLOAT_MAX;
NSString *const UIPasteboardTypeAutomatic = @"com.apple.uikit.type-automatic";
NSString *const UITextFieldDidEndEditingReasonKey = @"UITextFieldEndEditingReasonKey";
