#import <UIKit/UIKit.h>

// The exported constants that arrived in iOS 7.0, and no others: an object carries the API of one
// release, so each release's worth of them is its own file. Every value was read, not chosen -- out
// of a real dyld shared cache with tools/cfconst.py and out of the host's own UIKit, which agree on
// every one both could give; tests/backports/host/uikitconst holds the backport to the host's.

NSString * const NSTextStorageDidProcessEditingNotification = @"NSTextStorageDidProcessEditingNotification";
NSString * const NSTextStorageWillProcessEditingNotification = @"NSTextStorageWillProcessEditingNotification";
NSString * const UIActivityTypeAirDrop = @"com.apple.UIKit.activity.AirDrop";
NSString * const UIApplicationLaunchOptionsBluetoothCentralsKey = @"UIApplicationLaunchOptionsBluetoothCentralsKey";
NSString * const UIApplicationLaunchOptionsBluetoothPeripheralsKey = @"UIApplicationLaunchOptionsBluetoothPeripheralsKey";
NSString * const UIApplicationStateRestorationSystemVersionKey = @"UIApplicationStateRestorationSystemVersion";
NSString * const UIApplicationStateRestorationTimestampKey = @"UIApplicationStateRestorationTimestamp";
NSString * const UIContentSizeCategoryDidChangeNotification = @"UIContentSizeCategoryDidChangeNotification";
NSString * const UIContentSizeCategoryNewValueKey = @"UIContentSizeCategoryNewValueKey";
