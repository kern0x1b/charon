// MPSImagePyramid and the five kernels over it, from MPSImageConvolution.h of the iPhoneOS 16.4
// surface: a base class "for creating different kinds of pyramid images" (MPSImageConvolution.h:495)
// and the Gaussian, Laplacian, Laplacian-subtract and Laplacian-add pyramids.
//
// One object for one release: all six classes' own annotation above their @interface is ios(10.0) -
// MPSImageConvolution.h:119 (MPSImageLaplacian), :519 (:520 MPSImagePyramid), :612 (:613
// MPSImageGaussianPyramid), :663 (:664 MPSImageLaplacianPyramid), :683 (:684
// MPSImageLaplacianPyramidSubtract) and :706 (:707 MPSImageLaplacianPyramidAdd) - and nothing else is
// in this file. Their superclass MPSUnaryImageKernel is ios(9.0) and MPSUnaryImageKernel9.m carries it.
//
// THE FILTER, which all five share and which the header gives three ways.
//   the default (MPSImageConvolution.h:505-506)  "The filter kernel is the outer product of
//     w = [ 1/16,  1/4,  3/8,  1/4,  1/16 ]^T, with itself"
//   by a centre weight (:527-528)  "the outer product ww^T, where
//     w = [ (1/4 - a/2),  1/4,  a,  1/4,  (1/4 - a/2) ]^T"
//   or the caller's own (:548-552, row major, kernelWidth * kernelHeight values)
// The kernel must be odd in both directions (:562-569), and that is refused by name rather than
// answered with a filter the header does not describe.
//
// THE LEVEL SHAPE is the header's own (:508-514):
//     w_n = max(1, floor(w_0 / 2^n)),  h_n = max(1, floor(h_0 / 2^n))
//
// THE GAUSSIAN PYRAMID (:519-537 and :576-596) fills every mipmap level after level 0, in place:
//     mip[n+1] = Downsample( filter( mip[n] ) )
// where Downsample "removes odd rows and columns from the input image" (:582-583) - which is to say
// level n+1's pixel (x, y) is the filtered level n at (2x, 2y). The header says the pyramid "ignores
// clipRect and offset and fills the entire mipmap levels" (:506-508), so nothing here reads either.
//
// THE LAPLACIAN PYRAMID (:612-660) is the difference against an interpolated half-resolution level:
//     LaplacianMipLevel[l] := GaussianMipLevel[l] - Interpolate(GaussianMipLevel[l+1])
// where Interpolate is "the classical 2x signal interpolation procedure" (:619-620), which the header
// then spells out as exactly two steps (:622-633): zero-stuffing, "dst.at(x, y) := src.at(x, y) if
// even(x) and even(y) else 0", and then filtering with this file's own kernel. So the interpolation
// here is a five-by-five filter over the zero-stuffed source, and a tap that lands on an odd position
// reads the zero of the zero-stuffing - which is also what settles the border, and it is why no edge
// mode is read here and none is asked for.
//
// The result is then mapped pointwise (:645-649): LaplacianRangeScale(p, bias, scale) = bias + p*scale,
// defaults bias 0.0 and scale 1.0. The subtract kernel (:683-704) writes it into every destination level
// from the bottom up, one fewer level than the source has; the add kernel (:706-729) inverts that
// mapping and adds the interpolated level back, walking down from the top and taking the level above
// the first iteration from the source, which the header calls "the LaplacianMipLevel[#top] level"
// (:722-725).
//
// WHAT IS NOT CLAIMED. No number in this file is a measurement of Apple's code - the release's own MPS
// cannot run on this host, which facts/MetalPerformanceShaders/Image9.md records. What is written here
// is transcribed from the header above; what has been checked is the armv7 link, that this object
// defines the six classes it says.

#import "CharonMPSImage.h"

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"
// MPSImageConvolution.h marks -initWithDevice:kernelWidth:kernelHeight:weights: the designated
// initializer of MPSImagePyramid (:578 area) and -initWithCoder:device: another, and this class refuses
// the coder form because the release's keys for a filter are in no header, so it cannot chain to a
// designated initializer of its own. The same pragma MPSImage9.m carries for the same reason.
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

