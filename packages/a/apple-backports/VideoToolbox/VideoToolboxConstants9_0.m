#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>

// The string constants VideoToolbox declared in iOS 9.0. Where the values come from, and why the value is not the
// constant's own name: the head of VideoToolboxConstants8_0.m. An object carries the API of one release, so the
// 135 are split by the release each arrived in (registry/VideoToolbox/).

const CFStringRef kVTPixelTransferPropertyKey_DestinationColorPrimaries = CFSTR("DestinationColorPrimaries");
const CFStringRef kVTPixelTransferPropertyKey_DestinationICCProfile = CFSTR("DestinationICCProfile");
const CFStringRef kVTPixelTransferPropertyKey_DestinationTransferFunction = CFSTR("DestinationTransferFunction");
const CFStringRef kVTPixelTransferPropertyKey_DestinationYCbCrMatrix = CFSTR("DestinationYCbCrMatrix");
