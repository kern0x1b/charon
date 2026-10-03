#import <AVFoundation/AVFoundation.h>

// The AVFoundation constants iOS 17.0 added, which the releases this port targets do not export.
// One object per release: an object may only carry API that arrived in one of them, which the gate
// reads off the stub.
//
// Every value below was MEASURED, not written out by hand. 29 of the 29 names in this file
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
NSString *const AVAssetExportPresetMVHEVC1440x1440 = @"AVAssetExportPresetMVHEVC1440x1440";
NSString *const AVAssetExportPresetMVHEVC960x960 = @"AVAssetExportPresetMVHEVC960x960";
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
NSString *const AVMediaCharacteristicCarriesVideoStereoMetadata = @"com.apple.quicktime.video.stereo-metadata";
NSString *const AVMediaCharacteristicContainsStereoMultiviewVideo = @"public.contains-stereo-multiview-video";
NSString *const AVMediaCharacteristicEnhancesSpeechIntelligibility = @"public.accessibility.enhances-speech-intelligibility";
NSString *const AVMediaCharacteristicIndicatesHorizontalFieldOfView = @"public.indicates-horizontal-field-of-view";
NSString *const AVMediaCharacteristicTactileMinimal = @"public.haptics.minimal";
NSString *const AVMetadataObjectTypeHumanFullBody = @"humanFullBody";
NSString *const AVOutputSettingsPresetMVHEVC1440x1440 = @"AVOutputSettingsPresetMVHEVC1440x1440";
NSString *const AVOutputSettingsPresetMVHEVC960x960 = @"AVOutputSettingsPresetMVHEVC960x960";
NSString *const AVSampleBufferVideoRendererDidFailToDecodeNotification = @"AVSampleBufferVideoRendererDidFailToDecodeNotification";
NSString *const AVSampleBufferVideoRendererDidFailToDecodeNotificationErrorKey = @"AVSampleBufferVideoRendererDidFailToDecodeNotificationErrorKey";
NSString *const AVSampleBufferVideoRendererRequiresFlushToResumeDecodingDidChangeNotification = @"AVSampleBufferVideoRendererRequiresFlushToResumeDecodingDidChangeNotification";
NSString *const AVURLAssetOverrideMIMETypeKey = @"AVURLAssetOutOfBandMIMETypeKey";
NSString *const AVVideoCompositionPerFrameHDRDisplayMetadataPolicyGenerate = @"PerFrameHDRDisplayMetadataPolicy_Generate";
NSString *const AVVideoCompositionPerFrameHDRDisplayMetadataPolicyPropagate = @"PerFrameHDRDisplayMetadataPolicy_Propagate";
NSString *const AVVideoDecompressionPropertiesKey = @"AVVideoDecompressionPropertiesKey";
