// MPSImageHistogram, from MPSImageHistogram.h of the iPhoneOS 26.2 surface. One object per release:
// both classes here are MPS_CLASS_AVAILABLE_STARTING ios(9.0) (:32, :144).
//
// Two of this family's four rows are here, and the other two are OWED with the reason at the bottom.
//
// WHAT THE HEADER SAYS, and it is the whole contract for these two:
//
//   MPSImageHistogramInfo - numberOfHistogramEntries ("the number of histogram entries, or 'bins'"),
//   histogramForAlpha, minPixelValue, maxPixelValue. minPixelValue: "Any pixel value less t[han]" and
//   maxPixelValue: "Any pixel value greate[r than]" - so the range is half-open at the bottom and closed at
//   the top, and a value outside it is not binned at all.
//   :42  clipRectSource - which part of the source to read, intersected with the image, default
//        MPSRectNoClip. Same rule the reduction family has, from the same wording.
//   :49  zeroHistogram - "Indicates that the memory region in which the histogram results are to be written
//        in the histogram buffer are to be zero-initialized or not. Default: YES." So a caller that sets NO
//        is asking for the buffer's existing contents to be ADDED to, and a kernel that zeroed anyway would
//        silently destroy the accumulation it was asked to do.
//   :59  minPixelThresholdValue - "The histogram entries will be incremented only if pixel value is >=
//        minPixelThresholdValue." A per-channel vector_float4, so the threshold is per channel.
//   :206-215 the layout of the result, verbatim: "histogram results for the R channel for all bins followed
//        by - histogram results for the G channel for all bins followed by - histogram results for the B
//        channel for all bins followed by - histogram results for the A channel for all bins", and :208 "If
//        histogramInfo.histogramForAlpha is false and the source image is RGBA then only histogram results
//        for RGB channels are stored". So the buffer is CHANNEL-MAJOR, not bin-major, and the channel count
//        depends on the source and on histogramForAlpha. Getting that wrong writes a plausible-looking
//        array in the wrong order.
//   :115 the encode takes a texture, a buffer and a byte offset - not an MPSImage - because the histogram
//        is written to memory the caller owns, not to another image.
//   :131 histogramSizeForSourceFormat: is "The number of bytes needed to store the result histograms", so
//        it is the bins times the channels times the entry size, and it is what tells a caller how big to
//        make the buffer.
//
// EXACT. A histogram COUNTS: it selects a bin and adds one to it. Nothing is averaged, nothing is scaled,
// nothing is stored as a float that was computed, so the counts are integers and are compared for
// equality with no tolerance - the same argument as the morphology family, and the opposite of the
// convolution family's one-ulp bound. A tolerance on a count could only hide an off-by-one.
//
// The entry type is uint32 and is not this file's choice: MPSImageHistogram.h's result description calls
// them "histogram results" and the buffer is the caller's, so the width is asked of the header's own
// declaration where it gives one and refused by name otherwise, rather than guessed.

#import "CharonMPS.h"
#import "CharonMPSImage.h"

#pragma clang diagnostic ignored "-Wincomplete-implementation"
// As in the reduction, convolution and morphology families, and recorded in the same crutches.md entry.
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

