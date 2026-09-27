// The UIKit constants first exported by iOS 7.0
// (facts/UIKit/UIKitConstants70.md).
//
// One object carries one release: every symbol here is first exported by the oldest
// held release that has it, so a band from 7.0 on re-exports the release's own and the
// bands below keep this one.
//
// Every value below was read out of a real dyld shared cache, /System/Library/Frameworks/UIKit.framework/UIKit,
// never from a header and never from a host framework.

#import <UIKit/UIKit.h>

const NSNotificationName NSTextStorageDidProcessEditingNotification = @"NSTextStorageDidProcessEditingNotification";
const NSNotificationName NSTextStorageWillProcessEditingNotification = @"NSTextStorageWillProcessEditingNotification";
const UIActivityType UIActivityTypeAirDrop = @"com.apple.UIKit.activity.AirDrop";
const UIApplicationLaunchOptionsKey UIApplicationLaunchOptionsBluetoothCentralsKey = @"UIApplicationLaunchOptionsBluetoothCentralsKey";
const UIApplicationLaunchOptionsKey UIApplicationLaunchOptionsBluetoothPeripheralsKey = @"UIApplicationLaunchOptionsBluetoothPeripheralsKey";
NSString *const UIApplicationStateRestorationSystemVersionKey = @"UIApplicationStateRestorationSystemVersion";
NSString *const UIApplicationStateRestorationTimestampKey = @"UIApplicationStateRestorationTimestamp";
const NSNotificationName UIContentSizeCategoryDidChangeNotification = @"UIContentSizeCategoryDidChangeNotification";
NSString *const UIContentSizeCategoryNewValueKey = @"UIContentSizeCategoryNewValueKey";
