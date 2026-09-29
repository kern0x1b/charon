#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>

// The string constants VideoToolbox declared in iOS 16.0. Where the values come from, and why the value is not the
// constant's own name: the head of VideoToolboxConstants8_0.m. An object carries the API of one release, so the
// 135 are split by the release each arrived in (registry/VideoToolbox/).

const CFStringRef kVTCompressionPropertyKey_ConstantBitRate = CFSTR("ConstantBitRate");
const CFStringRef kVTCompressionPropertyKey_EstimatedAverageBytesPerFrame = CFSTR("kVTProCodecPropertyKey_AverageBytesPerFrame");
const CFStringRef kVTCompressionPropertyKey_MinAllowedFrameQP = CFSTR("MinAllowedFrameQP");
const CFStringRef kVTCompressionPropertyKey_PreserveAlphaChannel = CFSTR("kVTCodecPropertyKey_PreserveAlphaChannel");
const CFStringRef kVTCompressionPropertyKey_ReferenceBufferCount = CFSTR("ReferenceBufferCount");
const CFStringRef kVTPixelRotationPropertyKey_FlipHorizontalOrientation = CFSTR("FlipHorizontalOrientation");
const CFStringRef kVTPixelRotationPropertyKey_FlipVerticalOrientation = CFSTR("FlipVerticalOrientation");
const CFStringRef kVTPixelRotationPropertyKey_Rotation = CFSTR("Rotation");
const CFStringRef kVTRotation_0 = CFSTR("Rotation0");
const CFStringRef kVTRotation_180 = CFSTR("Rotation180");
const CFStringRef kVTRotation_CCW90 = CFSTR("RotationCCW90");
const CFStringRef kVTRotation_CW90 = CFSTR("RotationCW90");
