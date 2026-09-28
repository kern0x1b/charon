/* crop.m -- the crop-and-scale rules against Core ML's own image constructor, pixel for pixel.
 *
 * The port's request path brings a handler's picture to the size a model declares
 * (CharonVisionImage.h). The oracle for how Core ML does that is Core ML's own image constructor,
 * which is what facts/Vision/Vision.md cites: the same CGImage, the same target size, the two
 * CVPixelBuffers compared byte for byte. One program, built twice -- once against the framework's
 * own resampler and once against the port's, which is compiled with the rest of the library under
 * names of its own by the harness -- so the only thing that differs between the two answers is
 * which resampler produced the pixels.
 *
 * Every case prints `differing=N of M`, and the harness fails the run if any N is not zero.
 */
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreML/CoreML.h>
#import <Foundation/Foundation.h>

#ifdef CHARON_PORT_BUILD
#import <Vision/Vision.h>
/* The port's two functions, the header's interpolation left at its default. */
#import "CharonVisionImage.h"
#endif

/* A picture with structure rather than a flat colour, so a resampler that is off by a row or a
 * channel shows up: a left-to-right red ramp crossed with a top-to-bottom green one, with the blue
 * channel carrying a diagonal, which a paste and a blend cannot both reproduce. */
static CGImageRef picture(size_t wide, size_t high)
{
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    /* 32 bits a pixel in the same order as the target format: a 24-bit image has no alpha and
     * Core ML's own constructor refuses to make a buffer of one ("Failed to form pixel buffer from
     * CGImage"), which is the same reason the port's buffer helper draws with the same order. */
    CGContextRef context = CGBitmapContextCreate(NULL, wide, high, 8, 0, space,
                                                 kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGImageRef image = NULL;
    size_t x, y;
    CGColorSpaceRelease(space);
    if (context == NULL) {
        return NULL;
    }
    for (y = 0; y < high; y++) {
        for (x = 0; x < wide; x++) {
            CGContextSetRGBFillColor(context, (CGFloat)x / (CGFloat)(wide > 0 ? wide : 1),
                                     (CGFloat)y / (CGFloat)(high > 0 ? high : 1),
                                     (CGFloat)((x + y) % 7) / 7.0, 1.0);
            CGContextFillRect(context, CGRectMake((CGFloat)x, (CGFloat)y, 1, 1));
        }
    }
    image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return image;
}

/* Core ML's own constructor, which is the oracle: it takes the picture, the size to bring it to and
 * the options, and answers a buffer. */
static CVPixelBufferRef oracle(CGImageRef image, size_t wide, size_t high, BOOL cropAndScale)
{
    NSError *failure = nil;
    NSDictionary *options = cropAndScale ? @{ MLFeatureValueImageOptionCropAndScale : @YES } : @{};
    MLFeatureValue *value = [MLFeatureValue featureValueWithCGImage:image
                                                       pixelsWide:wide
                                                       pixelsHigh:high
                                                  pixelFormatType:kCVPixelFormatType_32BGRA
                                                          options:options
                                                            error:&failure];
    if (value == nil) {
        fprintf(stderr, "the oracle refused: %s\n", failure.localizedDescription.UTF8String);
        return NULL;
    }
    /* Retained: the value that held it is a local here and is gone when this returns, and a
     * buffer that is read afterwards has to have outlived its owner. */
    return (CVPixelBufferRef)CVPixelBufferRetain(value.imageBufferValue);
}

#ifdef CHARON_PORT_BUILD
/* The port's own: a picture into a buffer, then that buffer brought to the size with the option. */
static CVPixelBufferRef port_answer(CGImageRef image, size_t wide, size_t high, VNImageCropAndScaleOption option)
{
    CVPixelBufferRef source = charon_vision_buffer_of_image(image);
    CVPixelBufferRef answer;
    if (source == NULL) {
        return NULL;
    }
    answer = charon_vision_pixels(source, wide, high, option);
    CVPixelBufferRelease(source);
    /* The same: charon_vision_pixels answers a buffer it made, and the caller owns it. */
    return answer;
}
#endif

/* Byte for byte, over the whole of the buffer: four bytes a pixel, which is what both sides are
 * asked for (kCVPixelFormatType_32BGRA) and so what the comparison can be over. */
static long differing(CVPixelBufferRef want, CVPixelBufferRef got, size_t *of)
{
    long different = 0;
    size_t index, count = 0;
    const uint8_t *a, *b;
    if (want == NULL || got == NULL) {
        *of = 0;
        return -1;
    }
    if (CVPixelBufferGetWidth(want) != CVPixelBufferGetWidth(got) ||
        CVPixelBufferGetHeight(want) != CVPixelBufferGetHeight(got)) {
        *of = 0;
        return -1;
    }
    CVPixelBufferLockBaseAddress(want, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferLockBaseAddress(got, kCVPixelBufferLock_ReadOnly);
    a = (const uint8_t *)CVPixelBufferGetBaseAddress(want);
    b = (const uint8_t *)CVPixelBufferGetBaseAddress(got);
    for (index = 0; index < CVPixelBufferGetBytesPerRow(want) * CVPixelBufferGetHeight(want); index += 4) {
        if (a[index] != b[index] || a[index + 1] != b[index + 1] || a[index + 2] != b[index + 2] ||
            a[index + 3] != b[index + 3]) {
            different++;
        }
        count++;
    }
    CVPixelBufferUnlockBaseAddress(want, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferUnlockBaseAddress(got, kCVPixelBufferLock_ReadOnly);
    *of = count;
    return different;
}

int main(int argc, const char *argv[])
{
    /* the two options this port carries, and the sizes: the review's two, an exact 1:1, and an
     * integer 2x, which is the one where a fractional scale does not arise at all. */
    struct {
        size_t from_wide, from_high, to_wide, to_high;
    } sizes[] = {{100, 50, 224, 224}, {13, 7, 8, 8}, {16, 16, 16, 16}, {8, 8, 16, 16}, {4, 7, 33, 9}};
    size_t index;
    long worst = 0;

    @autoreleasepool {
        for (index = 0; index < sizeof(sizes) / sizeof(sizes[0]); index++) {
            CGImageRef image = picture(sizes[index].from_wide, sizes[index].from_high);
            int option;
            for (option = 0; option < 2; option++) {
                CVPixelBufferRef want = oracle(image, sizes[index].to_wide, sizes[index].to_high, YES);
#ifdef CHARON_PORT_BUILD
                CVPixelBufferRef got = port_answer(image, sizes[index].to_wide, sizes[index].to_high,
                                                    option == 0 ? VNImageCropAndScaleOptionCenterCrop
                                                               : VNImageCropAndScaleOptionScaleFit);
#else
                CVPixelBufferRef got = oracle(image, sizes[index].to_wide, sizes[index].to_high, YES);
                (void)option;
#endif
                size_t of = 0;
                long difference = differing(want, got, &of);
                printf("%zux%zu to %zux%zu option %s: differing=%ld of %zu\n", sizes[index].from_wide,
                       sizes[index].from_high, sizes[index].to_wide, sizes[index].to_high,
                       option == 0 ? "centrecrop" : "scalefit", difference, of);
                if (difference > worst) {
                    worst = difference;
                }
                if (want != NULL) {
                    CVPixelBufferRelease(want);
                }
                if (got != NULL) {
                    CVPixelBufferRelease(got);
                }
            }
            CGImageRelease(image);
        }
    }
    (void)argc;
    (void)argv;
    printf("worst differing pixels: %ld\n", worst);
    return worst == 0 ? 0 : 1;
}
