#import <ImageIO/ImageIO.h>

// The iOS 10.0.1 band's ImageIO name constants, 4 of them that the port did not carry, one object per
// release band because release-split refuses an object whose symbols first appear in more than one release.
//
// The release's own caches first export these four symbols at iOS 10.0.1, and the 10.0.1 band has no object of its own yet.
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

extern CFStringRef const kCGImagePropertyASTCBlockSize;
extern CFStringRef const kCGImagePropertyASTCEncoder;
extern CFStringRef const kCGImagePropertyEncoder;
extern CFStringRef const kCGImagePropertyPVREncoder;

CFStringRef const kCGImagePropertyASTCBlockSize = CFSTR("kCGImagePropertyASTCBlockSize");
CFStringRef const kCGImagePropertyASTCEncoder = CFSTR("kCGImagePropertyASTCEncoder");
CFStringRef const kCGImagePropertyEncoder = CFSTR("kCGImagePropertyEncoder");
CFStringRef const kCGImagePropertyPVREncoder = CFSTR("kCGImagePropertyPVREncoder");
