#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>

// The string constants VideoToolbox declared in iOS 13.0. Where the values come from, and why the value is not the
// constant's own name: the head of VideoToolboxConstants8_0.m. An object carries the API of one release, so the
// 135 are split by the release each arrived in (registry/VideoToolbox/).

const CFStringRef kVTAlphaChannelMode_PremultipliedAlpha = CFSTR("PremultipliedAlpha");
const CFStringRef kVTAlphaChannelMode_StraightAlpha = CFSTR("StraightAlpha");
const CFStringRef kVTCompressionPropertyKey_AlphaChannelMode = CFSTR("AlphaChannelMode");
const CFStringRef kVTCompressionPropertyKey_TargetQualityForAlpha = CFSTR("TargetQualityForAlpha");
const CFStringRef kVTCompressionPropertyKey_UsingGPURegistryID = CFSTR("UsingMetalRegistryID");
const CFStringRef kVTDecompressionPropertyKey_UsingGPURegistryID = CFSTR("UsingMetalRegistryID");
const CFStringRef kVTPixelTransferPropertyKey_RealTime = CFSTR("RealTime");
const CFStringRef kVTProfileLevel_HEVC_Monochrome10_AutoLevel = CFSTR("HEVC_Monochrome10_AutoLevel");
const CFStringRef kVTVideoEncoderList_GPURegistryID = CFSTR("GPURegistryID");
const CFStringRef kVTVideoEncoderList_InstanceLimit = CFSTR("InstanceLimit");
const CFStringRef kVTVideoEncoderList_PerformanceRating = CFSTR("PerformanceRating");
const CFStringRef kVTVideoEncoderList_QualityRating = CFSTR("QualityRating");
const CFStringRef kVTVideoEncoderList_SupportedSelectionProperties = CFSTR("SupportedSelectionProperties");
const CFStringRef kVTVideoEncoderSpecification_PreferredEncoderGPURegistryID = CFSTR("PreferredEncoderGPURegistryID");
const CFStringRef kVTVideoEncoderSpecification_RequiredEncoderGPURegistryID = CFSTR("RequiredEncoderGPURegistryID");
