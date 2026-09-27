// The HomeKit string constants of iOS 8.3. Every value here was read out of a real
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

NSString *const HMCharacteristicMetadataUnitsSeconds = @"seconds";
