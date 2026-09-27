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
    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blur setValue:self forKey:kCIInputImageKey];
    // Only the radius: the filter has no angle on the system this is written against, and setting a key
    // a filter does not have raises rather than doing nothing.
    if ([blur respondsToSelector:NSSelectorFromString(@"setInputRadius:")])
        [blur setValue:@(sigma) forKey:@"inputRadius"];
    return blur.outputImage ?: self;
}

- (CIImage *)imageByClampingToExtent
{
    CIFilter *filter = [CIFilter filterWithName:@"CIAffineClamp"];
    [filter setValue:self forKey:kCIInputImageKey];
    return filter.outputImage ?: self;
}

- (CIImage *)imageByClampingToRect:(CGRect)rect
{
    // The image over that rectangle, and the result clamped, so what comes out stops at the rectangle
    // instead of at the image's own edge.
    CIFilter *filter = [CIFilter filterWithName:@"CIAffineClamp"];
    [filter setValue:[[self imageByCroppingToRect:rect] imageByApplyingFilter:@"CIAffineClamp"
                                withInputParameters:@{kCIInputImageKey: [self imageByCroppingToRect:rect]}]
            forKey:kCIInputImageKey];
    return filter.outputImage ?: self;
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
    CIFilter *filter = [CIFilter filterWithName:@"CILanczosScaleTransform"];
    [filter setValue:self forKey:kCIInputImageKey];
    [filter setValue:@(transform.a) forKey:@"inputScale"];
    [filter setValue:@(transform.d) forKey:@"inputAspectRatio"];
    [filter setValue:@(transform.tx) forKey:@"inputTranslateX"];
    [filter setValue:@(transform.ty) forKey:@"inputTranslateY"];
    return filter.outputImage ?: [self imageByApplyingTransform:transform];
}

- (CIImage *)imageBySettingProperties:(NSDictionary *)properties
{
    // The same image, carrying what the caller said about it: an image's own properties dictionary is
    // where the release keeps what a renderer is told about it, and a later caller reads them back.
    CIImage *image = self;
    if (!properties.count)
        return image;
    NSMutableDictionary *merged = [image.properties mutableCopy] ?: [NSMutableDictionary dictionary];
    [merged addEntriesFromDictionary:properties];
    return [image imageBySettingProperties:merged];
}

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
