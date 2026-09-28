/* The image a request handler holds, as a pixel buffer of the size a model's image input wants.
 *
 * A header of static inline functions, and not a .m of its own, because two files of this library
 * call them and a C function two files share has to live in a file that exports no symbol: a .m
 * would put both in the dylib's exports, where the registry would owe an entry for a name Core ML
 * does not declare. It is the same reason CharonMLBridge.h and CharonMLConstraints.h are headers.
 *
 * Vision is where this belongs: a Core ML feature value takes a buffer, and turning what a handler
 * holds into one of the size the model asks for -- cropping, scaling, and the two ways a Core ML
 * image input says to do it -- is image handling, not model handling.
 *
 * The two options are the two Vision declares, and they are the two Core ML's own image
 * constructors use:
 *   - centre crop: the image is scaled until it covers the target and the middle is kept, so the
 *     answer is made of the middle of the picture at the model's own aspect;
 *   - scale fit: the image is scaled until it fits inside the target and the rest is left black,
 *     so nothing of the picture is cut away.
 *
 * A buffer that is already the size the model wants is handed on as it is, which is the case a
 * camera frame or a video frame is in and the one that costs nothing: the pixels are not touched
 * at all. A CGImage is drawn into a buffer, because a feature value of the image type takes a
 * buffer and this port carries no image feature value that takes a CGImage (facts/CoreML/CoreML.md
 * says why).
 */
#ifndef CHARON_VISION_IMAGE_H
#define CHARON_VISION_IMAGE_H

#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>

/* The interpolation Core ML's own image constructor uses, as a macro so the check can compile this
 * same function with each of CoreGraphics' qualities and find the one that matches the framework
 * pixel for pixel -- tests/backports/host/vision/crop.m, which is how `High` was chosen. The default
 * is what the measurement says; a caller that wants a different one is the check, not a library. */
#ifndef CHARON_VISION_INTERPOLATION
#define CHARON_VISION_INTERPOLATION kCGInterpolationHigh
#endif

