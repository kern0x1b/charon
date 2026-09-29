#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>

// The string constants VideoToolbox declared in iOS 17.4. Where the values come from, and why the value is not the
// constant's own name: the head of VideoToolboxConstants8_0.m. An object carries the API of one release, so the
// 135 are split by the release each arrived in (registry/VideoToolbox/).

const CFStringRef kVTCompressionPropertyKey_CalculateMeanSquaredError = CFSTR("CalculateMeanSquaredError");
const CFStringRef kVTCompressionPropertyKey_HorizontalFieldOfView = CFSTR("HorizontalFieldOfView");
const CFStringRef kVTSampleAttachmentQualityMetricsKey_ChromaBlueMeanSquaredError = CFSTR("ChromaBlueMeanSquaredError");
const CFStringRef kVTSampleAttachmentQualityMetricsKey_ChromaRedMeanSquaredError = CFSTR("ChromaRedMeanSquaredError");
const CFStringRef kVTSampleAttachmentQualityMetricsKey_LumaMeanSquaredError = CFSTR("LumaMeanSquaredError");
