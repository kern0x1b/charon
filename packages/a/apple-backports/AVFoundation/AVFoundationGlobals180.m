#import <AVFoundation/AVFoundation.h>

// The AVFoundation constants iOS 18.0 added, which the releases this port targets do not export.
// One object per release: an object may only carry API that arrived in one of them, which the gate
// reads off the stub.
//
// Every value below was MEASURED, not written out by hand. 23 of the 23 names in this file
// were read twice, from two independent places that agree: the shared cache of the iOS release that
// added the name - tools/corpus/cache-value.lua reads what the symbol its image exports holds - and
// the host's own AVFoundation, asked with dlopen + dlsym and decoded through CFStringGetCString as
// UTF-8, recorded in coordination/corpus/ledger/constant-values-AVFoundation.tsv with the build it
// was read on. facts/AVFoundation/Globals.md has both runs, the names they agree on and the ones
// only one of them could reach.
//
// None of this is the port's minimum release own: it does not export these names, so an application
// that names one loads this string rather than a missing symbol, and where it hands the string to
// the release the release treats it as it treats any string it does not know.
NSString *const AVAssetImageGeneratorDynamicRangePolicyForceSDR = @"ForceSDR";
NSString *const AVAssetImageGeneratorDynamicRangePolicyMatchSource = @"MatchSource";
NSString *const AVAssetPlaybackConfigurationOptionSpatialVideo = @"AVAssetPlaybackConfigurationOptionSpatialVideo";
NSString *const AVCaptionConversionAdjustmentTypeTimeRange = @"AVCaptionConversionAdjustmentTypeTimeRange";
NSString *const AVCaptionConversionWarningTypeExcessMediaData = @"AVCaptionConversionWarningTypeExcessMediaData";
NSString *const AVCaptionMediaSubTypeKey = @"AVCaptionMediaSubTypeKey";
NSString *const AVCaptionMediaTypeKey = @"AVCaptionMediaTypeKey";
NSString *const AVCaptionTimeCodeFrameDurationKey = @"AVCaptionTimeCodeFrameDurationKey";
NSString *const AVCaptionUseDropFrameTimeCodeKey = @"AVCaptionUseDropFrameTimeCodeKey";
NSString *const AVFileTypeAppleiTT = @"com.apple.itunes-timed-text";
NSString *const AVFileTypeSCC = @"com.scenarist.closed-caption";
NSString *const AVMetadataIdentifierQuickTimeMetadataFullFrameRatePlaybackIntent = @"mdta/com.apple.quicktime.full-frame-rate-playback-intent";
NSString *const AVMetadataQuickTimeMetadataKeyFullFrameRatePlaybackIntent = @"com.apple.quicktime.full-frame-rate-playback-intent";
NSString *const AVPlayerIntegratedTimelineSnapshotsOutOfSyncNotification = @"AVPlayerIntegratedTimelineSnapshotsOutOfSyncNotification";
NSString *const AVPlayerIntegratedTimelineSnapshotsOutOfSyncReasonCurrentSegmentChanged = @"AVPlayerIntegratedTimelineSnapshotsOutOfSyncReasonCurrentSegmentChanged";
NSString *const AVPlayerIntegratedTimelineSnapshotsOutOfSyncReasonKey = @"AVPlayerIntegratedTimelineSnapshotsOutOfSyncReasonKey";
NSString *const AVPlayerIntegratedTimelineSnapshotsOutOfSyncReasonLoadedTimeRangesChanged = @"AVPlayerIntegratedTimelineSnapshotsOutOfSyncReasonLoadedTimeRangesChanged";
NSString *const AVPlayerIntegratedTimelineSnapshotsOutOfSyncReasonSegmentsChanged = @"AVPlayerIntegratedTimelineSnapshotsOutOfSyncReasonSegmentsChanged";
NSString *const AVSpatialCaptureDiscomfortReasonNotEnoughLight = @"AVSpatialCaptureDiscomfortReasonNotEnoughLight";
NSString *const AVSpatialCaptureDiscomfortReasonSubjectTooClose = @"AVSpatialCaptureDiscomfortReasonSubjectTooClose";
NSString *const AVVideoCodecTypeAppleProRes4444XQ = @"ap4x";
NSString *const AVVideoCodecTypeJPEGXL = @"jxlc";
NSString *const AVVideoTransferFunction_IEC_sRGB = @"IEC_sRGB";
