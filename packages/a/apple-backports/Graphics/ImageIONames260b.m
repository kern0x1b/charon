#import <ImageIO/ImageIO.h>

// The iOS 26.0 band's ImageIO name constants, 12 of them that the port did not carry, one object per
// release band because release-split refuses an object whose symbols first appear in more than one release.
//
// The twelve are in no held rung and are annotated iOS 26.0; ImageIONames260.m already holds the one 26.0 name the port had, and a second object of the same band is what the split by symbol asks for.
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

extern CFStringRef const kCGComputeHDRStats;
extern CFStringRef const kCGImageDestinationEncodeAlternateColorSpace;
extern CFStringRef const kCGImageDestinationEncodeBaseColorSpace;
extern CFStringRef const kCGImageDestinationEncodeBasePixelFormatRequest;
extern CFStringRef const kCGImageDestinationEncodeGainMapPixelFormatRequest;
extern CFStringRef const kCGImageDestinationEncodeGainMapSubsampleFactor;
extern CFStringRef const kCGImageDestinationEncodeGenerateGainMapWithBaseImage;
extern CFStringRef const kCGImageDestinationEncodeIsBaseImage;
extern CFStringRef const kCGImagePropertyASTCBlockSize4x4;
extern CFStringRef const kCGImagePropertyASTCBlockSize8x8;
extern CFStringRef const kCGImageProviderPreferredTileHeight;
extern CFStringRef const kCGImageProviderPreferredTileWidth;

CFStringRef const kCGComputeHDRStats = CFSTR("kCGComputeHDRStats");
CFStringRef const kCGImageDestinationEncodeAlternateColorSpace = CFSTR("kCGImageDestinationEncodeAlternateColorSpace");
CFStringRef const kCGImageDestinationEncodeBaseColorSpace = CFSTR("kCGImageDestinationEncodeBaseColorSpace");
CFStringRef const kCGImageDestinationEncodeBasePixelFormatRequest = CFSTR("kCGImageDestinationEncodeBasePixelFormatRequest");
CFStringRef const kCGImageDestinationEncodeGainMapPixelFormatRequest = CFSTR("kCGImageDestinationEncodeGainMapPixelFormatRequest");
CFStringRef const kCGImageDestinationEncodeGainMapSubsampleFactor = CFSTR("kCGImageDestinationEncodeGainMapSubsampleFactor");
CFStringRef const kCGImageDestinationEncodeGenerateGainMapWithBaseImage = CFSTR("kCGImageDestinationEncodeGenerateGainMapWithBaseImage");
CFStringRef const kCGImageDestinationEncodeIsBaseImage = CFSTR("kCGImageDestinationEncodeIsBaseImage");
CFStringRef const kCGImagePropertyASTCBlockSize4x4 = CFSTR("kCGImagePropertyASTCBlockSize4x4");
CFStringRef const kCGImagePropertyASTCBlockSize8x8 = CFSTR("kCGImagePropertyASTCBlockSize8x8");
CFStringRef const kCGImageProviderPreferredTileHeight = CFSTR("kCGImageProviderPreferredTileHeight");
CFStringRef const kCGImageProviderPreferredTileWidth = CFSTR("kCGImageProviderPreferredTileWidth");
