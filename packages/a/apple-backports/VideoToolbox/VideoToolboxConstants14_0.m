#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>

// The string constants VideoToolbox declared in iOS 14.0. Where the values come from, and why the value is not the
// constant's own name: the head of VideoToolboxConstants8_0.m. An object carries the API of one release, so the
// 135 are split by the release each arrived in (registry/VideoToolbox/).

const CFStringRef kVTCompressionPropertyKey_HDRMetadataInsertionMode = CFSTR("HDRMetadataInsertionMode");
const CFStringRef kVTCompressionPropertyKey_PreserveDynamicHDRMetadata = CFSTR("PreserveDynamicHDRMetadata");
const CFStringRef kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality = CFSTR("PrioritizeEncodingSpeedOverQuality");
const CFStringRef kVTDecompressionPropertyKey_PropagatePerFrameHDRDisplayMetadata = CFSTR("PropagatePerFrameHDRDisplayMetadata");
const CFStringRef kVTHDRMetadataInsertionMode_Auto = CFSTR("HDRMetadataInsertionMode_Auto");
const CFStringRef kVTHDRMetadataInsertionMode_None = CFSTR("HDRMetadataInsertionMode_None");
const CFStringRef kVTVideoEncoderList_SupportsFrameReordering = CFSTR("SupportsFrameReordering");
