// The HomeKit string constants of iOS 18.0. Every value here was read out of a real
// HomeKit.framework (18.0) with the project's own dyld cache reader: the symbol's own
// pointer resolved through that cache's slide information, then the __CFConstantString's
// char* and its length, with the bytes read at that address agreeing with the length in
// every one of them.
//
// The release in the file's name is the one tools/release-split.lua measures as the first
// that exports these symbols, not the one the 26.2 header annotates: for 63 of the framework's
// constants the two differ, the header is the later of the two, and the band machinery places an
// object by the measurement. facts/HomeKit/HMConstants.md lists every divergence.
#import <Foundation/Foundation.h>

NSString *const HMCharacteristicTypeRouterStatus = @"0000020E-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeWANStatusList = @"00000212-0000-1000-8000-0026BB765291";
NSString *const HMCharacteristicTypeWiFiSatelliteStatus = @"0000021E-0000-1000-8000-0026BB765291";
NSString *const HMServiceTypeWiFiRouter = @"0000020A-0000-1000-8000-0026BB765291";
NSString *const HMServiceTypeWiFiSatellite = @"0000020F-0000-1000-8000-0026BB765291";
