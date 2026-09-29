#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>

// The 135 string constants of VideoToolbox, each at the value it was MEASURED to have.
//
// Where the values come from, and why not from the release: the host cache on this machine is a 753KB
// stub (magic "dyld", not 0xfeedfacf) and the release's own 6.1.3 armv7 cache refuses to be read at
// all - it was copied from a running device and 3709 of its pages hold slid pointers, which is why
// tools/cfconst.py cannot use it. The host's VideoToolbox exports all 135 symbols and implements them,
// so each value was read out of the host's own code (tests/backports/host/videotoolbox) and this file
// is written from that table. Nothing here is a rule.
//
// The thing worth writing down, because it is the reason the table was needed at all: NONE of the 135
// values is the constant's own name. 117 are the last underscore-separated part of the name, 7 are
// everything after "kVT", and 11 are neither - among them
//   kVTCompressionPropertyKey_EstimatedAverageBytesPerFrame = kVTProCodecPropertyKey_AverageBytesPerFrame
//   kVTRotation_0                                            = Rotation0
//   kVTRotation_CCW90                                        = RotationCCW90
// A string constant written as its own name - the form this package uses for MXErrorDomain and
// PKPushTypeVoIP, both MEASURED to be right - would have been wrong in all 135.


const CFStringRef kVTAlphaChannelMode_PremultipliedAlpha = CFSTR("PremultipliedAlpha");
const CFStringRef kVTAlphaChannelMode_StraightAlpha = CFSTR("StraightAlpha");
const CFStringRef kVTCameraCalibrationExtrinsicOriginSource_StereoCameraSystemBaseline = CFSTR("StereoCameraSystemBaseline");
const CFStringRef kVTCameraCalibrationLensAlgorithmKind_ParametricLens = CFSTR("ParametricLens");
const CFStringRef kVTCameraCalibrationLensDomain_Color = CFSTR("Color");
const CFStringRef kVTCameraCalibrationLensRole_Left = CFSTR("Left");
const CFStringRef kVTCameraCalibrationLensRole_Mono = CFSTR("Mono");
const CFStringRef kVTCameraCalibrationLensRole_Right = CFSTR("Right");
const CFStringRef kVTCompressionPreset_Balanced = CFSTR("Balanced");
const CFStringRef kVTCompressionPreset_HighQuality = CFSTR("HighQuality");
const CFStringRef kVTCompressionPreset_HighSpeed = CFSTR("HighSpeed");
const CFStringRef kVTCompressionPreset_VideoConferencing = CFSTR("VideoConferencing");
const CFStringRef kVTCompressionPropertyCameraCalibrationKey_ExtrinsicOrientationQuaternion = CFSTR("ExtrinsicOrientationQuaternion");
const CFStringRef kVTCompressionPropertyCameraCalibrationKey_ExtrinsicOriginSource = CFSTR("ExtrinsicOriginSource");
const CFStringRef kVTCompressionPropertyCameraCalibrationKey_IntrinsicMatrix = CFSTR("IntrinsicMatrix");
const CFStringRef kVTCompressionPropertyCameraCalibrationKey_IntrinsicMatrixProjectionOffset = CFSTR("IntrinsicMatrixProjectionOffset");
const CFStringRef kVTCompressionPropertyCameraCalibrationKey_IntrinsicMatrixReferenceDimensions = CFSTR("IntrinsicMatrixReferenceDimensions");
const CFStringRef kVTCompressionPropertyCameraCalibrationKey_LensAlgorithmKind = CFSTR("LensAlgorithmKind");
const CFStringRef kVTCompressionPropertyCameraCalibrationKey_LensDistortions = CFSTR("LensDistortions");
const CFStringRef kVTCompressionPropertyCameraCalibrationKey_LensDomain = CFSTR("LensDomain");
const CFStringRef kVTCompressionPropertyCameraCalibrationKey_LensFrameAdjustmentsPolynomialX = CFSTR("LensFrameAdjustmentsPolynomialX");
const CFStringRef kVTCompressionPropertyCameraCalibrationKey_LensFrameAdjustmentsPolynomialY = CFSTR("LensFrameAdjustmentsPolynomialY");
const CFStringRef kVTCompressionPropertyCameraCalibrationKey_LensIdentifier = CFSTR("LensIdentifier");
const CFStringRef kVTCompressionPropertyCameraCalibrationKey_LensRole = CFSTR("LensRole");
const CFStringRef kVTCompressionPropertyCameraCalibrationKey_RadialAngleLimit = CFSTR("RadialAngleLimit");
const CFStringRef kVTCompressionPropertyKey_AllowOpenGOP = CFSTR("AllowOpenGOP");
const CFStringRef kVTCompressionPropertyKey_AlphaChannelMode = CFSTR("AlphaChannelMode");
const CFStringRef kVTCompressionPropertyKey_BaseLayerBitRateFraction = CFSTR("BaseLayerBitRateFraction");
const CFStringRef kVTCompressionPropertyKey_BaseLayerFrameRate = CFSTR("BaseLayerFrameRate");
const CFStringRef kVTCompressionPropertyKey_BaseLayerFrameRateFraction = CFSTR("BaseLayerFrameRateFraction");
const CFStringRef kVTCompressionPropertyKey_CalculateMeanSquaredError = CFSTR("CalculateMeanSquaredError");
const CFStringRef kVTCompressionPropertyKey_CameraCalibrationDataLensCollection = CFSTR("CameraCalibrationDataLensCollection");
const CFStringRef kVTCompressionPropertyKey_ConstantBitRate = CFSTR("ConstantBitRate");
const CFStringRef kVTCompressionPropertyKey_ContentLightLevelInfo = CFSTR("ContentLightLevelInfo");
const CFStringRef kVTCompressionPropertyKey_EnableLTR = CFSTR("EnableLTR");
const CFStringRef kVTCompressionPropertyKey_EncoderID = CFSTR("EncoderID");
const CFStringRef kVTCompressionPropertyKey_EstimatedAverageBytesPerFrame = CFSTR("kVTProCodecPropertyKey_AverageBytesPerFrame");
const CFStringRef kVTCompressionPropertyKey_GammaLevel = CFSTR("GammaLevel");
const CFStringRef kVTCompressionPropertyKey_HDRMetadataInsertionMode = CFSTR("HDRMetadataInsertionMode");
const CFStringRef kVTCompressionPropertyKey_HasLeftStereoEyeView = CFSTR("HasLeftStereoEyeView");
const CFStringRef kVTCompressionPropertyKey_HasRightStereoEyeView = CFSTR("HasRightStereoEyeView");
const CFStringRef kVTCompressionPropertyKey_HeroEye = CFSTR("HeroEye");
const CFStringRef kVTCompressionPropertyKey_HorizontalDisparityAdjustment = CFSTR("HorizontalDisparityAdjustment");
const CFStringRef kVTCompressionPropertyKey_HorizontalFieldOfView = CFSTR("HorizontalFieldOfView");
const CFStringRef kVTCompressionPropertyKey_MVHEVCLeftAndRightViewIDs = CFSTR("MVHEVCLeftAndRightViewIDs");
const CFStringRef kVTCompressionPropertyKey_MVHEVCVideoLayerIDs = CFSTR("MVHEVCVideoLayerIDs");
const CFStringRef kVTCompressionPropertyKey_MVHEVCViewIDs = CFSTR("MVHEVCViewIDs");
const CFStringRef kVTCompressionPropertyKey_MasteringDisplayColorVolume = CFSTR("MasteringDisplayColorVolume");
const CFStringRef kVTCompressionPropertyKey_MaxAllowedFrameQP = CFSTR("MaxAllowedFrameQP");
const CFStringRef kVTCompressionPropertyKey_MaximizePowerEfficiency = CFSTR("MaximizePowerEfficiency");
const CFStringRef kVTCompressionPropertyKey_MaximumRealTimeFrameRate = CFSTR("MaximumRealTimeFrameRate");
const CFStringRef kVTCompressionPropertyKey_MinAllowedFrameQP = CFSTR("MinAllowedFrameQP");
const CFStringRef kVTCompressionPropertyKey_MultiPassStorage = CFSTR("MultiPassStorage");
const CFStringRef kVTCompressionPropertyKey_OutputBitDepth = CFSTR("OutputBitDepth");
const CFStringRef kVTCompressionPropertyKey_PreserveAlphaChannel = CFSTR("kVTCodecPropertyKey_PreserveAlphaChannel");
const CFStringRef kVTCompressionPropertyKey_PreserveDynamicHDRMetadata = CFSTR("PreserveDynamicHDRMetadata");
const CFStringRef kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality = CFSTR("PrioritizeEncodingSpeedOverQuality");
const CFStringRef kVTCompressionPropertyKey_ProjectionKind = CFSTR("ProjectionKind");
const CFStringRef kVTCompressionPropertyKey_RecommendedParallelizedSubdivisionMinimumDuration = CFSTR("RecommendedParallelizedSubdivisionMinimumDuration");
const CFStringRef kVTCompressionPropertyKey_RecommendedParallelizedSubdivisionMinimumFrameCount = CFSTR("RecommendedParallelizedSubdivisionMinimumFrameCount");
const CFStringRef kVTCompressionPropertyKey_ReferenceBufferCount = CFSTR("ReferenceBufferCount");
const CFStringRef kVTCompressionPropertyKey_StereoCameraBaseline = CFSTR("StereoCameraBaseline");
const CFStringRef kVTCompressionPropertyKey_SupportedPresetDictionaries = CFSTR("SupportedPresetDictionaries");
const CFStringRef kVTCompressionPropertyKey_SupportsBaseFrameQP = CFSTR("SupportsBaseFrameQP");
const CFStringRef kVTCompressionPropertyKey_TargetQualityForAlpha = CFSTR("TargetQualityForAlpha");
const CFStringRef kVTCompressionPropertyKey_UsingGPURegistryID = CFSTR("UsingMetalRegistryID");
const CFStringRef kVTCompressionPropertyKey_VBVBufferDuration = CFSTR("VBVBufferDuration");
const CFStringRef kVTCompressionPropertyKey_VBVInitialDelayPercentage = CFSTR("VBVInitialDelayPercentage");
const CFStringRef kVTCompressionPropertyKey_VBVMaxBitRate = CFSTR("VBVMaxBitRate");
const CFStringRef kVTCompressionPropertyKey_VariableBitRate = CFSTR("VariableBitRate");
const CFStringRef kVTCompressionPropertyKey_ViewPackingKind = CFSTR("ViewPackingKind");
const CFStringRef kVTDecodeFrameOptionKey_ContentAnalyzerCropRectangle = CFSTR("ContentAnalyzerCropRectangle");
const CFStringRef kVTDecodeFrameOptionKey_ContentAnalyzerRotation = CFSTR("ContentAnalyzerRotation");
const CFStringRef kVTDecompressionPropertyKey_AllowBitstreamToChangeFrameDimensions = CFSTR("AllowBitstreamToChangeFrameDimensions");
const CFStringRef kVTDecompressionPropertyKey_GeneratePerFrameHDRDisplayMetadata = CFSTR("GeneratePerFrameHDRDisplayMetadata");
const CFStringRef kVTDecompressionPropertyKey_MaximizePowerEfficiency = CFSTR("MaximizePowerEfficiency");
const CFStringRef kVTDecompressionPropertyKey_OutputPoolRequestedMinimumBufferCount = CFSTR("OutputPoolRequestedMinimumBufferCount");
const CFStringRef kVTDecompressionPropertyKey_PropagatePerFrameHDRDisplayMetadata = CFSTR("PropagatePerFrameHDRDisplayMetadata");
const CFStringRef kVTDecompressionPropertyKey_RequestedMVHEVCVideoLayerIDs = CFSTR("RequestedMVHEVCVideoLayerIDs");
const CFStringRef kVTDecompressionPropertyKey_UsingGPURegistryID = CFSTR("UsingMetalRegistryID");
const CFStringRef kVTDecompressionProperty_TemporalLevelLimit = CFSTR("TemporalLevelLimit");
const CFStringRef kVTEncodeFrameOptionKey_AcknowledgedLTRTokens = CFSTR("AcknowledgedLTRTokens");
const CFStringRef kVTEncodeFrameOptionKey_BaseFrameQP = CFSTR("BaseFrameQP");
const CFStringRef kVTEncodeFrameOptionKey_ForceLTRRefresh = CFSTR("ForceLTRRefresh");
const CFStringRef kVTHDRMetadataInsertionMode_Auto = CFSTR("HDRMetadataInsertionMode_Auto");
const CFStringRef kVTHDRMetadataInsertionMode_None = CFSTR("HDRMetadataInsertionMode_None");
const CFStringRef kVTHDRMetadataInsertionMode_RequestSDRRangePreservation = CFSTR("HDRMetadataInsertionMode_RequestSDRRangePreservation");
const CFStringRef kVTHDRPerFrameMetadataGenerationOptionsKey_HDRFormats = CFSTR("HDRFormats");
const CFStringRef kVTHeroEye_Left = CFSTR("Left");
const CFStringRef kVTHeroEye_Right = CFSTR("Right");
const CFStringRef kVTMotionEstimationSessionCreationOption_Label = CFSTR("Label");
const CFStringRef kVTMotionEstimationSessionCreationOption_MotionVectorSize = CFSTR("MotionVectorSize");
const CFStringRef kVTMotionEstimationSessionCreationOption_UseMultiPassSearch = CFSTR("UseMultiPassSearch");
const CFStringRef kVTMultiPassStorageCreationOption_DoNotDelete = CFSTR("DoNotDelete");
const CFStringRef kVTPixelRotationPropertyKey_FlipHorizontalOrientation = CFSTR("FlipHorizontalOrientation");
const CFStringRef kVTPixelRotationPropertyKey_FlipVerticalOrientation = CFSTR("FlipVerticalOrientation");
const CFStringRef kVTPixelRotationPropertyKey_Rotation = CFSTR("Rotation");
const CFStringRef kVTPixelTransferPropertyKey_DestinationColorPrimaries = CFSTR("DestinationColorPrimaries");
const CFStringRef kVTPixelTransferPropertyKey_DestinationICCProfile = CFSTR("DestinationICCProfile");
const CFStringRef kVTPixelTransferPropertyKey_DestinationTransferFunction = CFSTR("DestinationTransferFunction");
const CFStringRef kVTPixelTransferPropertyKey_DestinationYCbCrMatrix = CFSTR("DestinationYCbCrMatrix");
const CFStringRef kVTPixelTransferPropertyKey_RealTime = CFSTR("RealTime");
const CFStringRef kVTProfileLevel_H264_ConstrainedBaseline_AutoLevel = CFSTR("H264_ConstrainedBaseline_AutoLevel");
const CFStringRef kVTProfileLevel_H264_ConstrainedHigh_AutoLevel = CFSTR("H264_ConstrainedHigh_AutoLevel");
const CFStringRef kVTProfileLevel_HEVC_Main10_AutoLevel = CFSTR("HEVC_Main10_AutoLevel");
const CFStringRef kVTProfileLevel_HEVC_Main42210_AutoLevel = CFSTR("HEVC_Main42210_AutoLevel");
const CFStringRef kVTProfileLevel_HEVC_Main_AutoLevel = CFSTR("HEVC_Main_AutoLevel");
const CFStringRef kVTProfileLevel_HEVC_Monochrome10_AutoLevel = CFSTR("HEVC_Monochrome10_AutoLevel");
const CFStringRef kVTProfileLevel_HEVC_Monochrome_AutoLevel = CFSTR("HEVC_Monochrome_AutoLevel");
const CFStringRef kVTProjectionKind_Equirectangular = CFSTR("Equirectangular");
const CFStringRef kVTProjectionKind_HalfEquirectangular = CFSTR("HalfEquirectangular");
const CFStringRef kVTProjectionKind_ParametricImmersive = CFSTR("ParametricImmersive");
const CFStringRef kVTProjectionKind_Rectilinear = CFSTR("Rectilinear");
const CFStringRef kVTRotation_0 = CFSTR("Rotation0");
const CFStringRef kVTRotation_180 = CFSTR("Rotation180");
const CFStringRef kVTRotation_CCW90 = CFSTR("RotationCCW90");
const CFStringRef kVTRotation_CW90 = CFSTR("RotationCW90");
const CFStringRef kVTSampleAttachmentKey_RequireLTRAcknowledgementToken = CFSTR("RequireLTRAcknowledgementToken");
const CFStringRef kVTSampleAttachmentQualityMetricsKey_ChromaBlueMeanSquaredError = CFSTR("ChromaBlueMeanSquaredError");
const CFStringRef kVTSampleAttachmentQualityMetricsKey_ChromaRedMeanSquaredError = CFSTR("ChromaRedMeanSquaredError");
const CFStringRef kVTSampleAttachmentQualityMetricsKey_LumaMeanSquaredError = CFSTR("LumaMeanSquaredError");
const CFStringRef kVTVideoDecoderSpecification_PreferredDecoderGPURegistryID = CFSTR("PreferredDecoderGPURegistryID");
const CFStringRef kVTVideoDecoderSpecification_RequiredDecoderGPURegistryID = CFSTR("RequiredDecoderGPURegistryID");
const CFStringRef kVTVideoEncoderListOption_IncludeStandardDefinitionDVEncoders = CFSTR("IncludeStandardDefinitionDVEncoders");
const CFStringRef kVTVideoEncoderList_GPURegistryID = CFSTR("GPURegistryID");
const CFStringRef kVTVideoEncoderList_InstanceLimit = CFSTR("InstanceLimit");
const CFStringRef kVTVideoEncoderList_PerformanceRating = CFSTR("PerformanceRating");
const CFStringRef kVTVideoEncoderList_QualityRating = CFSTR("QualityRating");
const CFStringRef kVTVideoEncoderList_SupportedSelectionProperties = CFSTR("SupportedSelectionProperties");
const CFStringRef kVTVideoEncoderList_SupportsFrameReordering = CFSTR("SupportsFrameReordering");
const CFStringRef kVTVideoEncoderSpecification_EnableLowLatencyRateControl = CFSTR("EnableLowLatencyRateControl");
const CFStringRef kVTVideoEncoderSpecification_PreferredEncoderGPURegistryID = CFSTR("PreferredEncoderGPURegistryID");
const CFStringRef kVTVideoEncoderSpecification_RequiredEncoderGPURegistryID = CFSTR("RequiredEncoderGPURegistryID");
const CFStringRef kVTViewPackingKind_OverUnder = CFSTR("OverUnder");
const CFStringRef kVTViewPackingKind_SideBySide = CFSTR("SideBySide");
