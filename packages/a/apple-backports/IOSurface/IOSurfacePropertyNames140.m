#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceObjC.h>

// The names IOSurface added in iOS 14.0, with the texts IOSurface itself gives them, read out
// of the arm64e shared cache of iOS 18.0 through each symbol with tools/cfconst.py (facts/IOSurface/Names.md).
//
// One file for the one release these arrived in: an object carries the API of a single release, and the
// armv7 ladder measures this name first appearing in the cache of iOS 14.0.
//
// The text is the release's own and is not a spelling of the symbol: a uniform type identifier is what a
// file's type is compared by, and a spelling of the constant would be a different type.

const CFStringRef kIOSurfaceName = CFSTR("IOSurfaceName");
