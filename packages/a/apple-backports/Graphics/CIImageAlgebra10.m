#import <CoreImage/CoreImage.h>
#import <CoreGraphics/CoreGraphics.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

// The algebra of an image: what a caller does to one between the filter that made it and the renderer
// that draws it. iOS 6 has the filters most of it is made of - CIAffineClamp, CIColorMatrix,
// CIGaussianBlur, CILanczosScaleTransform, CIMaskToAlpha, CIConstantColorGenerator - and does not have
// the operations, so each of these is the release's own filter composed into the operation. One of
// them cannot be: the release has no filter that divides by alpha, so the one that does goes through
// the port's own accumulator, which divides the bytes itself.

@implementation CIImage (CharonAlgebra)

- (CIImage *)imageByApplyingGaussianBlurWithSigma:(CGFloat)sigma
{
    // The release's own gaussian blur, with the sigma the caller gives.
    // Only the keys the filter has - read off the framework itself: inputImage and inputRadius. A
    // filter asked for a key it does not have raises rather than doing nothing.
    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blur setValue:self forKey:kCIInputImageKey];
    [blur setValue:@(sigma) forKey:@"inputRadius"];
    return blur.outputImage ?: self;
}

// How deep this thread is inside a clamp the port is making. -[CIAffineClamp outputImage] clamps its
// own input first, and it does that by asking the input for -[CIImage imageByClampingToRect:] - which
// on a release that has that method is this category, so each clamp asked for another until the stack
// ran out. Measured under -fsanitize=address as a stack overflow with those two frames repeating. A
// thread already inside the port's clamp is answering the framework's own question, and the answer is
// the image it has; a thread that is not is the caller and gets the clamp.
//
// The depth is per thread, in the thread's own dictionary and not in a thread-local: the armv7 target
// has no thread-local storage, and clang says so - "thread-local storage is not supported for the
// current target" - so a clamp on one thread never short-circuits a clamp on another because nothing
// is shared at all.
static NSString *const CharonCIClampDepthKey = @"charon.ciimage.clampDepth";

static NSInteger CharonCIClampDepth(void)
{
    return [[[[NSThread currentThread] threadDictionary] objectForKey:CharonCIClampDepthKey] integerValue];
}

static void CharonSetCIClampDepth(NSInteger depth)
{
    [[[NSThread currentThread] threadDictionary] setObject:@(depth) forKey:CharonCIClampDepthKey];
}

// One clamp of the image to the rectangle, or the image itself when the ask is the framework's own
// and this thread is already inside the port's clamp.
static CIImage *CharonCIClamp(CIImage *image, CGRect rect)
{
    if (CharonCIClampDepth() > 0)
        return image;
    CharonSetCIClampDepth(CharonCIClampDepth() + 1);
    CIImage *clamped = image;
    if (!CGRectIsNull(rect) && !CGRectIsEmpty(rect)) {
        CIFilter *filter = [CIFilter filterWithName:@"CIAffineClamp"];
        [filter setValue:[image imageByCroppingToRect:rect] forKey:kCIInputImageKey];
        clamped = filter.outputImage ?: [image imageByCroppingToRect:rect];
    }
    CharonSetCIClampDepth(CharonCIClampDepth() - 1);
    return clamped;
}

- (CIImage *)imageByClampingToExtent
{
    return CharonCIClamp(self, self.extent);
}

- (CIImage *)imageByClampingToRect:(CGRect)rect
{
    return CharonCIClamp(self, rect);
}

- (CIImage *)imageByInsertingIntermediate
{
    return [self imageByInsertingIntermediate:NO];
}

- (CIImage *)imageByInsertingIntermediate:(BOOL)cache
{
    // What inserting an intermediate stage means is that the pixels are materialised rather than
    // passed through, and a colour matrix that is the identity does that with the release's own
    // filter: the same image, written out rather than handed on. The flag says whether the framework
    // keeps the result, and there is no cache here to keep it in, so both spellings give the same
    // image and the difference is named in facts/CoreImage/ImageAlgebra.md rather than pretended to.
    CIFilter *filter = [CIFilter filterWithName:@"CIColorMatrix"];
    [filter setValue:self forKey:kCIInputImageKey];
    [filter setValue:[CIVector vectorWithX:1 Y:0 Z:0 W:0] forKey:@"inputRVector"];
    [filter setValue:[CIVector vectorWithX:0 Y:1 Z:0 W:0] forKey:@"inputGVector"];
    [filter setValue:[CIVector vectorWithX:0 Y:0 Z:1 W:0] forKey:@"inputBVector"];
    [filter setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:1] forKey:@"inputAVector"];
    return filter.outputImage ?: self;
}

- (CIImage *)imageByPremultiplyingAlpha
{
    // Each colour channel scaled by the alpha: a colour matrix whose red, green and blue vectors are
    // the alpha with nothing else in them, and whose alpha vector leaves the alpha alone.
    CIFilter *filter = [CIFilter filterWithName:@"CIColorMatrix"];
    [filter setValue:self forKey:kCIInputImageKey];
    [filter setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:1] forKey:@"inputRVector"];
    [filter setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:1] forKey:@"inputGVector"];
    [filter setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:1] forKey:@"inputBVector"];
    [filter setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:1] forKey:@"inputAVector"];
    return filter.outputImage ?: self;
}

