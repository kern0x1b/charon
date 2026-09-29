#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>

// The string constants VideoToolbox declared in iOS 12.0. Where the values come from, and why the value is not the
// constant's own name: the head of VideoToolboxConstants8_0.m. An object carries the API of one release, so the
// 135 are split by the release each arrived in (registry/VideoToolbox/).

const CFStringRef kVTCompressionPropertyKey_AllowOpenGOP = CFSTR("AllowOpenGOP");
const CFStringRef kVTCompressionPropertyKey_MaximizePowerEfficiency = CFSTR("MaximizePowerEfficiency");
