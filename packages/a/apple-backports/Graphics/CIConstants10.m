#import <CoreImage/CoreImage.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

// The names of the inputs, outputs and options CoreImage's own filters and contexts are given their
// parameters by, and the names of the metadata attributes a filter is described by. iOS 6 carries
// some of them and not the rest, and the ones it does not carry are here: every value is the string
// the release's own filters read the parameter by, read off the host's CoreImage rather than
// written out by hand. facts/CoreImage/Constants.md has the run that read them.

NSString *const kCIAttributeDescription = @"CIAttributeDescription";
NSString *const kCIAttributeFilterAvailable_Mac = @"CIAttributeFilterAvailable_Mac";
NSString *const kCIAttributeFilterAvailable_iOS = @"CIAttributeFilterAvailable_iOS";
NSString *const kCIAttributeReferenceDocumentation = @"CIAttributeReferenceDocumentation";
NSString *const kCIAttributeTypeGradient = @"CIAttributeTypeGradient";
NSString *const kCIAttributeTypeOpaqueColor = @"CIAttributeTypeOpaqueColor";
NSString *const kCICategoryFilterGenerator = @"CICategoryFilterGenerator";
NSString *const kCIUIParameterSet = @"CIUIParameterSet";
NSString *const kCIUISetAdvanced = @"CIUISetAdvanced";
NSString *const kCIUISetBasic = @"CIUISetBasic";
NSString *const kCIUISetDevelopment = @"CIUISetDevelopment";
NSString *const kCIUISetIntermediate = @"CIUISetIntermediate";
NSString *const kCIActiveKeys = @"activeKeys";
NSString *const kCIContextHighQualityDownsample = @"high_quality_downsample";
NSString *const kCIInputAmountKey = @"inputAmount";
NSString *const kCIInputBaselineExposureKey = @"inputBaselineExposure";
NSString *const kCIInputBiasKey = @"inputBias";
NSString *const kCIInputBoostKey = @"inputBoost";
NSString *const kCIInputBoostShadowAmountKey = @"inputBoostShadowAmount";
NSString *const kCIInputColorKey = @"inputColor";
NSString *const kCIInputColorNoiseReductionAmountKey = @"inputColorNoiseReductionAmount";
NSString *const kCIInputContrastKey = @"inputContrast";
NSString *const kCIInputDecoderVersionKey = @"inputDecoderVersion";
NSString *const kCIInputDepthImageKey = @"inputDepthImage";
NSString *const kCIInputDisableGamutMapKey = @"inputDisableGamutMap";
NSString *const kCIInputDisparityImageKey = @"inputDisparityImage";
NSString *const kCIInputEVKey = @"inputEV";
NSString *const kCIInputEnableChromaticNoiseTrackingKey = @"inputEnableNoiseTracking";
NSString *const kCIInputEnableSharpeningKey = @"inputEnableSharpening";
NSString *const kCIInputEnableVendorLensCorrectionKey = @"inputEnableVendorLensCorrection";
NSString *const kCIInputExtentKey = @"inputExtent";
NSString *const kCIInputGradientImageKey = @"inputGradientImage";
NSString *const kCIInputIgnoreImageOrientationKey = @"inputIgnoreOrientation";
NSString *const kCIInputImageOrientationKey = @"inputImageOrientation";
NSString *const kCIInputLuminanceNoiseReductionAmountKey = @"inputLuminanceNoiseReductionAmount";
NSString *const kCIInputMatteImageKey = @"inputMatteImage";
NSString *const kCIInputMoireAmountKey = @"inputMoireAmount";
NSString *const kCIInputNeutralChromaticityXKey = @"inputNeutralChromaticityX";
NSString *const kCIInputNeutralChromaticityYKey = @"inputNeutralChromaticityY";
NSString *const kCIInputNeutralLocationKey = @"inputNeutralLocation";
NSString *const kCIInputNeutralTemperatureKey = @"inputNeutralTemperature";
NSString *const kCIInputNeutralTintKey = @"inputNeutralTint";
NSString *const kCIInputNoiseReductionAmountKey = @"inputNoiseReductionAmount";
NSString *const kCIInputNoiseReductionContrastAmountKey = @"inputNoiseReductionContrastAmount";
NSString *const kCIInputNoiseReductionDetailAmountKey = @"inputNoiseReductionDetailAmount";
NSString *const kCIInputNoiseReductionSharpnessAmountKey = @"inputNoiseReductionSharpnessAmount";
NSString *const kCIInputRefractionKey = @"inputRefraction";
NSString *const kCIInputScaleFactorKey = @"inputScaleFactor";
NSString *const kCIInputShadingImageKey = @"inputShadingImage";
NSString *const kCIInputSharpnessKey = @"inputSharpness";
NSString *const kCIInputTargetImageKey = @"inputTargetImage";
NSString *const kCIInputTimeKey = @"inputTime";
NSString *const kCIInputTransformKey = @"inputTransform";
NSString *const kCIInputWeightsKey = @"inputWeights";
NSString *const kCIInputWidthKey = @"inputWidth";
NSString *const kCIContextAllowLowPower = @"kCIContextAllowLowPower";
NSString *const kCIContextCVMetalTextureCache = @"kCIContextCVMetalTextureCache";
NSString *const kCIContextMemoryLimit = @"kCIContextMemoryLimit";
NSString *const kCIContextName = @"kCIContextName";
NSString *const kCIOutputNativeSizeKey = @"outputNativeSize";
NSString *const kCIContextOutputPremultiplied = @"output_premultiplied";
NSString *const kCIPropertiesKey = @"properties";
NSString *const kCISupportedDecoderVersionsKey = @"supportedDecoderVersions";
NSString *const kCIContextWorkingFormat = @"working_format";
NSString *const kCISamplerWrapMode = @"wrap_mode";
