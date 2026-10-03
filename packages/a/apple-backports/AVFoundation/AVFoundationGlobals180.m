#import <AVFoundation/AVFoundation.h>

// The AVFoundation constants this object carries, one release's worth: an object may only hold API
// that arrived in one release, and which release that is was MEASURED off the held cache ladder with
// tools/symbol-first-release.lua - the first release whose AVFoundation EXPORTS the name - not read
// off a header's API_AVAILABLE. The two disagree for 28 of the 51 names here, which is
// why the header's own introduced version is not what this file is split by.
//
// Every value below was read, none was typed. 51 of the 51 names were read twice, from two
// independent places that agree: the shared cache of the iOS release that added the name -
// tools/corpus/cache-value.lua reads what the symbol its image exports holds - and the host's own
// AVFoundation, asked with dlopen + dlsym and decoded through CFStringGetCString as UTF-8, recorded
// in coordination/corpus/ledger/constant-values-AVFoundation.tsv with the build it was read on.
// facts/AVFoundation/Globals.md has both runs, their controls, the names they agree on, and the five
// AVCaptureWhiteBalanceTemperatureAndTintValues presets no oracle on this machine can answer.
//
// None of this is the port's minimum release own: it does not export these names, so an application
// that names one loads this string rather than a missing symbol, and where it hands the string to
// the release the release treats it as it treats any string it does not know.
NSString *const AVAssetExportPresetMVHEVC1440x1440 = @"AVAssetExportPresetMVHEVC1440x1440";
NSString *const AVAssetExportPresetMVHEVC960x960 = @"AVAssetExportPresetMVHEVC960x960";
NSString *const AVAssetImageGeneratorDynamicRangePolicyForceSDR = @"ForceSDR";
NSString *const AVAssetImageGeneratorDynamicRangePolicyMatchSource = @"MatchSource";
NSString *const AVAssetPlaybackConfigurationOptionSpatialVideo = @"AVAssetPlaybackConfigurationOptionSpatialVideo";
NSString *const AVCaptionConversionAdjustmentTypeTimeRange = @"AVCaptionConversionAdjustmentTypeTimeRange";
NSString *const AVCaptionConversionWarningTypeExcessMediaData = @"AVCaptionConversionWarningTypeExcessMediaData";
NSString *const AVCaptionMediaSubTypeKey = @"AVCaptionMediaSubTypeKey";
NSString *const AVCaptionMediaTypeKey = @"AVCaptionMediaTypeKey";
NSString *const AVCaptionTimeCodeFrameDurationKey = @"AVCaptionTimeCodeFrameDurationKey";
NSString *const AVCaptionUseDropFrameTimeCodeKey = @"AVCaptionUseDropFrameTimeCodeKey";
NSString *const AVCaptureDeviceTypeContinuityCamera = @"AVCaptureDeviceTypeContinuityCamera";
NSString *const AVCaptureDeviceTypeExternal = @"AVCaptureDeviceTypeExternal";
NSString *const AVCaptureDeviceTypeMicrophone = @"AVCaptureDeviceTypeMicrophone";
NSString *const AVCaptureReactionTypeBalloons = @"ReactionBalloons";
NSString *const AVCaptureReactionTypeConfetti = @"ReactionConfetti";
NSString *const AVCaptureReactionTypeFireworks = @"ReactionFireworks";
NSString *const AVCaptureReactionTypeHeart = @"ReactionHeart";
NSString *const AVCaptureReactionTypeLasers = @"ReactionLasers";
NSString *const AVCaptureReactionTypeRain = @"ReactionRain";
NSString *const AVCaptureReactionTypeThumbsDown = @"ReactionThumbsDown";
NSString *const AVCaptureReactionTypeThumbsUp = @"ReactionThumbsUp";
NSString *const AVFileTypeAHAP = @"public.haptics-content";
NSString *const AVFileTypeAppleiTT = @"com.apple.itunes-timed-text";
NSString *const AVFileTypeSCC = @"com.scenarist.closed-caption";
NSString *const AVMediaCharacteristicCarriesVideoStereoMetadata = @"com.apple.quicktime.video.stereo-metadata";
NSString *const AVMediaCharacteristicContainsStereoMultiviewVideo = @"public.contains-stereo-multiview-video";
NSString *const AVMediaCharacteristicEnhancesSpeechIntelligibility = @"public.accessibility.enhances-speech-intelligibility";
NSString *const AVMediaCharacteristicIndicatesHorizontalFieldOfView = @"public.indicates-horizontal-field-of-view";
NSString *const AVMediaCharacteristicTactileMinimal = @"public.haptics.minimal";
NSString *const AVMetadataIdentifierQuickTimeMetadataCameraFocalLength35mmEquivalent = @"mdta/com.apple.quicktime.camera.focal_length.35mm_equivalent";
NSString *const AVMetadataIdentifierQuickTimeMetadataCameraLensModel = @"mdta/com.apple.quicktime.camera.lens_model";
NSString *const AVMetadataIdentifierQuickTimeMetadataFullFrameRatePlaybackIntent = @"mdta/com.apple.quicktime.full-frame-rate-playback-intent";
NSString *const AVMetadataObjectTypeHumanFullBody = @"humanFullBody";
NSString *const AVMetadataQuickTimeMetadataKeyFullFrameRatePlaybackIntent = @"com.apple.quicktime.full-frame-rate-playback-intent";
NSString *const AVOutputSettingsPresetMVHEVC1440x1440 = @"AVOutputSettingsPresetMVHEVC1440x1440";
NSString *const AVOutputSettingsPresetMVHEVC960x960 = @"AVOutputSettingsPresetMVHEVC960x960";
NSString *const AVPlayerIntegratedTimelineSnapshotsOutOfSyncNotification = @"AVPlayerIntegratedTimelineSnapshotsOutOfSyncNotification";
NSString *const AVPlayerIntegratedTimelineSnapshotsOutOfSyncReasonCurrentSegmentChanged = @"AVPlayerIntegratedTimelineSnapshotsOutOfSyncReasonCurrentSegmentChanged";
NSString *const AVPlayerIntegratedTimelineSnapshotsOutOfSyncReasonKey = @"AVPlayerIntegratedTimelineSnapshotsOutOfSyncReasonKey";
NSString *const AVPlayerIntegratedTimelineSnapshotsOutOfSyncReasonLoadedTimeRangesChanged = @"AVPlayerIntegratedTimelineSnapshotsOutOfSyncReasonLoadedTimeRangesChanged";
NSString *const AVPlayerIntegratedTimelineSnapshotsOutOfSyncReasonSegmentsChanged = @"AVPlayerIntegratedTimelineSnapshotsOutOfSyncReasonSegmentsChanged";
NSString *const AVSampleBufferDisplayLayerReadyForDisplayDidChangeNotification = @"AVSampleBufferDisplayLayerReadyForDisplayDidChangeNotification";
NSString *const AVSpatialCaptureDiscomfortReasonNotEnoughLight = @"AVSpatialCaptureDiscomfortReasonNotEnoughLight";
NSString *const AVSpatialCaptureDiscomfortReasonSubjectTooClose = @"AVSpatialCaptureDiscomfortReasonSubjectTooClose";
NSString *const AVURLAssetOverrideMIMETypeKey = @"AVURLAssetOutOfBandMIMETypeKey";
NSString *const AVVideoCodecTypeAppleProRes4444XQ = @"ap4x";
NSString *const AVVideoCodecTypeJPEGXL = @"jxlc";
NSString *const AVVideoCompositionPerFrameHDRDisplayMetadataPolicyGenerate = @"PerFrameHDRDisplayMetadataPolicy_Generate";
NSString *const AVVideoCompositionPerFrameHDRDisplayMetadataPolicyPropagate = @"PerFrameHDRDisplayMetadataPolicy_Propagate";
NSString *const AVVideoTransferFunction_IEC_sRGB = @"IEC_sRGB";