// The filter's own three values, which the categories below need. They are MPSImagePyramid's PRIVATE
// ivars - declared in its @implementation, and a subclass's category cannot see them, which the compiler
// says outright ("instance variable '_kernel' is private") - so the class publishes them under names no
// SDK header declares, and the two categories read those. This is the same arrangement as
// MPSCNNKernel10.m's charon_mps_setWindowWidth:, which exists because the convolution and the pooling
// file both read it.
@interface MPSImagePyramid (CharonMPSImagePyramidFilter)
- (const float *)charon_mps_filter;
- (NSUInteger)charon_mps_filterWidth;
- (NSUInteger)charon_mps_filterHeight;
@end

// The shape of the twelve pixel formats MPSImage's own mapping produces (MPSImage13.m:50-73). The
// channel format back from a pixel format is MPSImage13.m's own function, and it is not called here: it
// is defined in MPSImage13.m, which is not an object every band keeps - a band whose release exports
// MPSImage links the release's class and drops that file - so a call to it would be an undefined symbol
// in exactly the bands this object is kept for. This table is this file's own and answers the one
// question these kernels ask of a texture, which is how wide a pixel is.
static BOOL CharonMPSPyramidPixelShape(MTLPixelFormat pixel, NSUInteger *channels, size_t *elementSize)
{
    size_t element;
    NSUInteger count;
    switch (pixel) {
    case MTLPixelFormatR8Unorm:    element = 1; count = 1; break;
    case MTLPixelFormatRG8Unorm:   element = 1; count = 2; break;
    case MTLPixelFormatRGBA8Unorm: element = 1; count = 4; break;
    case MTLPixelFormatR16Unorm:   element = 2; count = 1; break;
    case MTLPixelFormatRG16Unorm:  element = 2; count = 2; break;
    case MTLPixelFormatRGBA16Unorm:element = 2; count = 4; break;
    case MTLPixelFormatR16Float:   element = 2; count = 1; break;
    case MTLPixelFormatRG16Float:  element = 2; count = 2; break;
    case MTLPixelFormatRGBA16Float:element = 2; count = 4; break;
    case MTLPixelFormatR32Float:   element = 4; count = 1; break;
    case MTLPixelFormatRG32Float:  element = 4; count = 2; break;
    case MTLPixelFormatRGBA32Float:element = 4; count = 4; break;
    default: return NO;
    }
    if (channels)
        *channels = count;
    if (elementSize)
        *elementSize = element;
    return YES;
}

// max(1, floor(base / 2^level)), MPSImageConvolution.h:510-511.
static NSUInteger CharonMPSPyramidExtent(NSUInteger base, NSUInteger level)
{
    NSUInteger extent = base >> level;
    return extent ? extent : 1;
}

// A level of a texture, read into or written from a buffer of its own shape. The texture's own read and
// write are the ones every other MPSImage kernel uses (CharonMPSImageReadRegion and
// CharonMPSImageWriteRegion, which go through -readBytes: and -writeBytes: on an MPSImage); a pyramid
// is given a TEXTURE and works on its MIP LEVELS, which no MPSImage of this port wraps, so the texture's
// own -getBytes:...-mipmapLevel: and -replaceRegion:...-mipmapLevel: are used directly here.
static BOOL CharonMPSPyramidRead(id<MTLTexture> texture, NSUInteger level, NSUInteger width, NSUInteger height,
                                 NSUInteger channels, size_t elementSize, void *buffer)
{
    size_t stride = width * channels * elementSize;
    if (level >= texture.mipmapLevelCount)
        return NO;
    [texture getBytes:buffer bytesPerRow:stride fromRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:level];
    return YES;
}

static BOOL CharonMPSPyramidWrite(id<MTLTexture> texture, NSUInteger level, NSUInteger width, NSUInteger height,
                                  NSUInteger channels, size_t elementSize, const void *buffer)
{
    size_t stride = width * channels * elementSize;
    if (level >= texture.mipmapLevelCount)
        return NO;
    [texture replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:level withBytes:buffer bytesPerRow:stride];
    return YES;
}

