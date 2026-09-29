#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>

// The string constants VideoToolbox declared in iOS 15.0. Where the values come from, and why the value is not the
// constant's own name: the head of VideoToolboxConstants8_0.m. An object carries the API of one release, so the
// 135 are split by the release each arrived in (registry/VideoToolbox/).

const CFStringRef kVTCompressionPropertyKey_BaseLayerBitRateFraction = CFSTR("BaseLayerBitRateFraction");
const CFStringRef kVTCompressionPropertyKey_EnableLTR = CFSTR("EnableLTR");
const CFStringRef kVTCompressionPropertyKey_MaxAllowedFrameQP = CFSTR("MaxAllowedFrameQP");
const CFStringRef kVTCompressionPropertyKey_SupportsBaseFrameQP = CFSTR("SupportsBaseFrameQP");
const CFStringRef kVTEncodeFrameOptionKey_AcknowledgedLTRTokens = CFSTR("AcknowledgedLTRTokens");
const CFStringRef kVTEncodeFrameOptionKey_BaseFrameQP = CFSTR("BaseFrameQP");
const CFStringRef kVTEncodeFrameOptionKey_ForceLTRRefresh = CFSTR("ForceLTRRefresh");
const CFStringRef kVTProfileLevel_H264_ConstrainedBaseline_AutoLevel = CFSTR("H264_ConstrainedBaseline_AutoLevel");
const CFStringRef kVTProfileLevel_H264_ConstrainedHigh_AutoLevel = CFSTR("H264_ConstrainedHigh_AutoLevel");
const CFStringRef kVTSampleAttachmentKey_RequireLTRAcknowledgementToken = CFSTR("RequireLTRAcknowledgementToken");
const CFStringRef kVTVideoEncoderListOption_IncludeStandardDefinitionDVEncoders = CFSTR("IncludeStandardDefinitionDVEncoders");
