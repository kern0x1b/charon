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
NSString *const CIDetectorAspectRatio = @"CIDetectorAspectRatio";
NSString *const CIDetectorEyeBlink = @"CIDetectorEyeBlink";
NSString *const CIDetectorFocalLength = @"CIDetectorFocalLength";
NSString *const CIDetectorMaxFeatureCount = @"CIDetectorMaxFeatureCount";
NSString *const CIDetectorNumberOfAngles = @"CIDetectorNumberOfAngles";
NSString *const CIDetectorReturnSubFeatures = @"CIDetectorReturnSubFeatures";
NSString *const CIDetectorSmile = @"CIDetectorSmile";
NSString *const CIDetectorTypeQRCode = @"CIDetectorTypeQRCode";
NSString *const CIDetectorTypeRectangle = @"CIDetectorTypeRectangle";
NSString *const CIDetectorTypeText = @"CIDetectorTypeText";
NSString *const kCIUIParameterSet = @"CIUIParameterSet";
NSString *const kCIUISetAdvanced = @"CIUISetAdvanced";
NSString *const kCIUISetBasic = @"CIUISetBasic";
NSString *const kCIUISetDevelopment = @"CIUISetDevelopment";
NSString *const kCIUISetIntermediate = @"CIUISetIntermediate";
NSString *const kCIActiveKeys = @"activeKeys";
NSString *const kCISamplerAffineMatrix = @"affine_matrix";
NSString *const kCISamplerWrapBlack = @"black";
NSString *const kCISamplerWrapClamp = @"clamp";
NSString *const kCISamplerColorSpace = @"color_space";
NSString *const kCISamplerFilterMode = @"filter_mode";
NSString *const kCIContextHighQualityDownsample = @"high_quality_downsample";
NSString *const kCIInputAmountKey = @"inputAmount";
NSString *const kCIInputBacksideImageKey = @"inputBacksideImage";
NSString *const kCIInputBaselineExposureKey = @"inputBaselineExposure";
NSString *const kCIInputBiasKey = @"inputBias";
NSString *const kCIInputBiasVectorKey = @"inputBiasVector";
NSString *const kCIInputBoostKey = @"inputBoost";
NSString *const kCIInputBoostShadowAmountKey = @"inputBoostShadowAmount";
NSString *const kCIInputColorKey = @"inputColor";
NSString *const kCIInputColor0Key = @"inputColor0";
NSString *const kCIInputColor1Key = @"inputColor1";
NSString *const kCIInputColorNoiseReductionAmountKey = @"inputColorNoiseReductionAmount";
NSString *const kCIInputColorSpaceKey = @"inputColorSpace";
NSString *const kCIInputContrastKey = @"inputContrast";
NSString *const kCIInputCountKey = @"inputCount";
NSString *const kCIInputDecoderVersionKey = @"inputDecoderVersion";
NSString *const kCIInputDepthImageKey = @"inputDepthImage";
NSString *const kCIInputDisableGamutMapKey = @"inputDisableGamutMap";
NSString *const kCIInputDisparityImageKey = @"inputDisparityImage";
NSString *const kCIInputAllowDraftModeKey = @"inputDraftMode";
NSString *const kCIInputEVKey = @"inputEV";
NSString *const kCIInputEnableEDRModeKey = @"inputEnableEDRMode";
NSString *const kCIInputEnableChromaticNoiseTrackingKey = @"inputEnableNoiseTracking";
NSString *const kCIInputEnableSharpeningKey = @"inputEnableSharpening";
NSString *const kCIInputEnableVendorLensCorrectionKey = @"inputEnableVendorLensCorrection";
NSString *const kCIInputExtentKey = @"inputExtent";
NSString *const kCIInputExtrapolateKey = @"inputExtrapolate";
NSString *const kCIInputGradientImageKey = @"inputGradientImage";
NSString *const kCIInputIgnoreImageOrientationKey = @"inputIgnoreOrientation";
NSString *const kCIInputImageOrientationKey = @"inputImageOrientation";
NSString *const kCIInputLinearSpaceFilter = @"inputLinearSpaceFilter";
NSString *const kCIInputLocalToneMapAmountKey = @"inputLocalToneMapAmount";
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
NSString *const kCIInputPaletteImageKey = @"inputPaletteImage";
NSString *const kCIInputPerceptualKey = @"inputPerceptual";
NSString *const kCIInputPoint0Key = @"inputPoint0";
NSString *const kCIInputPoint1Key = @"inputPoint1";
NSString *const kCIInputRadius0Key = @"inputRadius0";
NSString *const kCIInputRadius1Key = @"inputRadius1";
NSString *const kCIInputRefractionKey = @"inputRefraction";
NSString *const kCIInputScaleFactorKey = @"inputScaleFactor";
NSString *const kCIInputShadingImageKey = @"inputShadingImage";
NSString *const kCIInputSharpnessKey = @"inputSharpness";
NSString *const kCIInputTargetImageKey = @"inputTargetImage";
NSString *const kCIInputThresholdKey = @"inputThreshold";
NSString *const kCIInputTimeKey = @"inputTime";
NSString *const kCIInputTransformKey = @"inputTransform";
NSString *const kCIInputWeightsKey = @"inputWeights";
NSString *const kCIInputWidthKey = @"inputWidth";
NSString *const kCIContextAllowLowPower = @"kCIContextAllowLowPower";
NSString *const kCIContextCVMetalTextureCache = @"kCIContextCVMetalTextureCache";
NSString *const kCIContextMemoryLimit = @"kCIContextMemoryLimit";
NSString *const kCIContextName = @"kCIContextName";
NSString *const kCIDynamicRangeConstrainedHigh = @"kCIDynamicRangeConstrainedHigh";
NSString *const kCIDynamicRangeHigh = @"kCIDynamicRangeHigh";
NSString *const kCIDynamicRangeStandard = @"kCIDynamicRangeStandard";
NSString *const kCIImageApplyCleanAperture = @"kCIImageApplyCleanAperture";
NSString *const kCIImageApplyOrientationProperty = @"kCIImageApplyOrientationProperty";
NSString *const kCIImageAutoAdjustCrop = @"kCIImageAutoAdjustCrop";
NSString *const kCIImageAutoAdjustLevel = @"kCIImageAutoAdjustLevel";
NSString *const kCIImageAuxiliaryDepth = @"kCIImageAuxiliaryDepth";
NSString *const kCIImageAuxiliaryDisparity = @"kCIImageAuxiliaryDisparity";
NSString *const kCIImageAuxiliaryHDRGainMap = @"kCIImageAuxiliaryHDRGainMap";
NSString *const kCIImageAuxiliaryPortraitEffectsMatte = @"kCIImageAuxiliaryPortraitEffectsMatte";
NSString *const kCIImageAuxiliarySemanticSegmentationGlassesMatte = @"kCIImageAuxiliarySemanticSegmentationGlassesMatte";
NSString *const kCIImageAuxiliarySemanticSegmentationHairMatte = @"kCIImageAuxiliarySemanticSegmentationHairMatte";
NSString *const kCIImageAuxiliarySemanticSegmentationSkinMatte = @"kCIImageAuxiliarySemanticSegmentationSkinMatte";
NSString *const kCIImageAuxiliarySemanticSegmentationSkyMatte = @"kCIImageAuxiliarySemanticSegmentationSkyMatte";
NSString *const kCIImageAuxiliarySemanticSegmentationTeethMatte = @"kCIImageAuxiliarySemanticSegmentationTeethMatte";
NSString *const kCIImageContentAverageLightLevel = @"kCIImageContentAverageLightLevel";
NSString *const kCIImageContentHeadroom = @"kCIImageContentHeadroom";
NSString *const kCIImageExpandToHDR = @"kCIImageExpandToHDR";
NSString *const kCIImageRepresentationAVDepthData = @"kCIImageRepresentationAVDepthData";
NSString *const kCIImageRepresentationAVPortraitEffectsMatte = @"kCIImageRepresentationAVPortraitEffectsMatte";
NSString *const kCIImageRepresentationAVSemanticSegmentationMattes = @"kCIImageRepresentationAVSemanticSegmentationMattes";
NSString *const kCIImageRepresentationDepthImage = @"kCIImageRepresentationDepthImage";
NSString *const kCIImageRepresentationDisparityImage = @"kCIImageRepresentationDisparityImage";
NSString *const kCIImageRepresentationHDRGainMapAsRGB = @"kCIImageRepresentationHDRGainMapAsRGB";
NSString *const kCIImageRepresentationHDRGainMapImage = @"kCIImageRepresentationHDRGainMapImage";
NSString *const kCIImageRepresentationHDRImage = @"kCIImageRepresentationHDRImage";
NSString *const kCIImageRepresentationPortraitEffectsMatteImage = @"kCIImageRepresentationPortraitEffectsMatteImage";
NSString *const kCIImageRepresentationSemanticSegmentationGlassesMatteImage = @"kCIImageRepresentationSemanticSegmentationGlassesMatteImage";
NSString *const kCIImageRepresentationSemanticSegmentationHairMatteImage = @"kCIImageRepresentationSemanticSegmentationHairMatteImage";
NSString *const kCIImageRepresentationSemanticSegmentationSkinMatteImage = @"kCIImageRepresentationSemanticSegmentationSkinMatteImage";
NSString *const kCIImageRepresentationSemanticSegmentationSkyMatteImage = @"kCIImageRepresentationSemanticSegmentationSkyMatteImage";
NSString *const kCIImageRepresentationSemanticSegmentationTeethMatteImage = @"kCIImageRepresentationSemanticSegmentationTeethMatteImage";
NSString *const kCIImageToneMapHDRtoSDR = @"kCIImageToneMapHDRtoSDR";
NSString *const kCISamplerFilterLinear = @"linear";
NSString *const kCISamplerFilterNearest = @"nearest";
NSString *const kCIOutputNativeSizeKey = @"outputNativeSize";
NSString *const kCIContextOutputPremultiplied = @"output_premultiplied";
NSString *const kCIPropertiesKey = @"properties";
NSString *const kCISupportedDecoderVersionsKey = @"supportedDecoderVersions";
NSString *const kCIImageProviderTileSize = @"tile_size";
NSString *const kCIImageProviderUserInfo = @"user_info";
NSString *const kCIContextWorkingFormat = @"working_format";
NSString *const kCISamplerWrapMode = @"wrap_mode";