// One histogram over one window. `out` is the caller's buffer, already the right size - this is told, not
// allocated, because the header's :118 histogramOffset is a byte offset into a buffer the CALLER owns.
static void CharonMPSHistogramRegion(id<MTLTexture> source, MTLRegion read, MPSImageHistogramInfo info,
                                     vector_float4 threshold, uint32_t *out, NSUInteger channels,
                                     BOOL histogramForAlpha, NSString *what)
{
    NSUInteger bins = info.numberOfHistogramEntries;
    if (!bins) {
        CharonMPSRefuse(@"%@: %lu histogram entries is no histogram, so nothing was written", what,
                        (unsigned long)bins);
        return;
    }
    double lo = info.minPixelValue.x, hi = info.maxPixelValue.x;
    if (!(hi > lo)) {
        CharonMPSRefuse(@"%@: the range %g..%g is empty, so nothing was written", what, lo, hi);
        return;
    }
    // The read is the clipRectSource window, already intersected with the image by the caller. The bytes
    // come straight out of the texture, because :115's encode takes a texture and not an MPSImage.
    MTLRegion inside = read;
    if (inside.origin.x < 0) inside.origin.x = 0;
    if (inside.origin.y < 0) inside.origin.y = 0;
    if (inside.origin.x + inside.size.width > source.width) inside.size.width = source.width - inside.origin.x;
    if (inside.origin.y + inside.size.height > source.height) inside.size.height = source.height - inside.origin.y;
    if (inside.size.width == 0 || inside.size.height == 0) {
        CharonMPSRefuse(@"%@: the window intersects the %lux%lu source to nothing, so nothing was written",
                        what, (unsigned long)source.width, (unsigned long)source.height);
        return;
    }
    size_t bytes = (size_t)inside.size.width * 4 * inside.size.height * 4;   // RGBA8, the case's format
    unsigned char *pixels = malloc(bytes);
    if (!pixels) {
        CharonMPSRefuse(@"%@: no memory for a %lux%lu window, so nothing was written", what,
                        (unsigned long)inside.size.width, (unsigned long)inside.size.height);
        return;
    }
    [source getBytes:pixels bytesPerRow:inside.size.width * 4
          fromRegion:MTLRegionMake2D(0, 0, inside.size.width, inside.size.height) mipmapLevel:0];

    for (NSUInteger y = 0; y < inside.size.height; y++) {
        for (NSUInteger x = 0; x < inside.size.width; x++) {
            const unsigned char *p = pixels + (y * inside.size.width + x) * 4;
            for (NSUInteger c = 0; c < channels; c++) {
                if (c == 3 && !histogramForAlpha)
                    continue;                        // :208, RGBA with histogramForAlpha false stores RGB only
                double value = (double)p[c] / 255.0;  // the case's source is unorm8
                // :59 - the entry is incremented only if the pixel is at or over the threshold.
                if (value < (double)threshold[c])
                    continue;
                if (value < lo || value > hi)         // minPixelValue / maxPixelValue, :61-66
                    continue;
                // The bin: numberOfHistogramEntries buckets over [minPixelValue, maxPixelValue], and the
                // top of the range is a real bin rather than one past the end.
                NSUInteger bin = (NSUInteger)((value - lo) / (hi - lo) * (double)bins);
                if (bin >= bins)
                    bin = bins - 1;
                out[c * bins + bin] += 1;            // :206-215, channel-major
            }
        }
    }
    free(pixels);
}

@implementation MPSImageHistogram {
    MTLRegion _clipRectSource;
    BOOL _zeroHistogram;
    vector_float4 _minPixelThresholdValue;
    MPSImageHistogramInfo _histogramInfo;
}

@synthesize clipRectSource = _clipRectSource;
@synthesize zeroHistogram = _zeroHistogram;
@synthesize minPixelThresholdValue = _minPixelThresholdValue;
@synthesize histogramInfo = _histogramInfo;

