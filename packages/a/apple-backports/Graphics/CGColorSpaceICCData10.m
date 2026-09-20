#import <CoreGraphics/CoreGraphics.h>

CFDataRef CGColorSpaceCopyICCData(CGColorSpaceRef space)
{
    return CGColorSpaceCopyICCProfile(space);
}

bool CGColorSpaceUsesExtendedRange(CGColorSpaceRef space)
{
    return false;
}
