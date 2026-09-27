#import <CoreImage/CoreImage.h>
#import <CoreGraphics/CoreGraphics.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

@interface CIImageAccumulator (CharonPixels)
- (void)charon_setTexels:(NSData *)texels;
@end

// Dividing a pixel by its own alpha, which no filter of the release can do: CIDivideBlendMode is
// absent from its cache. The arithmetic is over the rendered bytes - the release's own rendering of the
// image - and the result is handed back as a CIImage over the port's own accumulator, whose -image is a
// view of exactly those bytes.
//
// -imageBySamplingNearest is NOT here, and the reason is in facts/CoreImage/ImageAlgebra.md: on the
// release every image is sampled linearly and there is no sampler to mark an image with, so nearest
// sampling is a property of a later transform and not of the image, and the port has nowhere to put the
// mark. An identity here would be the same pixels wearing a claim they have not earned.

// One pass over the rendered bytes, with the operation given as a block. A block rather than a
// function pointer, because the two operations are the two there are and neither of them is a kernel
// worth expressing twice.
static CIImage *CharonCIKernelOver(CIImage *image, void (^operation)(uint8_t *, size_t))
{
    if (!image)
        return nil;
    CGRect bounds = CGRectIntegral(image.extent);
    size_t width = (size_t)bounds.size.width, height = (size_t)bounds.size.height;
    if (!width || !height)
        return nil;
    NSMutableData *bytes = [NSMutableData dataWithLength:width * height * 4];
    CIContext *context = [CIContext contextWithOptions:@{kCIContextWorkingColorSpace: [NSNull null],
                                                       kCIContextOutputPremultiplied: @NO}];
    [context render:image toBitmap:bytes.mutableBytes rowBytes:(NSInteger)(width * 4) bounds:bounds
            format:kCIFormatRGBA8 colorSpace:NULL];
    operation(bytes.mutableBytes, width * height);
    // The bytes go into an accumulator and the image comes back out of it, so what the caller holds is
    // a real CIImage over the port's own bytes: -image is a view of exactly these.
    CIImageAccumulator *accumulator = [CIImageAccumulator imageAccumulatorWithExtent:bounds format:kCIFormatRGBA8];
    [accumulator charon_setTexels:bytes];
    return [accumulator image];
}

@implementation CIImage (CharonCPUKernel)

- (CIImage *)imageByUnpremultiplyingAlpha
{
    // Each channel divided by the alpha it is multiplied by, and a pixel of no alpha left as it is:
    // a colour of nothing cannot be unpremultiplied into a colour.
    return CharonCIKernelOver(self, ^(uint8_t *bytes, size_t pixels) {
        for (size_t k = 0; k < pixels; k++) {
            uint8_t *pixel = bytes + k * 4;
            if (!pixel[3])
                continue;
            for (int channel = 0; channel < 3; channel++)
                pixel[channel] = (uint8_t)MIN(255, (pixel[channel] * 255 + pixel[3] / 2) / pixel[3]);
        }
    });
}

@end
