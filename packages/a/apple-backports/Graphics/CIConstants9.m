#import <CoreImage/CoreImage.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

// The names of the inputs, outputs and options CoreImage's own filters and contexts are given their
// parameters by, and the names of the metadata attributes a filter is described by. iOS 6 carries
// some of them and not the rest, and the ones it does not carry are here: every value is the string
// the release's own filters read the parameter by, read off the host's CoreImage rather than
// written out by hand. facts/CoreImage/Constants.md has the run that read them.
// Split by release: an object may only carry API that arrived in one of them, which the gate
// reads off the stub. The values are the host's own symbols; facts/CoreImage/Constants.md.
CIFormat kCIFormatA16 = 1793;
CIFormat kCIFormatA8 = 257;
CIFormat kCIFormatAf = 2305;
CIFormat kCIFormatAh = 2049;
CIFormat kCIFormatR16 = 1797;
CIFormat kCIFormatR8 = 261;
CIFormat kCIFormatRG16 = 1798;
CIFormat kCIFormatRGf = 2310;
CIFormat kCIFormatRGh = 2054;
CIFormat kCIFormatRf = 2309;
CIFormat kCIFormatRh = 2053;
NSString *const CIDetectorNumberOfAngles = @"CIDetectorNumberOfAngles";
NSString *const CIDetectorReturnSubFeatures = @"CIDetectorReturnSubFeatures";
NSString *const CIDetectorTypeText = @"CIDetectorTypeText";
NSString *const kCIAttributeDescription = @"CIAttributeDescription";
NSString *const kCIAttributeFilterAvailable_Mac = @"CIAttributeFilterAvailable_Mac";
NSString *const kCIAttributeFilterAvailable_iOS = @"CIAttributeFilterAvailable_iOS";
NSString *const kCIAttributeReferenceDocumentation = @"CIAttributeReferenceDocumentation";
NSString *const kCIAttributeTypeGradient = @"CIAttributeTypeGradient";
NSString *const kCIAttributeTypeOpaqueColor = @"CIAttributeTypeOpaqueColor";
NSString *const kCICategoryFilterGenerator = @"CICategoryFilterGenerator";
NSString *const kCIContextHighQualityDownsample = @"high_quality_downsample";
NSString *const kCIImageProviderTileSize = @"tile_size";
NSString *const kCIImageProviderUserInfo = @"user_info";
NSString *const kCIInputBiasKey = @"inputBias";
NSString *const kCIInputGradientImageKey = @"inputGradientImage";
NSString *const kCIInputRefractionKey = @"inputRefraction";
NSString *const kCIInputShadingImageKey = @"inputShadingImage";
NSString *const kCIInputWeightsKey = @"inputWeights";
NSString *const kCISamplerAffineMatrix = @"affine_matrix";
NSString *const kCISamplerColorSpace = @"color_space";
NSString *const kCISamplerFilterLinear = @"linear";
NSString *const kCISamplerFilterMode = @"filter_mode";
NSString *const kCISamplerFilterNearest = @"nearest";
NSString *const kCISamplerWrapBlack = @"black";
NSString *const kCISamplerWrapClamp = @"clamp";
NSString *const kCISamplerWrapMode = @"wrap_mode";
NSString *const kCIUIParameterSet = @"CIUIParameterSet";
NSString *const kCIUISetAdvanced = @"CIUISetAdvanced";
NSString *const kCIUISetBasic = @"CIUISetBasic";
NSString *const kCIUISetDevelopment = @"CIUISetDevelopment";
NSString *const kCIUISetIntermediate = @"CIUISetIntermediate";
// Not carried here, because the 16.4 header does not declare them and this port is written against
// it: kCIFormatRGB10, kCIFormatRGBX16, kCIFormatRGBXf, kCIFormatRGBXh. They arrived in iOS 14.2 and 17.0, and their values are in the run named above.
