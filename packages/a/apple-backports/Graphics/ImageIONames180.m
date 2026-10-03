#import <ImageIO/ImageIO.h>

// The iOS 18.0 band's ImageIO name constants, 25 of them that the port did not carry, one object per
// release band because release-split refuses an object whose symbols first appear in more than one release.
//
// Fourteen of these are first exported by the iOS 18.0 caches and eleven are in no held rung with an iOS 18.0 annotation, so one object holds the whole of that band's answer.
//
// EVERY VALUE WAS READ FROM THE HOST S OWN ImageIO with dlsym, one process per symbol, and printed as
// text and as bytes by tests/backports/host/imageio-names, which reads this object s values by LINKING it
// into a pure C reader so the value compared against Apple s is the port s own. A convention would have
// been wrong for eleven of these forty-six: kCGImagePropertyAVISDictionary is "{AVIS}", the two TIFF
// position names are "XPosition" and "YPosition", kCGImagePropertyGroupMonoscopicImageLocation is
// "GroupImageIndexMonoscopicImageLocation", and the four monoscopic locations and the three stereo
// aggressor keys are "Center", "Left", "Right", "Unspecified", "Severity", "SubTypeURI" and "Type".
// The same family holds both shapes, so no rule picks the right one and the measurement is the only thing
// that does.
//
// A name is plain data - a caller looks a metadata key up with it - so the port answers it itself and the
// release is never asked. They are const CFStringRef like every other in this family.

extern CFStringRef const kCGImageAuxiliaryDataInfoColorSpace;
extern CFStringRef const kCGImageAuxiliaryDataTypeISOGainMap;
extern CFStringRef const kCGImageDestinationEncodeBaseIsSDR;
extern CFStringRef const kCGImageDestinationEncodeRequest;
extern CFStringRef const kCGImageDestinationEncodeRequestOptions;
extern CFStringRef const kCGImageDestinationEncodeToISOGainmap;
extern CFStringRef const kCGImageDestinationEncodeToISOHDR;
extern CFStringRef const kCGImageDestinationEncodeToSDR;
extern CFStringRef const kCGImageDestinationEncodeTonemapMode;
extern CFStringRef const kCGImagePropertyGroupImageIndexMonoscopic;
extern CFStringRef const kCGImagePropertyGroupImageIsMonoscopicImage;
extern CFStringRef const kCGImagePropertyGroupImageStereoAggressors;
extern CFStringRef const kCGImagePropertyGroupMonoscopicImageLocation;
extern CFStringRef const kCGImageSourceDecodeRequest;
extern CFStringRef const kCGImageSourceDecodeRequestOptions;
extern CFStringRef const kCGImageSourceDecodeToHDR;
extern CFStringRef const kCGImageSourceDecodeToSDR;
extern CFStringRef const kCGImageSourceGenerateImageSpecificLumaScaling;
extern CFStringRef const kIIOMonoscopicImageLocation_Center;
extern CFStringRef const kIIOMonoscopicImageLocation_Left;
extern CFStringRef const kIIOMonoscopicImageLocation_Right;
extern CFStringRef const kIIOMonoscopicImageLocation_Unspecified;
extern CFStringRef const kIIOStereoAggressors_Severity;
extern CFStringRef const kIIOStereoAggressors_SubTypeURI;
extern CFStringRef const kIIOStereoAggressors_Type;

CFStringRef const kCGImageAuxiliaryDataInfoColorSpace = CFSTR("kCGImageAuxiliaryDataInfoColorSpace");
CFStringRef const kCGImageAuxiliaryDataTypeISOGainMap = CFSTR("kCGImageAuxiliaryDataTypeISOGainMap");
CFStringRef const kCGImageDestinationEncodeBaseIsSDR = CFSTR("kCGImageDestinationEncodeBaseIsSDR");
CFStringRef const kCGImageDestinationEncodeRequest = CFSTR("kCGImageDestinationEncodeRequest");
CFStringRef const kCGImageDestinationEncodeRequestOptions = CFSTR("kCGImageDestinationEncodeRequestOptions");
CFStringRef const kCGImageDestinationEncodeToISOGainmap = CFSTR("kCGImageDestinationEncodeToISOGainmap");
CFStringRef const kCGImageDestinationEncodeToISOHDR = CFSTR("kCGImageDestinationEncodeToISOHDR");
CFStringRef const kCGImageDestinationEncodeToSDR = CFSTR("kCGImageDestinationEncodeToSDR");
CFStringRef const kCGImageDestinationEncodeTonemapMode = CFSTR("kCGImageDestinationEncodeTonemapMode");
CFStringRef const kCGImagePropertyGroupImageIndexMonoscopic = CFSTR("GroupImageIndexMonoscopic");
CFStringRef const kCGImagePropertyGroupImageIsMonoscopicImage = CFSTR("GroupImageIsMonoscopicImage");
CFStringRef const kCGImagePropertyGroupImageStereoAggressors = CFSTR("GroupImageStereoAggressors");
CFStringRef const kCGImagePropertyGroupMonoscopicImageLocation = CFSTR("GroupImageIndexMonoscopicImageLocation");
CFStringRef const kCGImageSourceDecodeRequest = CFSTR("kCGImageSourceDecodeRequest");
CFStringRef const kCGImageSourceDecodeRequestOptions = CFSTR("kCGImageSourceDecodeRequestOptions");
CFStringRef const kCGImageSourceDecodeToHDR = CFSTR("kCGImageSourceDecodeToHDR");
CFStringRef const kCGImageSourceDecodeToSDR = CFSTR("kCGImageSourceDecodeToSDR");
CFStringRef const kCGImageSourceGenerateImageSpecificLumaScaling = CFSTR("kCGImageSourceGenerateImageSpecificLumaScaling");
CFStringRef const kIIOMonoscopicImageLocation_Center = CFSTR("Center");
CFStringRef const kIIOMonoscopicImageLocation_Left = CFSTR("Left");
CFStringRef const kIIOMonoscopicImageLocation_Right = CFSTR("Right");
CFStringRef const kIIOMonoscopicImageLocation_Unspecified = CFSTR("Unspecified");
CFStringRef const kIIOStereoAggressors_Severity = CFSTR("Severity");
CFStringRef const kIIOStereoAggressors_SubTypeURI = CFSTR("SubTypeURI");
CFStringRef const kIIOStereoAggressors_Type = CFSTR("Type");
