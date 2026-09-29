#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>

// The string constants VideoToolbox declared in iOS 17.0. Where the values come from, and why the value is not the
// constant's own name: the head of VideoToolboxConstants8_0.m. An object carries the API of one release, so the
// 135 are split by the release each arrived in (registry/VideoToolbox/).

const CFStringRef kVTCompressionPropertyKey_HasLeftStereoEyeView = CFSTR("HasLeftStereoEyeView");
const CFStringRef kVTCompressionPropertyKey_HasRightStereoEyeView = CFSTR("HasRightStereoEyeView");
const CFStringRef kVTCompressionPropertyKey_HeroEye = CFSTR("HeroEye");
const CFStringRef kVTCompressionPropertyKey_HorizontalDisparityAdjustment = CFSTR("HorizontalDisparityAdjustment");
const CFStringRef kVTCompressionPropertyKey_MVHEVCLeftAndRightViewIDs = CFSTR("MVHEVCLeftAndRightViewIDs");
const CFStringRef kVTCompressionPropertyKey_MVHEVCVideoLayerIDs = CFSTR("MVHEVCVideoLayerIDs");
const CFStringRef kVTCompressionPropertyKey_MVHEVCViewIDs = CFSTR("MVHEVCViewIDs");
const CFStringRef kVTCompressionPropertyKey_StereoCameraBaseline = CFSTR("StereoCameraBaseline");
const CFStringRef kVTDecompressionPropertyKey_GeneratePerFrameHDRDisplayMetadata = CFSTR("GeneratePerFrameHDRDisplayMetadata");
const CFStringRef kVTDecompressionPropertyKey_RequestedMVHEVCVideoLayerIDs = CFSTR("RequestedMVHEVCVideoLayerIDs");
