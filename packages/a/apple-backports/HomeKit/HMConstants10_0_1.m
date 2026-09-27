// The HomeKit string constants of iOS 10.0.1. Every value here was read out of a real
// HomeKit.framework (12.0, 16.0, 18.0) with the project's own dyld cache reader: the symbol's own
// pointer resolved through that cache's slide information, then the __CFConstantString's
// char* and its length, with the bytes read at that address agreeing with the length in
// every one of them.
//
// The release in the file's name is the one tools/release-split.lua measures as the first
// that exports these symbols, not the one the 26.2 header annotates: for 63 of the framework's
// constants the two differ, the header is the later of the two, and the band machinery places an
// object by the measurement. facts/HomeKit/HMConstants.md lists every divergence.
#import <Foundation/Foundation.h>

NSString *const HMAccessoryCategoryTypeIPCamera = @"C9EE63DB-2FF7-4514-826A-2FC2F0D4C9F0";
NSString *const HMAccessoryCategoryTypeVideoDoorbell = @"957A52E0-BE03-490C-8305-7B20C1CC17BA";
NSString *const HMActionSetTypeTriggerOwned = @"HMActionSetTypeTriggerOwned";
NSString *const HMCharacteristicMetadataUnitsMicrogramsPerCubicMeter = @"micrograms/m^3";
NSString *const HMCharacteristicMetadataUnitsPartsPerMillion = @"ppm";
NSString *const HMCharacteristicPropertyRequiresAuthorizationData = @"HMCharacteristicPropertyRequiresAuthorizationData";
NSString *const HMCharacteristicTypeDigitalZoom = @"0000011D-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeImageMirroring = @"0000011F-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeImageRotation = @"0000011E-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeMute = @"0000011A-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeNightVision = @"0000011B-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeOpticalZoom = @"0000011C-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeSelectedStreamConfiguration = @"00000117-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeSetupStreamEndpoint = @"00000118-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeStreamingStatus = @"00000120-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeSupportedAudioStreamConfiguration = @"00000115-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeSupportedRTPConfiguration = @"00000116-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeSupportedVideoStreamConfiguration = @"00000114-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeVolume = @"00000119-0000-1000-8000-0026BB765291";
NSString *const HMServiceTypeCameraControl = @"00000111-0000-1000-8000-0026BB765291";
NSString *const HMServiceTypeCameraRTPStreamManagement = @"00000110-0000-1000-8000-0026BB765291";
NSString *const HMServiceTypeDoorbell = @"00000121-0000-1000-8000-0026BB765291";
