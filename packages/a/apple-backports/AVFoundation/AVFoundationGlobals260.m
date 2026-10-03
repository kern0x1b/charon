#import <AVFoundation/AVFoundation.h>

// The AVFoundation constants iOS 26.0 added, which the releases this port targets do not export.
// One object per release: an object may only carry API that arrived in one of them, which the gate
// reads off the stub.
//
// Every value below was MEASURED, not written out by hand. 7 of the 61 names in this file
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
NSString *const AVAssetExportPresetHEVC4320x2160 = @"AVAssetExportPresetHEVC4320x2160";
NSString *const AVAssetExportPresetHEVC7680x4320 = @"AVAssetExportPresetHEVC7680x4320";
NSString *const AVAssetExportPresetMVHEVC4320x4320 = @"AVAssetExportPresetMVHEVC4320x4320";
NSString *const AVAssetExportPresetMVHEVC7680x7680 = @"AVAssetExportPresetMVHEVC7680x7680";
NSString *const AVAssetPlaybackConfigurationOptionNonRectilinearProjection = @"AVAssetPlaybackConfigurationOptionNonRectilinearProjection";
NSString *const AVAssetWriterInputMediaDataLocationSparselyInterleavedWithMainMediaData = @"AVAssetWriterInputMediaDataLocationSparselyInterleavedWithMainMediaData";
NSString *const AVCaptureAspectRatio16x9 = @"AVCaptureAspectRatio16x9";
NSString *const AVCaptureAspectRatio1x1 = @"AVCaptureAspectRatio1x1";
NSString *const AVCaptureAspectRatio3x4 = @"AVCaptureAspectRatio3x4";
NSString *const AVCaptureAspectRatio4x3 = @"AVCaptureAspectRatio4x3";
NSString *const AVCaptureAspectRatio9x16 = @"AVCaptureAspectRatio9x16";
NSString *const AVCaptureSceneMonitoringStatusNotEnoughLight = @"AVCaptureSceneMonitoringStatusNotEnoughLight";
NSString *const AVContentKeyRequestRandomDeviceIdentifierSeedKey = @"RandomDeviceIdentifierSeedKey";
NSString *const AVContentKeyRequestShouldRandomizeDeviceIdentifierKey = @"ShouldRandomizeDeviceIdentifierKey";
NSString *const AVFileTypeDICOM = @"org.nema.dicom";
NSString *const AVFileTypeQuickTimeAudio = @"com.apple.quicktime-audio";
NSString *const AVMediaCharacteristicIndicatesNonRectilinearProjection = @"public.indicates-non-rectilinear-projection";
NSString *const AVMediaCharacteristicMachineGenerated = @"public.machine-generated";
NSString *const AVMetadataIdentifierQuickTimeMetadataCameraFocalLength35mmEquivalent = @"mdta/com.apple.quicktime.camera.focal_length.35mm_equivalent";
NSString *const AVMetadataIdentifierQuickTimeMetadataCameraISOSensitivity = @"mdta/org.smpte.rdd18.camera.isosensitivity";
NSString *const AVMetadataIdentifierQuickTimeMetadataCameraLensIrisFNumber = @"mdta/com.apple.quicktime.camera.lens_irisfnumber";
NSString *const AVMetadataIdentifierQuickTimeMetadataCameraLensModel = @"mdta/com.apple.quicktime.camera.lens_model";
NSString *const AVMetadataIdentifierQuickTimeMetadataCameraShutterSpeedAngle = @"mdta/org.smpte.rdd18.camera.shutterspeed_angle";
NSString *const AVMetadataIdentifierQuickTimeMetadataCameraShutterSpeedTime = @"mdta/org.smpte.rdd18.camera.shutterspeed_time";
NSString *const AVMetadataIdentifierQuickTimeMetadataCameraWhiteBalance = @"mdta/org.smpte.rdd18.camera.whitebalance";
NSString *const AVMetadataIdentifierQuickTimeMetadataCinematicVideoIntent = @"mdta/com.apple.quicktime.cinematic-video-intent";
NSString *const AVMetadataIdentifierQuickTimeMetadataWhiteBalanceByCCTColorMatrices = @"mdta/com.apple.proresraw.whitebalance.bycct.colormatrices";
NSString *const AVMetadataIdentifierQuickTimeMetadataWhiteBalanceByCCTWhiteBalanceFactors = @"mdta/com.apple.proresraw.whitebalance.bycct.whitebalancefactors";
NSString *const AVMetadataObjectTypeCatHead = @"catHead";
NSString *const AVMetadataObjectTypeDogHead = @"dogHead";
NSString *const AVMetadataQuickTimeMetadataKeyCameraFocalLength35mmEquivalent = @"com.apple.quicktime.camera.focal_length.35mm_equivalent";
NSString *const AVMetadataQuickTimeMetadataKeyCameraISOSensitivity = @"org.smpte.rdd18.camera.isosensitivity";
NSString *const AVMetadataQuickTimeMetadataKeyCameraLensIrisFNumber = @"com.apple.quicktime.camera.lens_irisfnumber";
NSString *const AVMetadataQuickTimeMetadataKeyCameraLensModel = @"com.apple.quicktime.camera.lens_model";
NSString *const AVMetadataQuickTimeMetadataKeyCameraShutterSpeedAngle = @"org.smpte.rdd18.camera.shutterspeed_angle";
NSString *const AVMetadataQuickTimeMetadataKeyCameraShutterSpeedTime = @"org.smpte.rdd18.camera.shutterspeed_time";
NSString *const AVMetadataQuickTimeMetadataKeyCameraWhiteBalance = @"org.smpte.rdd18.camera.whitebalance";
NSString *const AVMetadataQuickTimeMetadataKeyCinematicVideoIntent = @"com.apple.quicktime.cinematic-video-intent";
NSString *const AVMetadataQuickTimeMetadataKeyWhiteBalanceByCCTColorMatrices = @"com.apple.proresraw.whitebalance.bycct.colormatrices";
NSString *const AVMetadataQuickTimeMetadataKeyWhiteBalanceByCCTWhiteBalanceFactors = @"com.apple.proresraw.whitebalance.bycct.whitebalancefactors";
NSString *const AVOutputSettingsPresetHEVC4320x2160 = @"AVOutputSettingsPresetHEVC4320x2160";
NSString *const AVOutputSettingsPresetHEVC7680x4320 = @"AVOutputSettingsPresetHEVC7680x4320";
NSString *const AVOutputSettingsPresetMVHEVC4320x4320 = @"AVOutputSettingsPresetMVHEVC4320x4320";
NSString *const AVOutputSettingsPresetMVHEVC7680x7680 = @"AVOutputSettingsPresetMVHEVC7680x7680";
NSString *const AVPlayerInterstitialEventMonitorCurrentEventSkippableStateDidChangeEventKey = @"CurrentEventSkippableStateDidChangeEventKey";
NSString *const AVPlayerInterstitialEventMonitorCurrentEventSkippableStateDidChangeNotification = @"CurrentEventSkippableStateDidChange";
NSString *const AVPlayerInterstitialEventMonitorCurrentEventSkippableStateDidChangeSkipControlLabelKey = @"CurrentEventSkippableStateDidChangeSkipControlLabelKey";
NSString *const AVPlayerInterstitialEventMonitorCurrentEventSkippableStateDidChangeStateKey = @"CurrentEventSkippableStateDidChangeStateKey";
NSString *const AVPlayerInterstitialEventMonitorCurrentEventSkippedEventKey = @"CurrentEventSkippedEventKey";
NSString *const AVPlayerInterstitialEventMonitorCurrentEventSkippedNotification = @"CurrentEventSkipped";
NSString *const AVPlayerInterstitialEventMonitorInterstitialEventDidFinishDidPlayEntireEventKey = @"InterstitialEventDidFinishDidPlayEntireEventKey";
NSString *const AVPlayerInterstitialEventMonitorInterstitialEventDidFinishEventKey = @"InterstitialEventDidFinishEventKey";
NSString *const AVPlayerInterstitialEventMonitorInterstitialEventDidFinishNotification = @"InterstitialEventDidFinish";
NSString *const AVPlayerInterstitialEventMonitorInterstitialEventDidFinishPlayoutTimeKey = @"InterstitialEventDidFinishPlayoutTimeKey";
NSString *const AVPlayerInterstitialEventMonitorInterstitialEventWasUnscheduledErrorKey = @"InterstitialEventWasUnscheduleErrorKey";
NSString *const AVPlayerInterstitialEventMonitorInterstitialEventWasUnscheduledEventKey = @"InterstitialEventWasUnscheduleEventKey";
NSString *const AVPlayerInterstitialEventMonitorInterstitialEventWasUnscheduledNotification = @"InterstitialEventWasUnscheduled";
NSString *const AVTrackAssociationTypeRenderMetadataSource = @"rndr";
NSString *const AVURLAssetShouldParseExternalSphericalTagsKey = @"AVURLAssetShouldParseExternalSphericalTagsKey";
NSString *const AVVideoCodecTypeAppleProResRAW = @"aprn";
NSString *const AVVideoCodecTypeAppleProResRAWHQ = @"aprh";
