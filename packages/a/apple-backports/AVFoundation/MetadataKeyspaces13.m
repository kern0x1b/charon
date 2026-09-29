#import <AVFoundation/AVFoundation.h>

// 13 constants, the iOS 13.0 metadata key-space names, and nothing else: a name this file does not
// define is a name the corpus's gate asks for and the link cannot find, so the list
// below is the whole of this file's claim and the registry names each one of them.
//
// Every value was read out of the host's own AVFoundation at runtime, one dlsym of
// the exported symbol per name, and the differential in tests/backports/host/avf-metadata
// reads the same table out of two builds - Apple's framework on its own, and this file
// beside it in one binary with the names renamed - and diffs them. A value is not copied
// out of a header; it is what the framework answered, which is why one of them is the
// eleven ASCII characters "udta/%A9ade" and not a copyright sign.
//
// See facts/AVFoundation/MetadataKeySpaces.md.

NSString *const AVMetadataIdentifierQuickTimeMetadataAutoLivePhoto = @"mdta/com.apple.quicktime.live-photo.auto";
NSString *const AVMetadataIdentifierQuickTimeMetadataDetectedCatBody = @"mdta/com.apple.quicktime.detected-cat-body";
NSString *const AVMetadataIdentifierQuickTimeMetadataDetectedDogBody = @"mdta/com.apple.quicktime.detected-dog-body";
NSString *const AVMetadataIdentifierQuickTimeMetadataDetectedHumanBody = @"mdta/com.apple.quicktime.detected-human-body";
NSString *const AVMetadataIdentifierQuickTimeMetadataDetectedSalientObject = @"mdta/com.apple.quicktime.detected-salient-object";
NSString *const AVMetadataIdentifierQuickTimeMetadataLivePhotoVitalityScore = @"mdta/com.apple.quicktime.live-photo.vitality-score";
NSString *const AVMetadataIdentifierQuickTimeMetadataLivePhotoVitalityScoringVersion = @"mdta/com.apple.quicktime.live-photo.vitality-scoring-version";
NSString *const AVMetadataIdentifierQuickTimeMetadataSpatialOverCaptureQualityScore = @"mdta/com.apple.quicktime.spatial-overcapture.quality-score";
NSString *const AVMetadataIdentifierQuickTimeMetadataSpatialOverCaptureQualityScoringVersion = @"mdta/com.apple.quicktime.spatial-overcapture.quality-scoring-version";
NSString *const AVMetadataObjectTypeCatBody = @"catBody";
NSString *const AVMetadataObjectTypeDogBody = @"dogBody";
NSString *const AVMetadataObjectTypeHumanBody = @"humanBody";
NSString *const AVMetadataObjectTypeSalientObject = @"salientObject";