// The value of the kernel's own filter at (x, y) of a level: the taps read the source, clamped at the
// border, which is the ordinary edge rule for a blur. The kernel is stored row major over
// kernelWidth * kernelHeight, so the tap at (kx, ky) weighs kernel[ky * kernelWidth + kx].
static double CharonMPSPyramidFiltered(const float *source, NSUInteger width, NSUInteger height,
                                       NSUInteger channel, NSUInteger channels,
                                       NSUInteger x, NSUInteger y,
                                       const float *kernel, NSUInteger kernelWidth, NSUInteger kernelHeight)
{
    NSUInteger halfWidth = kernelWidth / 2, halfHeight = kernelHeight / 2;
    double total = 0.0;
    for (NSUInteger ky = 0; ky < kernelHeight; ky++) {
        long sy = (long)y + (long)ky - (long)halfHeight;
        sy = sy < 0 ? 0 : ((NSUInteger)sy >= height ? (long)height - 1 : sy);
        for (NSUInteger kx = 0; kx < kernelWidth; kx++) {
            long sx = (long)x + (long)kx - (long)halfWidth;
            sx = sx < 0 ? 0 : ((NSUInteger)sx >= width ? (long)width - 1 : sx);
            double sample = (double)source[((NSUInteger)sy * width + (NSUInteger)sx) * channels + channel];
            total += (double)kernel[ky * kernelWidth + kx] * sample;
        }
    }
    return total;
}

// The interpolation, which is the same filter over the ZERO-STUFFED source: at (x, y) the sample a tap
// reads is the source's own at (p / 2, q / 2) when the tap's own position (p, q) is even in both
// directions, and zero otherwise. That is MPSImageConvolution.h:625-626 verbatim, and it is what makes
// the border answer without an edge rule of any kind.
static double CharonMPSPyramidInterpolated(const float *source, NSUInteger width, NSUInteger height,
                                           NSUInteger channel, NSUInteger channels,
                                           NSUInteger x, NSUInteger y,
                                           const float *kernel, NSUInteger kernelWidth, NSUInteger kernelHeight)
{
    NSUInteger halfWidth = kernelWidth / 2, halfHeight = kernelHeight / 2;
    double total = 0.0;
    for (NSUInteger ky = 0; ky < kernelHeight; ky++) {
        long py = (long)y + (long)ky - (long)halfHeight;
        for (NSUInteger kx = 0; kx < kernelWidth; kx++) {
            long px = (long)x + (long)kx - (long)halfWidth;
            if ((py & 1) || (px & 1))
                continue;
            long sx = px / 2, sy = py / 2;
            if (sx < 0 || sy < 0 || (NSUInteger)sx >= width || (NSUInteger)sy >= height)
                continue;
            double sample = (double)source[((NSUInteger)sy * width + (NSUInteger)sx) * channels + channel];
            total += (double)kernel[ky * kernelWidth + kx] * sample;
        }
    }
    return total;
}

@implementation MPSImagePyramid {
    NSMutableData *_kernel;      // the filter's own weights, row major, kernelWidth * kernelHeight of them
    NSUInteger _kernelWidth, _kernelHeight;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device kernelWidth:(NSUInteger)kernelWidth kernelHeight:(NSUInteger)kernelHeight weights:(const float *)kernelWeights
{
    if (!(self = [super initWithDevice:device]))
        return nil;
    if (!kernelWidth || !kernelHeight || !kernelWeights ||
        (kernelWidth % 2) == 0 || (kernelHeight % 2) == 0) {
        CharonMPSRefuse(@"MPSImagePyramid: a %lu by %lu kernel with weights %s is refused;"
                        @" MPSImageConvolution.h:562-569 says the width and the height must be odd",
                        (unsigned long)kernelWidth, (unsigned long)kernelHeight,
                        kernelWeights ? "given" : "not given");
        return nil;
    }
    _kernelWidth = kernelWidth;
    _kernelHeight = kernelHeight;
    _kernel = [NSMutableData dataWithLength:kernelWidth * kernelHeight * sizeof(float)];
    if (!_kernel) {
        CharonMPSRefuse(@"MPSImagePyramid: no memory for a %lux%lu kernel, so no object was made",
                        (unsigned long)kernelWidth, (unsigned long)kernelHeight);
        return nil;
    }
    [_kernel replaceBytesInRange:NSMakeRange(0, kernelWidth * kernelHeight * sizeof(float)) withBytes:kernelWeights];
    return self;
}

// The default filter of :505-506, w = [ 1/16, 1/4, 3/8, 1/4, 1/16 ]^T as the outer product ww^T.
- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    float w[5] = { 1.0f / 16.0f, 1.0f / 4.0f, 3.0f / 8.0f, 1.0f / 4.0f, 1.0f / 16.0f };
    float kernel[25];
    for (NSUInteger ky = 0; ky < 5; ky++)
        for (NSUInteger kx = 0; kx < 5; kx++)
            kernel[ky * 5 + kx] = w[ky] * w[kx];
    return [self initWithDevice:device kernelWidth:5 kernelHeight:5 weights:kernel];
}

