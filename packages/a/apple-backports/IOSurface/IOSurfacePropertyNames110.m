#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceObjC.h>

// The names IOSurface added in iOS 11.0, with the texts IOSurface itself gives them, read out
// of the arm64e shared cache of iOS 18.0 through each symbol with tools/cfconst.py (facts/IOSurface/Names.md).
//
// One file for the one release these arrived in: an object carries the API of a single release, and the
// armv7 ladder measures this name first appearing in the cache of iOS 11.0.
//
// The text is the release's own and is not a spelling of the symbol: a uniform type identifier is what a
// file's type is compared by, and a spelling of the constant would be a different type.

IOSurfacePropertyKey IOSurfacePropertyAllocSizeKey = @"IOSurfaceAllocSize";
IOSurfacePropertyKey IOSurfacePropertyKeyBytesPerElement = @"IOSurfaceBytesPerElement";
IOSurfacePropertyKey IOSurfacePropertyKeyBytesPerRow = @"IOSurfaceBytesPerRow";
IOSurfacePropertyKey IOSurfacePropertyKeyCacheMode = @"IOSurfaceCacheMode";
IOSurfacePropertyKey IOSurfacePropertyKeyElementHeight = @"IOSurfaceElementHeight";
IOSurfacePropertyKey IOSurfacePropertyKeyElementWidth = @"IOSurfaceElementWidth";
IOSurfacePropertyKey IOSurfacePropertyKeyHeight = @"IOSurfaceHeight";
IOSurfacePropertyKey IOSurfacePropertyKeyOffset = @"IOSurfaceOffset";
IOSurfacePropertyKey IOSurfacePropertyKeyPixelFormat = @"IOSurfacePixelFormat";
IOSurfacePropertyKey IOSurfacePropertyKeyPixelSizeCastingAllowed = @"IOSurfacePixelSizeCastingAllowed";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneBase = @"IOSurfacePlaneBase";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneBytesPerElement = @"IOSurfacePlaneBytesPerElement";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneBytesPerRow = @"IOSurfacePlaneBytesPerRow";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneElementHeight = @"IOSurfacePlaneElementHeight";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneElementWidth = @"IOSurfacePlaneElementWidth";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneHeight = @"IOSurfacePlaneHeight";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneInfo = @"IOSurfacePlaneInfo";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneOffset = @"IOSurfacePlaneOffset";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneSize = @"IOSurfacePlaneSize";
IOSurfacePropertyKey IOSurfacePropertyKeyPlaneWidth = @"IOSurfacePlaneWidth";
IOSurfacePropertyKey IOSurfacePropertyKeyWidth = @"IOSurfaceWidth";
const CFStringRef kIOSurfacePixelSizeCastingAllowed = CFSTR("IOSurfacePixelSizeCastingAllowed");
const CFStringRef kIOSurfacePlaneBitsPerElement = CFSTR("IOSurfacePlaneBitsPerElement");
const CFStringRef kIOSurfacePlaneComponentBitDepths = CFSTR("IOSurfacePlaneComponentBitDepths");
const CFStringRef kIOSurfacePlaneComponentBitOffsets = CFSTR("IOSurfacePlaneComponentBitOffsets");
const CFStringRef kIOSurfacePlaneComponentNames = CFSTR("IOSurfacePlaneComponentNames");
const CFStringRef kIOSurfacePlaneComponentRanges = CFSTR("IOSurfacePlaneComponentRanges");
const CFStringRef kIOSurfacePlaneComponentTypes = CFSTR("IOSurfacePlaneComponentTypes");
const CFStringRef kIOSurfaceSubsampling = CFSTR("IOSurfaceSubsampling");
