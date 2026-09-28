#import <CoreImage/CoreImage.h>
#import <CoreGraphics/CoreGraphics.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

// -imageByUnpremultiplyingAlpha.
//
// The release has no filter that divides by alpha - CIDivideBlendMode is absent from its 6.1.3 cache -
// and no kernel it can compile one from, so the arithmetic is the port's own, over the release's own
// rendering of the image, and what comes back is a CIImage over the port's own bytes.
//
// What the host does, measured and not assumed (tests/backports/host/ciimage/pixel asks it over the
// whole probe):
//
//   finite extent   the extent is unchanged, each channel is divided by the alpha, a result over one is
//                   clamped to one, the alpha is untouched, and a premultiply followed by an
//                   unpremultiply is the identity - 487584e5 either way
//   infinite extent the image comes back **still infinite and not rendered**, so there is nothing to
//                   divide, and the port answers the image itself
//
// The infinite case is why this does not take an eager render: a render of an infinite extent is not
// an image, it is an allocation of whatever size the caller guessed, and the host does not do it.

@interface CIImage (CharonUnpremultiply)
- (CIImage *)charon_unpremultiplied;
@end

@implementation CIImage (CharonUnpremultiply)

- (CIImage *)charon_unpremultiplied
{
    CGRect bounds = self.extent;
    if (CGRectIsNull(bounds) || CGRectIsEmpty(bounds))
        return self;
    // An infinite extent is the host's own answer: the image comes back as it is, and nothing is
    // rendered, because there is no finite rectangle to render it over.
    if (!CGRectIsInfinite(bounds) && !CGRectIsNull(CGRectIntersection(bounds, CGRectMake(-1e6, -1e6, 2e6, 2e6))))
        return self;

    CGRect whole = CGRectIntegral(bounds);
    size_t width = (size_t)ceil(whole.size.width), height = (size_t)ceil(whole.size.height);
    if (!width || !height)
        return self;
    NSMutableData *bytes = [NSMutableData dataWithLength:width * height * 4];
    CIContext *context = [CIContext contextWithOptions:@{kCIContextWorkingColorSpace: [NSNull null]}];
    [context render:self toBitmap:bytes.mutableBytes rowBytes:(NSInteger)(width * 4) bounds:whole
           format:kCIFormatRGBA8 colorSpace:CGColorSpaceCreateDeviceRGB()];

    uint8_t *pixels = bytes.mutableBytes;
    size_t count = width * height;
    for (size_t k = 0; k < count; k++) {
        uint8_t *pixel = pixels + k * 4;
        unsigned alpha = pixel[3];
        if (!alpha)
            continue;
        for (int channel = 0; channel < 3; channel++) {
            // each channel over its own alpha, a result over one is one
            unsigned value = (unsigned)pixel[channel] * 255 / alpha;
            pixel[channel] = (uint8_t)MIN(255, value);
        }
    }
    return [CIImage imageWithBitmapData:bytes bytesPerRow:width * 4 size:whole.size format:kCIFormatRGBA8
                            colorSpace:CGColorSpaceCreateDeviceRGB()];
}

- (CIImage *)imageByUnpremultiplyingAlpha
{
    return [self charon_unpremultiplied];
}

@end
