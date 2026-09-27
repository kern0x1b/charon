#import <UIKit/UIKit.h>

// The exported constants that arrived in iOS 10.0, and no others: an object carries the API of one
// release, so each release's worth of them is its own file. Every value was read, not chosen -- out
// of a real dyld shared cache with tools/cfconst.py and out of the host's own UIKit, which agree on
// every one both could give; tests/backports/host/uikitconst holds the backport to the host's.

NSString * const UIAccessibilityAssistiveTouchStatusDidChangeNotification = @"UIAccessibilityAssistiveTouchStatusDidChangeNotification";
NSString * const UIAccessibilityHearingDevicePairedEarDidChangeNotification = @"UIAccessibilityHearingDevicePairedEarDidChangeNotification";
NSString * const UIApplicationLaunchOptionsCloudKitShareMetadataKey = @"UIApplicationLaunchOptionsCloudKitShareMetadataKey";
NSString * const UITextFieldDidEndEditingReasonKey = @"UITextFieldEndEditingReasonKey";