// The centre weight of :527-528: w = [ (1/4 - a/2), 1/4, a, 1/4, (1/4 - a/2) ]^T as the outer product.
- (instancetype)initWithDevice:(id<MTLDevice>)device centerWeight:(float)centerWeight
{
    float edge = 1.0f / 4.0f - centerWeight / 2.0f;
    float w[5] = { edge, 1.0f / 4.0f, centerWeight, 1.0f / 4.0f, edge };
    float kernel[25];
    for (NSUInteger ky = 0; ky < 5; ky++)
        for (NSUInteger kx = 0; kx < 5; kx++)
            kernel[ky * 5 + kx] = w[ky] * w[kx];
    return [self initWithDevice:device kernelWidth:5 kernelHeight:5 weights:kernel];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    // For the reason MPSImageConvolution13.m gives for its own: the release's keys for a kernel's filter
    // are in no header, so an invented key would read an archive the release never wrote. Not recorded
    // as round-tripping; the initializers above are the way to make one.
    (void)aDecoder;
    (void)device;
    CharonMPSRefuse(@"MPSImagePyramid: -initWithCoder:device: is not carried - the release's keys for a"
                    @" pyramid's filter are in no header, so a decoder cannot rebuild them honestly");
    return nil;
}

- (NSUInteger)kernelWidth { return _kernelWidth; }
- (NSUInteger)kernelHeight { return _kernelHeight; }

- (const float *)charon_mps_filter { return (const float *)[_kernel bytes]; }
- (NSUInteger)charon_mps_filterWidth { return _kernelWidth; }
- (NSUInteger)charon_mps_filterHeight { return _kernelHeight; }

@end

// MPSImageGaussianPyramid, the class the header says is "currently supported" under MPSImagePyramid
// (:497-498), carries no member of its own: MPSImageConvolution.h:613 ends at @end. The encode is put
// on MPSImagePyramid, in a CATEGORY, and that is the arrangement the header requires and not a
// preference: "the user must run the operation in-place using
// MPSUnaryImageKernel::encodeToCommandBuffer:inPlaceTexture:fallbackCopyAllocator:"
// (MPSImageConvolution.h:592-594), and MPSUnaryImageKernel9.m answers that selector by refusing,
// because the in-place form needs MPSCopyAllocator semantics. A subclass's own implementation is found
// before its superclass's, so the pyramid's in-place walk is this category's and the refusal above it
// is what every other MPSUnaryImageKernel still gets.
@interface MPSImageGaussianPyramid (CharonMPSGaussianPyramid)
- (BOOL)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                 inPlaceTexture:(id<MTLTexture>)texture
       fallbackCopyAllocator:(MPSCopyAllocator)copyAllocator;
@end

@implementation MPSImageGaussianPyramid (CharonMPSGaussianPyramid)

