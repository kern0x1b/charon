// The UIKit constants first exported by iOS 8.0
// (facts/UIKit/UIKitConstants80.md).
//
// One object carries one release: every symbol here is first exported by the oldest
// held release that has it, so a band from 8.0 on re-exports the release's own and the
// bands below keep this one.
//
// Every value below was read out of a real dyld shared cache, /System/Library/Frameworks/UIKit.framework/UIKit,
// never from a header and never from a host framework.

#import <UIKit/UIKit.h>

NSString *const NSUserActivityDocumentURLKey = @"NSUserActivityDocumentURL";
const UIApplicationExtensionPointIdentifier UIApplicationKeyboardExtensionPointIdentifier = @"com.apple.keyboard-service";
const UIApplicationLaunchOptionsKey UIApplicationLaunchOptionsUserActivityDictionaryKey = @"UIApplicationLaunchOptionsUserActivityDictionaryKey";
const UIApplicationLaunchOptionsKey UIApplicationLaunchOptionsUserActivityTypeKey = @"UIApplicationLaunchOptionsUserActivityTypeKey";
const CGFloat UISplitViewControllerAutomaticDimension = -FLT_MAX;
const NSNotificationName UIViewControllerShowDetailTargetDidChangeNotification = @"UIViewControllerShowDetailTargetDidChangeNotification";
