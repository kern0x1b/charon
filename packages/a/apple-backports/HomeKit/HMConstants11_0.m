// The HomeKit string constants of iOS 11.0. Every value here was read out of a real
// HomeKit.framework (12.0, 16.0, 18.0) with the project's own dyld cache reader: the symbol's own
// pointer resolved through that cache's slide info, then the __CFConstantString's char* and
// its length, with the bytes read at that address agreeing with the length in every one of them.
// One release's API per object file, which is what the band machinery needs: nothing here arrived
// in any release but this one.
#import <Foundation/Foundation.h>

NSString *const HMCharacteristicTypeColorTemperature = @"000000CE-0000-1000-8000-0026BB765291";
NSString *const HMPresenceKeyPath = @"presence";
