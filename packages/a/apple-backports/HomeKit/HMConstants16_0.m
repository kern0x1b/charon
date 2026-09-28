// The HomeKit string constants of iOS 16.0.
//
// **Where these values come from, and how to check them.** Every value below is a value a real
// HomeKit.framework holds, and the host's own HomeKit is on this machine, so each one is
// re-measurable today with three calls and no HomeKit source: `tools/corpus/host-probe.c` opens
// /System/Library/PrivateFrameworks/HomeKit.framework/Versions/A/HomeKit with dlopen, looks the
// symbol up with dlsym, and decodes the `NSString *const` it finds through CFStringGetCString,
// sized by the string's own CFStringGetLength so that a wrong address is a failed conversion
// rather than a plausible wrong answer. Measured for all 255 and recorded in
// coordination/corpus/ledger/constant-values-HomeKit.tsv: 255 asked, 255 exported by the host,
// 255 agreeing with the values below, 0 differing, 0 unreadable.
//
// The caches these were first read from (16.0, 18.0) are named in facts/HomeKit/HMConstants.md.
//
// **The release in this file's name is a different measurement, by a different tool.** Which
// iOS release first exports a symbol is measured by `tools/release-split.lua`, which walks the
// real cache ladder, and the band machinery places an object by that measurement -- so the files
// are named for it and not for the release the 26.2 header annotates. For 63 of the framework's
// constants the two differ, the header is the later of the two, and facts/HomeKit/HMConstants.md
// lists every divergence.
//
// One release's API per object file, which is what the band machinery needs: nothing here
// arrived in any release but this one.

#import <Foundation/Foundation.h>

NSString *const HMAccessoryCategoryTypeAudioReceiver = @"BE15659C-3CE6-4FD0-B152-BCDB488446C6";
NSString *const HMAccessoryCategoryTypeTelevision = @"830C0952-7CD8-44FB-B0C0-DA4EDB0F32A9";
NSString *const HMAccessoryCategoryTypeTelevisionSetTopBox = @"FB953A08-6CDD-44E0-B011-CFAC559A3CFB";
NSString *const HMAccessoryCategoryTypeTelevisionStreamingStick = @"B0C866C4-3E25-4F6A-8476-A8A3B579A86E";
NSString *const HMAccessoryCategoryTypeWiFiRouter = @"337635B4-552A-48AD-A38D-DD2D5E826C9A";
NSString *const HMCharacteristicTypeClosedCaptions = @"000000DD-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeConfiguredName = @"000000E3-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeCurrentMediaState = @"000000E0-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeCurrentVisibilityState = @"00000135-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeIdentifier = @"000000E6-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeInputDeviceType = @"000000DC-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeInputSourceType = @"000000DB-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypePictureMode = @"000000E2-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypePowerModeSelection = @"000000DF-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeRemoteKey = @"000000E1-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeTargetMediaState = @"00000137-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeTargetVisibilityState = @"00000134-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeVolumeControlType = @"000000E9-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeVolumeSelector = @"000000EA-0000-1000-8000-0026BB765291";
NSString *const HMServiceTypeInputSource = @"000000D9-0000-1000-8000-0026BB765291";
NSString *const HMServiceTypeTelevision = @"000000D8-0000-1000-8000-0026BB765291";