- (BOOL)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                 inPlaceTexture:(id<MTLTexture>)texture
       fallbackCopyAllocator:(MPSCopyAllocator)copyAllocator
{
    // "The fallbackCopyAllocator parameter is not used" (MPSImageConvolution.h:595), because the work
    // is in place: every level of the texture is both read and written, which is what makes this the
    // form the header insists on.
    (void)copyAllocator;
    NSString *what = @"MPSImageGaussianPyramid";
    if (!commandBuffer) {
        CharonMPSRefuse(@"%@: no command buffer, so no level was written", what);
        return NO;
    }
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return NO;
    if (!texture) {
        CharonMPSRefuse(@"%@: no texture, so no level was written", what);
        return NO;
    }
    NSUInteger channels = 0;
    size_t elementSize = 0;
    if (!CharonMPSPyramidPixelShape(texture.pixelFormat, &channels, &elementSize) || !channels || !elementSize) {
        CharonMPSRefuse(@"%@: a texture of pixel format %d names no element width this port carries, so no"
                        @" level was written", what, (int)texture.pixelFormat);
        return NO;
    }
    const float *kernel = [self charon_mps_filter];
    NSUInteger kernelWidth = [self charon_mps_filterWidth];
    NSUInteger kernelHeight = [self charon_mps_filterHeight];
    NSUInteger levels = texture.mipmapLevelCount;
    if (levels < 2) {
        CharonMPSRefuse(@"%@: the texture has %lu mip level(s) and a pyramid writes every level after the"
                        @" first, so there was nothing to do", what, (unsigned long)levels);
        return NO;
    }
    NSUInteger baseWidth = texture.width, baseHeight = texture.height;
    for (NSUInteger level = 1; level < levels; level++) {
        NSUInteger sourceWidth = CharonMPSPyramidExtent(baseWidth, level - 1);
        NSUInteger sourceHeight = CharonMPSPyramidExtent(baseHeight, level - 1);
        NSUInteger width = CharonMPSPyramidExtent(baseWidth, level);
        NSUInteger height = CharonMPSPyramidExtent(baseHeight, level);
        size_t sourceBytes = (size_t)sourceWidth * sourceHeight * channels * elementSize;
        size_t bytes = (size_t)width * height * channels * elementSize;
        float *source = (float *)calloc(sourceBytes ? sourceBytes : 1, 1);
        float *answer = (float *)calloc(bytes ? bytes : 1, 1);
        if (!source || !answer) {
            free(source);
            free(answer);
            CharonMPSRefuse(@"%@: no memory for level %lu, so no level was written", what, (unsigned long)level);
            return NO;
        }
        if (!CharonMPSPyramidRead(texture, level - 1, sourceWidth, sourceHeight, channels, elementSize, source)) {
            free(source);
            free(answer);
            CharonMPSRefuse(@"%@: level %lu could not be read, so the pyramid stopped there", what,
                            (unsigned long)(level - 1));
            return NO;
        }
        // Downsample: this level's pixel (x, y) is the filtered level above at (2x, 2y) - "Downsample()
        // removes odd rows and columns from the input image" (MPSImageConvolution.h:582-583).
        for (NSUInteger y = 0; y < height; y++) {
            for (NSUInteger x = 0; x < width; x++) {
                NSUInteger at = 2 * x, over = 2 * y;
                if (at >= sourceWidth)
                    at = sourceWidth ? sourceWidth - 1 : 0;
                if (over >= sourceHeight)
                    over = sourceHeight ? sourceHeight - 1 : 0;
                for (NSUInteger channel = 0; channel < channels; channel++) {
                    double value = CharonMPSPyramidFiltered(source, sourceWidth, sourceHeight, channel, channels,
                                                            at, over, kernel, kernelWidth, kernelHeight);
                    answer[(y * width + x) * channels + channel] = (float)value;
                }
            }
        }
        BOOL written = CharonMPSPyramidWrite(texture, level, width, height, channels, elementSize, answer);
        free(source);
        free(answer);
        if (!written) {
            CharonMPSRefuse(@"%@: level %lu could not be written, so the pyramid stopped there", what,
                            (unsigned long)level);
            return NO;
        }
    }
    return YES;
}

@end

// The three Laplacian levels: the base with its two pointwise parameters, and the subtract and add
// kernels over it. The base carries no encode - MPSImageConvolution.h:664 declares none - and the two
// kernels declare none either (:684, :707), so both walk is a category on this class, for the same
// reason as the Gaussian one above.
@implementation MPSImageLaplacianPyramid {
    float _laplacianBias, _laplacianScale;
}

- (float)getLaplacianBias { return _laplacianBias; }

