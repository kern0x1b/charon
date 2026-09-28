#import <CoreImage/CoreImage.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

// The names of the inputs, outputs and options CoreImage's own filters and contexts are given their
// parameters by, and the names of the metadata attributes a filter is described by. iOS 6 carries
// some of them and not the rest, and the ones it does not carry are here: every value is the string
// the release's own filters read the parameter by, read off the host's CoreImage rather than
// written out by hand. facts/CoreImage/Constants.md has the run that read them.
// Split by release: an object may only carry API that arrived in one of them, which the gate
// reads off the stub. The values are the host's own symbols; facts/CoreImage/Constants.md.
CIFormat kCIFormatL16 = 1795;
CIFormat kCIFormatLA16 = 1796;
CIFormat kCIFormatLA8 = 260;
CIFormat kCIFormatLAf = 2308;
CIFormat kCIFormatLAh = 2052;
CIFormat kCIFormatLf = 2307;
CIFormat kCIFormatLh = 2051;
CIFormat kCIFormatRGBA16 = 1800;
NSString *const CIDetectorMaxFeatureCount = @"CIDetectorMaxFeatureCount";
NSString *const kCIActiveKeys = @"activeKeys";
NSString *const kCIInputAllowDraftModeKey = @"inputDraftMode";
NSString *const kCIInputBaselineExposureKey = @"inputBaselineExposure";
NSString *const kCIInputBoostKey = @"inputBoost";
NSString *const kCIInputBoostShadowAmountKey = @"inputBoostShadowAmount";
NSString *const kCIInputColorNoiseReductionAmountKey = @"inputColorNoiseReductionAmount";
NSString *const kCIInputDecoderVersionKey = @"inputDecoderVersion";
NSString *const kCIInputDisableGamutMapKey = @"inputDisableGamutMap";
NSString *const kCIInputEnableChromaticNoiseTrackingKey = @"inputEnableNoiseTracking";
NSString *const kCIInputEnableSharpeningKey = @"inputEnableSharpening";
NSString *const kCIInputEnableVendorLensCorrectionKey = @"inputEnableVendorLensCorrection";
NSString *const kCIInputIgnoreImageOrientationKey = @"inputIgnoreOrientation";
NSString *const kCIInputImageOrientationKey = @"inputImageOrientation";
NSString *const kCIInputLinearSpaceFilter = @"inputLinearSpaceFilter";
NSString *const kCIInputLuminanceNoiseReductionAmountKey = @"inputLuminanceNoiseReductionAmount";
NSString *const kCIInputNeutralChromaticityXKey = @"inputNeutralChromaticityX";
NSString *const kCIInputNeutralChromaticityYKey = @"inputNeutralChromaticityY";
NSString *const kCIInputNeutralLocationKey = @"inputNeutralLocation";
NSString *const kCIInputNeutralTemperatureKey = @"inputNeutralTemperature";
NSString *const kCIInputNeutralTintKey = @"inputNeutralTint";
NSString *const kCIInputNoiseReductionAmountKey = @"inputNoiseReductionAmount";
NSString *const kCIInputNoiseReductionContrastAmountKey = @"inputNoiseReductionContrastAmount";
NSString *const kCIInputNoiseReductionDetailAmountKey = @"inputNoiseReductionDetailAmount";
NSString *const kCIInputNoiseReductionSharpnessAmountKey = @"inputNoiseReductionSharpnessAmount";
NSString *const kCIInputScaleFactorKey = @"inputScaleFactor";
NSString *const kCIOutputNativeSizeKey = @"outputNativeSize";
NSString *const kCISupportedDecoderVersionsKey = @"supportedDecoderVersions";