- (CIImage *)imageBySettingAlphaOneInExtent:(CGRect)rect
{
    // The image masked to that rectangle and the alpha of what is left set to one: a colour matrix
    // whose alpha vector is a one, over the image masked by a white field of the rectangle's size.
    CIImage *mask = [[[CIImage alloc] initWithColor:[[CIColor alloc] initWithRed:1 green:1 blue:1 alpha:1]]
        imageByCroppingToRect:rect];
    CIFilter *maskFilter = [CIFilter filterWithName:@"CIBlendWithMask"];
    [maskFilter setValue:self forKey:kCIInputImageKey];
    [maskFilter setValue:mask forKey:kCIInputMaskImageKey];
    CIFilter *alpha = [CIFilter filterWithName:@"CIColorMatrix"];
    [alpha setValue:maskFilter.outputImage forKey:kCIInputImageKey];
    [alpha setValue:[CIVector vectorWithX:1 Y:0 Z:0 W:0] forKey:@"inputRVector"];
    [alpha setValue:[CIVector vectorWithX:0 Y:1 Z:0 W:0] forKey:@"inputGVector"];
    [alpha setValue:[CIVector vectorWithX:0 Y:0 Z:1 W:0] forKey:@"inputBVector"];
    [alpha setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:0] forKey:@"inputAVector"];
    [alpha setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:1] forKey:@"inputBiasVector"];
    return alpha.outputImage ?: self;
}

- (CIImage *)imageByApplyingTransform:(CGAffineTransform)transform highQualityDownsample:(BOOL)highQualityDownsample
{
    if (!highQualityDownsample)
        return [self imageByApplyingTransform:transform];
    // A high quality downsample is a proper filter over the source rather than the renderer's point
    // sampling, and the release has a lanczos scale to make one with: the image is scaled by the
    // transform with the lanczos filter in front of the sampler, and the surface it covers is the
    // one the transform asks for.
    // A high quality downsample is a proper filter over the source rather than the renderer's point
    // sampling. The release's lanczos scale has three keys - the image, a scale and an aspect ratio -
    // and no translation, so the transform is taken apart: the uniform scale goes through the filter
    // and what is left of the transform is applied over the result. A key the filter does not have
    // raises rather than doing nothing, which is how the earlier version of this died.
    CGFloat scale = sqrtf(fabs(transform.a * transform.d - transform.b * transform.c));
    if (scale <= 0)
        return [self imageByApplyingTransform:transform];
    CIFilter *filter = [CIFilter filterWithName:@"CILanczosScaleTransform"];
    [filter setValue:self forKey:kCIInputImageKey];
    [filter setValue:@(scale) forKey:@"inputScale"];
    [filter setValue:@(1) forKey:@"inputAspectRatio"];
    CIImage *scaled = filter.outputImage;
    if (!scaled)
        return [self imageByApplyingTransform:transform];
    CGAffineTransform rest = CGAffineTransformMakeTranslation(transform.tx, transform.ty);
    return [scaled imageByApplyingTransform:rest];
}

// -imageBySettingProperties: is NOT here, and the reason is measured. The release exposes no way to
// set an image's properties: the header's `properties` is readonly and there is no setter, so the two
// implementations available are a touch of the private ivar behind it - a crutch - and a call back into
// this method to get a new image, which is a stack overflow (measured under -fsanitize=address). The
// row stays named in facts/CoreImage/ImageAlgebra.md.
//
// That makes three of this family - -imageByUnpremultiplyingAlpha, -imageBySettingProperties: and, on
// the host's own measure, the clamp methods - methods the framework itself calls on an image while it
// renders it, rather than conveniences a caller makes. Answering them from a category is a trap: the
// framework's own step is replaced and calls the port's, which calls the framework's.

@end

// The constant colour images: a field of that colour over the whole infinite extent, so a caller that
// composites over one gets that colour everywhere and not over nothing.
@implementation CIImage (CharonConstantColors)

- (CIImage *)charon_imageOfColor:(CIColor *)color
{
    return [[CIImage alloc] initWithColor:color];
}

+ (CIImage *)blackImage
{
    return [[CIImage alloc] initWithColor:[[CIColor alloc] initWithRed:0 green:0 blue:0 alpha:1]];
}

+ (CIImage *)whiteImage
{
    return [[CIImage alloc] initWithColor:[[CIColor alloc] initWithRed:1 green:1 blue:1 alpha:1]];
}

+ (CIImage *)grayImage
{
    return [[CIImage alloc] initWithColor:[[CIColor alloc] initWithRed:0.5 green:0.5 blue:0.5 alpha:1]];
}

+ (CIImage *)redImage
{
    return [[CIImage alloc] initWithColor:[[CIColor alloc] initWithRed:1 green:0 blue:0 alpha:1]];
}

+ (CIImage *)greenImage
{
    return [[CIImage alloc] initWithColor:[[CIColor alloc] initWithRed:0 green:1 blue:0 alpha:1]];
}

+ (CIImage *)blueImage
{
    return [[CIImage alloc] initWithColor:[[CIColor alloc] initWithRed:0 green:0 blue:1 alpha:1]];
}

+ (CIImage *)cyanImage
{
    return [[CIImage alloc] initWithColor:[[CIColor alloc] initWithRed:0 green:1 blue:1 alpha:1]];
}

+ (CIImage *)magentaImage
{
    return [[CIImage alloc] initWithColor:[[CIColor alloc] initWithRed:1 green:0 blue:1 alpha:1]];
}

+ (CIImage *)yellowImage
{
    return [[CIImage alloc] initWithColor:[[CIColor alloc] initWithRed:1 green:1 blue:0 alpha:1]];
}

+ (CIImage *)clearImage
{
    return [[CIImage alloc] initWithColor:[[CIColor alloc] initWithRed:0 green:0 blue:0 alpha:0]];
}

@end