// The header spells this property's accessors out (:667): "setter = setLaplacianBias:, getter =
// getLaplacianBias", so the two are written by name and not the ones @synthesize would make.
- (void)setLaplacianBias:(float)laplacianBias { _laplacianBias = laplacianBias; }
- (float)getLaplacianScale { return _laplacianScale; }
- (void)setLaplacianScale:(float)laplacianScale { _laplacianScale = laplacianScale; }

@end

// The class itself first: MPSImageConvolution.h:684 declares no member on it, so it has nothing of its
// own to write, and a category cannot create the class it is written on - which is the same arrangement
// MPSImageThreshold13.m and MPSImageArithmetic13.m already use in this package.
@implementation MPSImageLaplacianPyramidSubtract
@end

@interface MPSImageLaplacianPyramidSubtract (CharonMPSLaplacianPyramid)
- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                sourceTexture:(id<MTLTexture>)sourceTexture
           destinationTexture:(id<MTLTexture>)destinationTexture;
@end

@implementation MPSImageLaplacianPyramidSubtract (CharonMPSLaplacianPyramid)

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                sourceTexture:(id<MTLTexture>)sourceTexture
           destinationTexture:(id<MTLTexture>)destinationTexture
{
    NSString *what = @"MPSImageLaplacianPyramid";
    if (!commandBuffer) {
        CharonMPSRefuse(@"%@: no command buffer, so no level was written", what);
        return;
    }
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    if (!sourceTexture || !destinationTexture) {
        CharonMPSRefuse(@"%@: no source or no destination texture, so no level was written", what);
        return;
    }
    // Limitation 2 of :655-658: "The number of channels, bit depth and resolution of the source and
    // destination textures need to match."
    NSUInteger channels = 0, destinationChannels = 0;
    size_t elementSize = 0, destinationElementSize = 0;
    if (!CharonMPSPyramidPixelShape(sourceTexture.pixelFormat, &channels, &elementSize) ||
        !CharonMPSPyramidPixelShape(destinationTexture.pixelFormat, &destinationChannels, &destinationElementSize) ||
        channels != destinationChannels || elementSize != destinationElementSize) {
        CharonMPSRefuse(@"%@: the source is pixel format %d and the destination %d; MPSImageConvolution.h:657"
                        @" says their channels, bit depth and resolution have to match, so no level was written",
                        what, (int)sourceTexture.pixelFormat, (int)destinationTexture.pixelFormat);
        return;
    }
    // The subtract kernel writes one level fewer than the source has (:695-699), and limitation 1 of
    // :654-655 is that in-place is not supported, which is the plain two-texture form used here.
    NSUInteger levels = sourceTexture.mipmapLevelCount;
    if (destinationTexture.mipmapLevelCount < levels) {
        CharonMPSRefuse(@"%@: the destination has %lu mip level(s) and the source %lu; MPSImageConvolution.h:695"
                        @" says the destination needs at least one fewer than the source, so no level was written",
                        what, (unsigned long)destinationTexture.mipmapLevelCount, (unsigned long)levels);
        return;
    }
    const float *kernel = [self charon_mps_filter];
    NSUInteger kernelWidth = [self charon_mps_filterWidth];
    NSUInteger kernelHeight = [self charon_mps_filterHeight];
    // The two pointwise parameters through the getters the header spells out at MPSImageConvolution.h:667 -
    // getLaplacianBias and getLaplacianScale - which are public and so visible from a category, where
    // the ivars behind them are not.
    double laplacianBias = [self getLaplacianBias];
    double laplacianScale = [self getLaplacianScale];
    for (NSUInteger level = 0; level + 1 < levels; level++) {
        NSUInteger width = CharonMPSPyramidExtent(sourceTexture.width, level);
        NSUInteger height = CharonMPSPyramidExtent(sourceTexture.height, level);
        NSUInteger aboveWidth = CharonMPSPyramidExtent(sourceTexture.width, level + 1);
        NSUInteger aboveHeight = CharonMPSPyramidExtent(sourceTexture.height, level + 1);
        size_t bytes = (size_t)width * height * channels * elementSize;
        size_t aboveBytes = (size_t)aboveWidth * aboveHeight * channels * elementSize;
        float *here = (float *)calloc(bytes ? bytes : 1, 1);
        float *above = (float *)calloc(aboveBytes ? aboveBytes : 1, 1);
        if (!here || !above) {
            free(here);
            free(above);
            CharonMPSRefuse(@"%@: no memory for level %lu, so no level was written", what, (unsigned long)level);
            return;
        }
        BOOL read = CharonMPSPyramidRead(sourceTexture, level, width, height, channels, elementSize, here) &&
                    CharonMPSPyramidRead(sourceTexture, level + 1, aboveWidth, aboveHeight, channels, elementSize, above);
        if (!read) {
            free(here);
            free(above);
            CharonMPSRefuse(@"%@: level %lu of the source could not be read, so no level was written", what,
                            (unsigned long)level);
            return;
        }
        for (NSUInteger y = 0; y < height; y++) {
            for (NSUInteger x = 0; x < width; x++) {
                for (NSUInteger channel = 0; channel < channels; channel++) {
                    double raw = (double)here[(y * width + x) * channels + channel] -
                                 CharonMPSPyramidInterpolated(above, aboveWidth, aboveHeight, channel, channels,
                                                             x, y, kernel, kernelWidth, kernelHeight);
                    // LaplacianRangeScale(pixel, bias, scale) := bias + pixel * scale (:647-648).
                    double value = laplacianBias + raw * laplacianScale;
                    here[(y * width + x) * channels + channel] = (float)value;
                }
            }
        }
        CharonMPSPyramidWrite(destinationTexture, level, width, height, channels, elementSize, here);
        free(here);
        free(above);
    }
}