static inline CVPixelBufferRef charon_vision_pixels(CVPixelBufferRef source, size_t wide, size_t high,
                                            VNImageCropAndScaleOption option)
{
    CVPixelBufferRef buffer = NULL;
    CGColorSpaceRef space = NULL;
    CGContextRef context = NULL;
    CGDataProviderRef provider = NULL;
    CGImageRef picture = NULL;
    const uint8_t *bytes;
    size_t sw, sh, stride;

    if (source == NULL || wide == 0 || high == 0) {
        return NULL;
    }
    if (CVPixelBufferGetWidth(source) == wide && CVPixelBufferGetHeight(source) == high) {
        return (CVPixelBufferRef)CVPixelBufferRetain(source);
    }
    if (CVPixelBufferLockBaseAddress(source, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) {
        return NULL;
    }
    sw = CVPixelBufferGetWidth(source);
    sh = CVPixelBufferGetHeight(source);
    stride = CVPixelBufferGetBytesPerRow(source);
    bytes = (const uint8_t *)CVPixelBufferGetBaseAddress(source);
    if (bytes == NULL || sw == 0 || sh == 0 ||
        CVPixelBufferCreate(kCFAllocatorDefault, wide, high, kCVPixelFormatType_32BGRA, NULL, &buffer) !=
            kCVReturnSuccess ||
        CVPixelBufferLockBaseAddress(buffer, 0) != kCVReturnSuccess) {
        CVPixelBufferUnlockBaseAddress(source, kCVPixelBufferLock_ReadOnly);
        if (buffer != NULL) {
            CVPixelBufferRelease(buffer);
        }
        return NULL;
    }
    space = CGColorSpaceCreateDeviceRGB();
    /* The source read as a CGImage, so the two options are applied to a picture rather than to a
     * rectangle of arithmetic: what is drawn is the pixels the handler holds. */
    provider = CGDataProviderCreateWithData(NULL, bytes, stride * sh, NULL);
    if (space != NULL && provider != NULL) {
        picture = CGImageCreate(sw, sh, 8, 32, stride, space,
                                kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little, provider, NULL, NO,
                                kCGRenderingIntentDefault);
    }
    /* The row length is the buffer's own, never width * 4: a CoreVideo buffer pads its rows to a
     * boundary of its own choosing, so a width that is not a multiple of 16 has rows longer than its
     * own pixels, and a context told width * 4 would write over the padding and scramble every row
     * after the first. */
    context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(buffer), wide, high, 8,
                                    CVPixelBufferGetBytesPerRow(buffer), space,
                                    kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    if (context != NULL) {
        CGRect where;
        CGFloat scale;
        /* Core ML's own image constructor blends when the scale is fractional: measured on this
         * host, 100x50 brought to 224x224 leaves 1996 of 50176 pixels different from a paste and
         * 13x7 brought to 8x8 leaves 22 of 64, while a paste leaves every scaled pixel at the
         * colour of its nearest corner. The interpolation quality is the only difference, and this
         * is the one CoreGraphics offers that is not nearest-neighbour: `High` resamples with a
         * smooth kernel, and it is what the numbers above are measured against. */
        CGContextSetInterpolationQuality(context, CHARON_VISION_INTERPOLATION);
        /* Black first, so scale fit's bars are black rather than whatever the buffer held. */
        CGContextSetRGBFillColor(context, 0, 0, 0, 1);
        CGContextFillRect(context, CGRectMake(0, 0, (CGFloat)wide, (CGFloat)high));
        if (option == VNImageCropAndScaleOptionScaleFit) {
            scale = MIN((CGFloat)wide / (CGFloat)sw, (CGFloat)high / (CGFloat)sh);
            where = CGRectMake(((CGFloat)wide - (CGFloat)sw * scale) / 2.0,
                               ((CGFloat)high - (CGFloat)sh * scale) / 2.0, (CGFloat)sw * scale,
                               (CGFloat)sh * scale);
        } else {
            /* Centre crop: the picture is scaled until it *covers* the target -- the shorter side
             * is the target's exactly -- and centred, so the target is a window on the middle of the
             * scaled picture. Drawing it at the target's own size instead would be a scale fit, and
             * the middle would be the middle of nothing: the scale is the whole difference between
             * the two options. */
            scale = MAX((CGFloat)wide / (CGFloat)sw, (CGFloat)high / (CGFloat)sh);
            where = CGRectMake(((CGFloat)wide - (CGFloat)sw * scale) / 2.0,
                               ((CGFloat)high - (CGFloat)sh * scale) / 2.0, (CGFloat)sw * scale,
                               (CGFloat)sh * scale);
        }
        if (picture != NULL) {
            CGContextDrawImage(context, where, picture);
        }
    }
    if (picture != NULL) {
        CGImageRelease(picture);
    }
    if (provider != NULL) {
        CGDataProviderRelease(provider);
    }
    if (context != NULL) {
        CGContextRelease(context);
    }
    if (space != NULL) {
        CGColorSpaceRelease(space);
    }
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    CVPixelBufferUnlockBaseAddress(source, kCVPixelBufferLock_ReadOnly);
    return buffer;
}

/* A CGImage as a pixel buffer of its own size, which is how a picture a caller handed a request
 * handler becomes something a Core ML feature value of the image type can be built from: the
 * helper above resamples from a buffer, so a picture is drawn into one of its own size first and
 * both kinds of image go through one drawing path and one pair of crop-and-scale rules. */
static inline CVPixelBufferRef charon_vision_buffer_of_image(CGImageRef image)
{
    CVPixelBufferRef buffer = NULL;
    CGColorSpaceRef space;
    CGContextRef context;
    size_t wide, high;

    if (image == NULL) {
        return NULL;
    }
    wide = CGImageGetWidth(image);
    high = CGImageGetHeight(image);
    if (wide == 0 || high == 0 ||
        CVPixelBufferCreate(kCFAllocatorDefault, wide, high, kCVPixelFormatType_32BGRA, NULL, &buffer) !=
            kCVReturnSuccess ||
        CVPixelBufferLockBaseAddress(buffer, 0) != kCVReturnSuccess) {
        if (buffer != NULL) {
            CVPixelBufferRelease(buffer);
        }
        return NULL;
    }
    space = CGColorSpaceCreateDeviceRGB();
    context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(buffer), wide, high, 8,
                                    CVPixelBufferGetBytesPerRow(buffer), space,
                                    kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    if (space != NULL) {
        CGColorSpaceRelease(space);
    }
    if (context != NULL) {
        CGContextSetInterpolationQuality(context, CHARON_VISION_INTERPOLATION);
    }
    if (context == NULL) {
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        CVPixelBufferRelease(buffer);
        return NULL;
    }
    CGContextDrawImage(context, CGRectMake(0, 0, (CGFloat)wide, (CGFloat)high), image);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    return buffer;
}

#endif /* CHARON_VISION_IMAGE_H */
