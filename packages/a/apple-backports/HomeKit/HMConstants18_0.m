// The HomeKit string constants of iOS 18.0. Every value here was read out of a real
// HomeKit.framework (12.0, 16.0, 18.0) with the project's own dyld cache reader: the symbol's own
// pointer resolved through that cache's slide info, then the __CFConstantString's char* and
// its length, with the bytes read at that address agreeing with the length in every one of them.
// One release's API per object file, which is what the band machinery needs: nothing here arrived
// in any release but this one.
#import <Foundation/Foundation.h>

NSString *const HMAccessoryCategoryTypeAirPort = @"8BFB739C-1E09-4F7B-ABB8-DD7BADD0E8A9";
NSString *const HMAccessoryCategoryTypeAudioReceiver = @"BE15659C-3CE6-4FD0-B152-BCDB488446C6";
NSString *const HMAccessoryCategoryTypeSpeaker = @"C0F5EDC5-4003-464A-9E5D-0DB36677BC35";
NSString *const HMAccessoryCategoryTypeTelevision = @"830C0952-7CD8-44FB-B0C0-DA4EDB0F32A9";
NSString *const HMAccessoryCategoryTypeTelevisionSetTopBox = @"FB953A08-6CDD-44E0-B011-CFAC559A3CFB";
NSString *const HMAccessoryCategoryTypeTelevisionStreamingStick = @"B0C866C4-3E25-4F6A-8476-A8A3B579A86E";
NSString *const HMAccessoryCategoryTypeWiFiRouter = @"337635B4-552A-48AD-A38D-DD2D5E826C9A";
NSString *const HMCharacteristicPropertyRequiresAuthorizationData = @"HMCharacteristicPropertyRequiresAuthorizationData";
NSString *const HMCharacteristicTypeActiveIdentifier = @"000000E7-0000-1000-8000-0026BB765291";
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
NSString *const HMCharacteristicTypeRouterStatus = @"0000020E-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeTargetMediaState = @"00000137-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeTargetVisibilityState = @"00000134-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeVolumeControlType = @"000000E9-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeVolumeSelector = @"000000EA-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeWANStatusList = @"00000212-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeWiFiSatelliteStatus = @"0000021E-0000-1000-8000-0026BB765291";
NSString *const HMServiceTypeInputSource = @"000000D9-0000-1000-8000-0026BB765291";
NSString *const HMServiceTypeTelevision = @"000000D8-0000-1000-8000-0026BB765291";
NSString *const HMServiceTypeWiFiRouter = @"0000020A-0000-1000-8000-0026BB765291";
NSString *const HMServiceTypeWiFiSatellite = @"0000020F-0000-1000-8000-0026BB765291";