@end

// The add kernel is the inverse of the above and is a second category on the same class, because it is
// a different class with its own encode and the release keeps them as two (:684 and :707).
// The add kernel's class, for the same reason as the subtract one above: MPSImageConvolution.h:707
// declares no member on it either.
@implementation MPSImageLaplacianPyramidAdd
@end

@implementation MPSImageLaplacianPyramidAdd (CharonMPSLaplacianPyramid)

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                sourceTexture:(id<MTLTexture>)sourceTexture
           destinationTexture:(id<MTLTexture>)destinationTexture
{
    NSString *what = @"MPSImageLaplacianPyramidAdd";
    if (!commandBuffer) {
        CharonMPSRefuse(@"%@: no command buffer, so no level was written", what);
        return;
    }
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    if (!sourceTexture || !destinationTexture) {
        CharonMPSRefuse(@"%@: no source or no destination texture, so no level was written", what);
        return;
    }
    NSUInteger channels = 0, destinationChannels = 0;
    size_t elementSize = 0, destinationElementSize = 0;
    if (!CharonMPSPyramidPixelShape(sourceTexture.pixelFormat, &channels, &elementSize) ||
        !CharonMPSPyramidPixelShape(destinationTexture.pixelFormat, &destinationChannels, &destinationElementSize) ||
        channels != destinationChannels || elementSize != destinationElementSize) {
        CharonMPSRefuse(@"%@: the source is pixel format %d and the destination %d; MPSImageConvolution.h:657"
                        @" says their channels, bit depth and resolution have to match, so no level was written",
                        what, (int)sourceTexture.pixelFormat, (int)destinationTexture.pixelFormat);
        return;
    }
    NSUInteger levels = sourceTexture.mipmapLevelCount;
    if (destinationTexture.mipmapLevelCount < levels) {
        CharonMPSRefuse(@"%@: the destination has %lu mip level(s) and the source %lu; MPSImageConvolution.h:695"
                        @" says the destination needs at least one fewer than the source, so no level was written",
                        what, (unsigned long)destinationTexture.mipmapLevelCount, (unsigned long)levels);
        return;
    }
    const float *kernel = [self charon_mps_filter];
    NSUInteger kernelWidth = [self charon_mps_filterWidth];
    NSUInteger kernelHeight = [self charon_mps_filterHeight];
    double laplacianBias = [self getLaplacianBias];
    double laplacianScale = [self getLaplacianScale];
    // One level of the answer at a time, from the top down (:713-719). The level ABOVE the first one is
    // not the destination's own - it has not been reconstructed yet - and comes from the source's top
    // level instead, which the header names "the LaplacianMipLevel[#top] level" (:722-725). It is read
    // once, before the walk, and it is the only level read from the source above.
    NSUInteger topWidth = CharonMPSPyramidExtent(sourceTexture.width, levels - 1);
    NSUInteger topHeight = CharonMPSPyramidExtent(sourceTexture.height, levels - 1);
    size_t topBytes = (size_t)topWidth * topHeight * channels * elementSize;
    float *top = (float *)calloc(topBytes ? topBytes : 1, 1);
    if (!top) {
        CharonMPSRefuse(@"%@: no memory for the top level, so no level was written", what);
        return;
    }
    if (!CharonMPSPyramidRead(sourceTexture, levels - 1, topWidth, topHeight, channels, elementSize, top)) {
        free(top);
        CharonMPSRefuse(@"%@: the top level of the source could not be read, so no level was written", what);
        return;
    }
    for (long step = (long)levels - 2; step >= 0; step--) {
        NSUInteger level = (NSUInteger)step;
        NSUInteger width = CharonMPSPyramidExtent(sourceTexture.width, level);
        NSUInteger height = CharonMPSPyramidExtent(sourceTexture.height, level);
        size_t bytes = (size_t)width * height * channels * elementSize;
        float *here = (float *)calloc(bytes ? bytes : 1, 1);
        if (!here) {
            free(top);
            CharonMPSRefuse(@"%@: no memory for level %lu, so no level was written", what, (unsigned long)level);
            return;
        }
        if (!CharonMPSPyramidRead(sourceTexture, level, width, height, channels, elementSize, here)) {
            free(here);
            free(top);
            CharonMPSRefuse(@"%@: level %lu of the source could not be read, so no level was written", what,
                            (unsigned long)level);
            return;
        }
        // The level above: the destination's own, already reconstructed, except at the top where it is
        // the source's own - the one read above.
        BOOL destinationHasAbove = destinationTexture.mipmapLevelCount > level + 1;
        NSUInteger aboveWidth = CharonMPSPyramidExtent(sourceTexture.width, level + 1);
        NSUInteger aboveHeight = CharonMPSPyramidExtent(sourceTexture.height, level + 1);
        size_t aboveBytes = (size_t)aboveWidth * aboveHeight * channels * elementSize;
        float *above = (float *)calloc(aboveBytes ? aboveBytes : 1, 1);
        if (!above || !(level + 1 == levels - 1
                        ? YES
                        : (destinationHasAbove
                           ? CharonMPSPyramidRead(destinationTexture, level + 1, aboveWidth, aboveHeight,
                                                    channels, elementSize, above)
                           : NO))) {
            free(here);
            free(above);
            free(top);
            CharonMPSRefuse(@"%@: level %lu above could not be read, so no level was written", what,
                            (unsigned long)(level + 1));
            return;
        }
        // AboveBytes is topBytes for the one iteration that uses `top`, and the two hold the same level's
        // values; the copy is what keeps one loop below.
        const float *aboveValues = (level + 1 == levels - 1) ? top : above;
        for (NSUInteger y = 0; y < height; y++) {
            for (NSUInteger x = 0; x < width; x++) {
                for (NSUInteger channel = 0; channel < channels; channel++) {
                    // LaplacianRangeScale^-1(stored, bias, scale) = (stored - bias) / scale, then the
                    // interpolated level above is added (:719). A scale of zero has no inverse; the value
                    // is then left as the stored one rather than divided by nothing.
                    double stored = (double)here[(y * width + x) * channels + channel];
                    double raw = laplacianScale != 0.0 ? (stored - laplacianBias) / laplacianScale : stored;
                    double value = raw + CharonMPSPyramidInterpolated(aboveValues, aboveWidth, aboveHeight,
                                                                       channel, channels, x, y,
                                                                       kernel, kernelWidth, kernelHeight);
                    here[(y * width + x) * channels + channel] = (float)value;
                }
            }
        }
        CharonMPSPyramidWrite(destinationTexture, level, width, height, channels, elementSize, here);
        free(here);
        free(above);
    }
    free(top);
}

@end

