#import <CoreFoundation/CoreFoundation.h>
#import <CoreServices/CoreServices.h>

// The names CoreServices added in iOS 9.1, with the texts CoreServices itself gives them, read out
// of the arm64e shared cache of iOS 18.0 through each symbol with tools/cfconst.py (facts/CoreServices/Names.md).
//
// One file for the one release these arrived in: an object carries the API of a single release, and the
// armv7 ladder measures this name first appearing in the cache of iOS 9.1.
//
// The text is the release's own and is not a spelling of the symbol: a uniform type identifier is what a
// file's type is compared by, and a spelling of the constant would be a different type.

CFStringRef const kUTTypeLivePhoto = CFSTR("com.apple.live-photo");