// :76 - initWithDevice:histogramInfo: is the designated initializer, and the info IS the histogram's shape.
- (instancetype)initWithDevice:(id<MTLDevice>)device histogramInfo:(const MPSImageHistogramInfo *)histogramInfo
{
    if ((self = [super initWithDevice:device])) {
        if (!histogramInfo || !histogramInfo->numberOfHistogramEntries) {
            CharonMPSRefuse(@"MPSImageHistogram: MPSImageHistogramInfo with %lu entries describes no"
                            @" histogram, so no object was made",
                            (unsigned long)(histogramInfo ? histogramInfo->numberOfHistogramEntries : 0));
            return nil;
        }
        _histogramInfo = *histogramInfo;
        _clipRectSource = MPSRectNoClip;          // the default, as :42's wording gives
        _zeroHistogram = YES;                     // :49 - "Default: YES"
        _minPixelThresholdValue = (vector_float4){0.0f, 0.0f, 0.0f, 0.0f};
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    CharonMPSRefuse(@"MPSImageHistogram: -initWithCoder:device: is not carried - the release's keys for a"
                    @" histogram's bins and range are in no header, so a decoder cannot rebuild them"
                    @" honestly");
    return nil;
}

- (size_t)histogramSizeForSourceFormat:(MTLPixelFormat)sourceFormat
{
    // :131 - "The number of bytes needed to store the result histograms", and :208 says the channel count
    // follows the source unless histogramForAlpha trims it. The entry is a 32-bit count, which is the
    // width the buffer description and histogramSizeForSourceFormat: together imply.
    // Only the formats this surface actually names are answered. There is no MTLPixelFormatRGB8Unorm on
    // it - the 8-bit formats are the RGBA and BGRA ones - so a three-channel source would have to be
    // spelled from the real enum, and guessing at one that does not exist would be a compile error at
    // best and a wrong channel count at worst.
    if (sourceFormat != MTLPixelFormatRGBA8Unorm && sourceFormat != MTLPixelFormatRGBA8Unorm_sRGB) {
        CharonMPSRefuse(@"MPSImageHistogram: -histogramSizeForSourceFormat: is asked about pixel format %lu,"
                        @" which this port does not carry, so the size is not guessed", (unsigned long)sourceFormat);
        return 0;
    }
    NSUInteger channels = 4;
    if (!_histogramInfo.histogramForAlpha)
        channels = 3;                              // :208 - RGBA with histogramForAlpha false stores RGB only
    return (size_t)_histogramInfo.numberOfHistogramEntries * channels * sizeof(uint32_t);
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                sourceTexture:(id<MTLTexture>)source
                     histogram:(id<MTLBuffer>)histogram
                histogramOffset:(NSUInteger)histogramOffset
{
    NSString *what = NSStringFromClass([self class]);
    if (!source || !histogram) {
        CharonMPSRefuse(@"%@: a source texture and a histogram buffer are both required, so nothing was"
                        @" written", what);
        return;
    }
    NSUInteger channels = _histogramInfo.histogramForAlpha ? 4 : 3;
    size_t need = [self histogramSizeForSourceFormat:source.pixelFormat];
    unsigned char *base = (unsigned char *)[histogram contents];
    if (histogramOffset > [histogram length] || need > [histogram length] - histogramOffset) {
        CharonMPSRefuse(@"%@: %lu bytes at offset %lu will not fit a buffer of %lu, so nothing was written",
                        what, (unsigned long)need, (unsigned long)histogramOffset,
                        (unsigned long)[histogram length]);
        return;
    }
    uint32_t *bins = (uint32_t *)(base + histogramOffset);
    // :49 - zeroHistogram NO means the caller's existing counts are to be ADDED to, so the memory is only
    // cleared when it was asked for.
    if (_zeroHistogram)
        memset(bins, 0, need);
    MTLRegion window = _clipRectSource;
    if (window.size.width < 0 || window.size.height < 0) {
        window = MTLRegionMake2D(0, 0, source.width, source.height);   // MPSRectNoClip, the whole texture
    }
    CharonMPSHistogramRegion(source, window, _histogramInfo, _minPixelThresholdValue, bins, channels,
                             _histogramInfo.histogramForAlpha, what);
}

@end

// MPSImageNormalizedHistogram, :145 - ios(9.0), MPSKernel. The same histogram with the range taken from
// the image rather than given: :218 adds a minmaxTexture the per-image minimum and maximum are written
// into, and the bins then run between them. So the range is MEASURED here - one walk for the minimum and
// the maximum, then the same binning - and the min/max are written where :203 says, so a caller can see
// which range produced the counts.
@implementation MPSImageNormalizedHistogram {
    MTLRegion _clipRectSource;
    BOOL _zeroHistogram;
    MPSImageHistogramInfo _histogramInfo;
}

@synthesize clipRectSource = _clipRectSource;
@synthesize zeroHistogram = _zeroHistogram;
@synthesize histogramInfo = _histogramInfo;

- (instancetype)initWithDevice:(id<MTLDevice>)device histogramInfo:(const MPSImageHistogramInfo *)histogramInfo
{
    if ((self = [super initWithDevice:device])) {
        if (!histogramInfo || !histogramInfo->numberOfHistogramEntries) {
            CharonMPSRefuse(@"MPSImageNormalizedHistogram: MPSImageHistogramInfo with %lu entries describes"
                            @" no histogram, so no object was made",
                            (unsigned long)(histogramInfo ? histogramInfo->numberOfHistogramEntries : 0));
            return nil;
        }
        _histogramInfo = *histogramInfo;
        _clipRectSource = MPSRectNoClip;
        _zeroHistogram = YES;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    CharonMPSRefuse(@"MPSImageNormalizedHistogram: -initWithCoder:device: is not carried - the release's"
                    @" keys for a histogram's bins are in no header");
    return nil;
}

- (size_t)histogramSizeForSourceFormat:(MTLPixelFormat)sourceFormat
{
    if (sourceFormat != MTLPixelFormatRGBA8Unorm && sourceFormat != MTLPixelFormatRGBA8Unorm_sRGB)
        return 0;                                  // as above: not this port's format, not guessed
    NSUInteger channels = _histogramInfo.histogramForAlpha ? 4 : 3;
    return (size_t)_histogramInfo.numberOfHistogramEntries * channels * sizeof(uint32_t);
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                sourceTexture:(id<MTLTexture>)source
              minmaxTexture:(id<MTLTexture>)minmax
                     histogram:(id<MTLBuffer>)histogram
              histogramOffset:(NSUInteger)histogramOffset
{
    NSString *what = NSStringFromClass([self class]);
    if (!source || !histogram || !minmax) {
        CharonMPSRefuse(@"%@: a source texture, a minmax texture and a histogram buffer are all required,"
                        @" so nothing was written", what);
        return;
    }
    MTLRegion window = _clipRectSource;
    if (window.size.width < 0 || window.size.height < 0)
        window = MTLRegionMake2D(0, 0, source.width, source.height);
    // Clamp to the texture before reading, the same way CharonMPSHistogramRegion does. A window whose
    // origin is inside but whose size runs past the texture is clamped by the helper; this path reads the
    // window itself, so it must clamp here or it reads past the row and the range comes back empty.
    if (window.origin.x < 0) window.origin.x = 0;
    if (window.origin.y < 0) window.origin.y = 0;
    if (window.origin.x + window.size.width > source.width) window.size.width = source.width - window.origin.x;
    if (window.origin.y + window.size.height > source.height) window.size.height = source.height - window.origin.y;
    if (window.size.width == 0 || window.size.height == 0) {
        CharonMPSRefuse(@"%@: the window intersects the %lux%lu source to nothing, so there is no range to"
                        @" normalize and nothing was written", what, (unsigned long)source.width,
                        (unsigned long)source.height);
        return;
    }

    // The range this histogram normalizes over is the image's own minimum and maximum over the window,
    // so it is measured before anything is binned - and written to minmax, because :203 says the caller
    // is handed it and a range nobody can see is a range nobody can check.
    size_t bytes = (size_t)window.size.width * 4 * window.size.height * 4;
    unsigned char *pixels = malloc(bytes);
    if (!pixels) {
        CharonMPSRefuse(@"%@: no memory for a %lux%lu window, so nothing was written", what,
                        (unsigned long)window.size.width, (unsigned long)window.size.height);
        return;
    }
    [source getBytes:pixels bytesPerRow:window.size.width * 4
          fromRegion:MTLRegionMake2D(0, 0, window.size.width, window.size.height) mipmapLevel:0];
    double lo = 1.0, hi = 0.0;
    for (size_t i = 0; i < bytes; i += 4) {
        for (NSUInteger c = 0; c < 4; c++) {
            double v = (double)pixels[i + c] / 255.0;
            if (v < lo) lo = v;
            if (v > hi) hi = v;
        }
    }
    free(pixels);
    if (!(hi > lo)) {
        CharonMPSRefuse(@"%@: the window's own range is empty (%g..%g), so there is nothing to normalize"
                        @" and nothing was written", what, lo, hi);
        return;
    }
    // A texture has no -length; MTLTextureGetBytesPerPixel is how its row is measured, and a one-pixel
    // RGBA8 texture is eight bytes, which is the two floats :203 asks to be handed back.
    if ([minmax width] < 1 || [minmax height] < 1) {
        CharonMPSRefuse(@"%@: a minmax texture of %lux%lu has no room for a minimum and a maximum, so"
                        @" nothing was written", what, (unsigned long)[minmax width],
                        (unsigned long)[minmax height]);
        return;
    }
    // MTLTextureGetBytesPerPixel is not on this surface, and a texture does not report its length, so the
    // room is measured the way this package has measured everything else: from the format the caller gave
    // the encoder. The minmax texture the case builds is RGBA8 - one pixel is four bytes - and a format
    // this port does not carry is refused above rather than assumed to be roomy enough.
    if (minmax.pixelFormat != MTLPixelFormatRGBA8Unorm && minmax.pixelFormat != MTLPixelFormatRGBA8Unorm_sRGB) {
        CharonMPSRefuse(@"%@: a minmax texture of pixel format %lu is not one this port carries, so nothing"
                        @" was written", what, (unsigned long)minmax.pixelFormat);
        return;
    }
    if ([minmax width] < 1 || [minmax height] < 1) {
        CharonMPSRefuse(@"%@: a minmax texture of %lux%lu pixels has no pixel to put a minimum and a"
                        @" maximum in, so nothing was written", what, (unsigned long)[minmax width],
                        (unsigned long)[minmax height]);
        return;
    }
    // The minimum and the maximum go into the R and the G of ONE RGBA8 pixel - four bytes for two
    // unorm8 values. An earlier version of this check demanded room for two FLOATS, which the header
    // never asks for and which a 1x1 unorm8 texture cannot hold, so it refused the very case :203
    // describes. The values are quantised to unorm8, which is what an RGBA8 minmax texture IS: a caller
    // that needs float precision hands in a float texture, and this refuses that rather than pretending.
    // The min/max land in the R and G of one RGBA8 pixel, so the write is FOUR bytes with a bytesPerRow
    // of four. Writing two floats with a bytesPerRow of eight is a write past the row, which is the
    // "Region width OOB" the driver asserted on - our own write, not the source read.
    unsigned char minmaxOut[4] = {(unsigned char)(lo * 255.0), (unsigned char)(hi * 255.0), 0, 255};
    [minmax replaceRegion:MTLRegionMake2D(0, 0, 1, 1) mipmapLevel:0
               withBytes:minmaxOut bytesPerRow:4];

    NSUInteger channels = _histogramInfo.histogramForAlpha ? 4 : 3;
    size_t need = [self histogramSizeForSourceFormat:source.pixelFormat];
    unsigned char *base = (unsigned char *)[histogram contents];
    if (histogramOffset > [histogram length] || need > [histogram length] - histogramOffset) {
        CharonMPSRefuse(@"%@: %lu bytes at offset %lu will not fit a buffer of %lu, so nothing was written",
                        what, (unsigned long)need, (unsigned long)histogramOffset,
                        (unsigned long)[histogram length]);
        return;
    }
    uint32_t *bins = (uint32_t *)(base + histogramOffset);
    if (_zeroHistogram)
        memset(bins, 0, need);
    MPSImageHistogramInfo measured = _histogramInfo;
    measured.minPixelValue = (vector_float4){(float)lo, (float)lo, (float)lo, (float)lo};
    measured.maxPixelValue = (vector_float4){(float)hi, (float)hi, (float)hi, (float)hi};
    CharonMPSHistogramRegion(source, window, measured, (vector_float4){0.0f, 0.0f, 0.0f, 0.0f}, bins,
                             channels, _histogramInfo.histogramForAlpha, what);
}

@end

// OWED, and named here so the gap is in the file rather than only in the registry:
//
//   MPSImageHistogramEqualization (:268) and MPSImageHistogramSpecification (:340). Neither is a walk over
//   an image. Both build a TRANSFORM - :249 "image transform (i.e. a cumulative distribution function of
//   the histogram)" for the equalization, and :358 a transform from a "desiredHistogram" for the
//   specification - and their only encode is :425 encodeTransformToCommandBuffer:, which takes an
//   MTLComputeCommandEncoder. That is the one thing this host cannot do at all: its AGX family lacks
//   computeCommandEncoderWithDispatchType: and the release's own kernel dies encoding with an
//   unrecognized selector. So there is no oracle for them here and no way to check an answer, and an
//   untestable transform would be a guessed one.
