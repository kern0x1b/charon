#import <CoreImage/CoreImage.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

// The names of the inputs, outputs and options CoreImage's own filters and contexts are given their
// parameters by, and the names of the metadata attributes a filter is described by. iOS 6 carries
// some of them and not the rest, and the ones it does not carry are here: every value is the string
// the release's own filters read the parameter by, read off the host's CoreImage rather than
// written out by hand. facts/CoreImage/Constants.md has the run that read them.
// Split by release: an object may only carry API that arrived in one of them, which the gate
// reads off the stub. The values are the host's own symbols; facts/CoreImage/Constants.md.
NSString *const kCIContextAllowLowPower = @"kCIContextAllowLowPower";
NSString *const kCIImageAuxiliaryHDRGainMap = @"kCIImageAuxiliaryHDRGainMap";
NSString *const kCIImageAuxiliarySemanticSegmentationGlassesMatte = @"kCIImageAuxiliarySemanticSegmentationGlassesMatte";
NSString *const kCIImageAuxiliarySemanticSegmentationHairMatte = @"kCIImageAuxiliarySemanticSegmentationHairMatte";
NSString *const kCIImageAuxiliarySemanticSegmentationSkinMatte = @"kCIImageAuxiliarySemanticSegmentationSkinMatte";
NSString *const kCIImageAuxiliarySemanticSegmentationSkyMatte = @"kCIImageAuxiliarySemanticSegmentationSkyMatte";
NSString *const kCIImageAuxiliarySemanticSegmentationTeethMatte = @"kCIImageAuxiliarySemanticSegmentationTeethMatte";
NSString *const kCIImageRepresentationAVSemanticSegmentationMattes = @"kCIImageRepresentationAVSemanticSegmentationMattes";
NSString *const kCIImageRepresentationHDRGainMapImage = @"kCIImageRepresentationHDRGainMapImage";
NSString *const kCIImageRepresentationSemanticSegmentationGlassesMatteImage = @"kCIImageRepresentationSemanticSegmentationGlassesMatteImage";
NSString *const kCIImageRepresentationSemanticSegmentationHairMatteImage = @"kCIImageRepresentationSemanticSegmentationHairMatteImage";
NSString *const kCIImageRepresentationSemanticSegmentationSkinMatteImage = @"kCIImageRepresentationSemanticSegmentationSkinMatteImage";
NSString *const kCIImageRepresentationSemanticSegmentationSkyMatteImage = @"kCIImageRepresentationSemanticSegmentationSkyMatteImage";
NSString *const kCIImageRepresentationSemanticSegmentationTeethMatteImage = @"kCIImageRepresentationSemanticSegmentationTeethMatteImage";
NSString *const kCIImageToneMapHDRtoSDR = @"kCIImageToneMapHDRtoSDR";
NSString *const kCIInputLocalToneMapAmountKey = @"inputLocalToneMapAmount";
NSString *const kCIPropertiesKey = @"properties";
