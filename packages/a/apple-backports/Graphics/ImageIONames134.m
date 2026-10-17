#import <ImageIO/ImageIO.h>

// The two BC name constants ImageIO's headers annotate iOS 12.0. Their symbols first appear in the held
// iOS 13.4 rung, so they are an object of the 13.4 band and not a 12.0 one. The other name of the
// iOS 16.0 band is in ImageIONames160b.m.
//
// A name is plain data - a caller looks a metadata key up with it - so the port answers it itself and the
// release is never asked. They are const CFStringRef like every other in this family.

extern CFStringRef const kCGImagePropertyBCEncoder;
extern CFStringRef const kCGImagePropertyBCFormat;

CFStringRef const kCGImagePropertyBCEncoder = CFSTR("kCGImagePropertyBCEncoder");
CFStringRef const kCGImagePropertyBCFormat = CFSTR("kCGImagePropertyBCFormat");