// The pixel formats CoreImage renders to, as the four-character codes the framework exports them
// under. They are not enum cases: the header declares each as an exported constant, so an application
// that names one needs the symbol and iOS 6 does not export it. Every value is the one the host's own
// symbol holds, read by tests/backports/host/ciimage/constvalues.m.
CIFormat kCIFormatA8 = 257;
CIFormat kCIFormatLA8 = 260;
CIFormat kCIFormatR8 = 261;
CIFormat kCIFormatA16 = 1793;
CIFormat kCIFormatL16 = 1795;
CIFormat kCIFormatLA16 = 1796;
CIFormat kCIFormatR16 = 1797;
CIFormat kCIFormatRG16 = 1798;
CIFormat kCIFormatRGBA16 = 1800;
CIFormat kCIFormatAh = 2049;
CIFormat kCIFormatLh = 2051;
CIFormat kCIFormatLAh = 2052;
CIFormat kCIFormatRh = 2053;
CIFormat kCIFormatRGh = 2054;
CIFormat kCIFormatAf = 2305;
CIFormat kCIFormatLf = 2307;
CIFormat kCIFormatLAf = 2308;
CIFormat kCIFormatRf = 2309;
CIFormat kCIFormatRGf = 2310;
CIFormat kCIFormatRGBAf = 2312;

// Not carried here, because the 16.4 header does not declare them and this port is written against
// it: kCIFormatRGB10, kCIFormatRGBX16, kCIFormatRGBXf, kCIFormatRGBXh. They arrived in iOS 14.2 and 17.0, and their values are in the run named above.
