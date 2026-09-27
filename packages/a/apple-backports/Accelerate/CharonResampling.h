// The resampling filter of vImage's shears, and the one-dimensional resampling the twenty-four shears
// are made of.
//
// `ResamplingFilter` is a `void *`, and on the port's own releases there is nothing to make one with: the
// Accelerate band measured that the armv7 caches carry **none** of vImage's C API below 7.0.1, so whatever
// the header's `API_AVAILABLE(ios(5.0))` says, there is no `vImageNewResamplingFilter` and no
// `vImageNewResamplingFilterForFunctionUsingBuffer` on 4.3 or 6.1.3 to fill a caller's buffer. So the port
// writes the filter itself, into a buffer the caller allocated from `vImageGetResamplingFilterSize`, and
// **the layout is the port's own** - which is what the header leaves room for when it declines to publish
// one, and what makes the whole family possible rather than a dead end.
//
// What the filter holds is what the kernel is *defined by*: the scale and the lobe count. The header
// describes the release's object as holding "precalculated filter coefficients", and the port's holds the
// parameters those coefficients are computed from, which is exact rather than quantised - a table of
// per-phase weights would be an approximation of the same curve, and the cost of the approximation is a
// deviation from the system on every sheared pixel.
//
// The kernel itself is the documented default, **Lanczos3** - Lanczos5 under `kvImageHighQualityResampling` -
// and the support is the documented one, scaled by the inverse of the scale when the scale is below one.
// That the support rule is right is measured, not assumed: `vImageGetResamplingFilterExtent` on the system
// answers 12, 6, 4 and 3 for scales 0.25, 0.5, 0.75 and 1.0, and 3 for every scale from one to two, which is
// `ceil(lobes / min(1, scale))` exactly.
//
// The weights are `sinc(x) * sinc(x / lobes)` at each tap's distance from the mapped position, **normalised
// per phase** so that they sum to one. The normalisation is not decoration: the system's own float weights
// at a phase of 0.5 are +0.61141, -0.13587 and +0.02446, and the unnormalised lobes there are +0.60793,
// -0.13509 and +0.02432 - so the normalising divisor is in them.

#pragma once

#import <Accelerate/Accelerate.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

// The lobes the two kernels have, which is what `kvImageHighQualityResampling` selects between.
#define CHARON_RESAMPLE_LOBES 3
#define CHARON_RESAMPLE_LOBES_HIGH 5

enum {
    CharonResampleMagic = 0x52534D50    // "RSMP", so a buffer that is not ours is refused rather than read
};

// The filter, in the port's own layout. The name carries a Charon prefix because the gate does not weigh a
// symbol of the port's own against a release or ask the registry about it (modules/apple/backports.lua,
// internal_symbol), the same reason CharonGeometry.h's and CharonYpCbCr.h's do. The tag is what keeps a
// buffer that is not one of ours from being read as one.
typedef struct CharonResampleFilter {
    uint32_t magic;
    float scale;
    uint32_t lobes;
    uint32_t reserved;
} CharonResampleFilter;

// The support, in pixels on each side: the lobes divided by the smaller of one and the scale, which is the
// documented "the support is scaled by 1/scale when downsampling" and the extent table the system answers.
static inline vImagePixelCount CharonResampleExtent(float scale, uint32_t lobes)
{
    float factor = scale < 1.0f ? scale : 1.0f;
    float extent = (float)lobes / factor;
    return (vImagePixelCount)ceilf(extent - 1.0e-4f);
}

static inline uint32_t CharonResampleLobes(vImage_Flags flags)
{
    return (flags & kvImageHighQualityResampling) ? CHARON_RESAMPLE_LOBES_HIGH : CHARON_RESAMPLE_LOBES;
}

// The buffer's size, which is what the caller allocates with. The header's constructor is documented to
// write "the kernel values into a preallocated kernel buffer" of "at least the size of the kernel data",
// which is this number, so a caller that trusts `vImageGetResamplingFilterSize` and then hands the buffer
// to a shear gets a buffer this will accept.
static inline size_t CharonResampleBufferSize(void)
{
    return sizeof(CharonResampleFilter);
}

// The filter a caller made, and whether it is one of ours. A NULL filter is refused rather than read, and a
// buffer whose tag is not ours is refused too: reading a release's or an application's bytes as a scale would
// be a wild pointer dressed as a resampling.
static inline const CharonResampleFilter *CharonResampleFilterOf(ResamplingFilter filter)
{
    const CharonResampleFilter *found = (const CharonResampleFilter *)filter;
    if (!found || found->magic != CharonResampleMagic)
        return NULL;
    return found;
}

// Filling a caller's buffer, and the one thing the port has to do that a release would have done.
static inline void CharonResampleFilterInit(void *buffer, float scale, vImage_Flags flags)
{
    CharonResampleFilter *filter = (CharonResampleFilter *)buffer;
    if (!filter)
        return;
    filter->magic = CharonResampleMagic;
    filter->scale = scale > 0.0f ? scale : 1.0f;
    filter->lobes = CharonResampleLobes(flags);
    filter->reserved = 0;
}

static inline double CharonSinc(double x)
{
    if (x == 0.0)
        return 1.0;
    return sin(M_PI * x) / (M_PI * x);
}

static inline double CharonLanczos(double x, uint32_t lobes)
{
    double a = (double)lobes;
    if (x <= -a || x >= a)
        return 0.0;
    return CharonSinc(x) * CharonSinc(x / a);
}

// The weights for one phase, written into `weights[0 .. 2 * extent]`, and the sum they were normalised
// from. `centre` is the mapped position and `taps` the first tap: the mapped position falls between taps
// `taps` and `taps + 1`, so the distance to tap `taps + k` is `centre - (taps + k)`.
//
// The support of the kernel is scaled by 1/scale when the scale is below one, so the number of taps either
// side is `extent` and the step between them is the position's own step divided by the scale - which is what
// makes a downscale read several source pixels per destination one and an upscale read none.
static inline void CharonResampleWeights(double centre, int taps, vImagePixelCount extent, uint32_t lobes,
                                         float scale, double *weights)
{
    int count = (int)(2 * extent) + 1;
    double step = 1.0 / (double)(scale < 1.0f ? scale : 1.0f);
    double sum = 0.0;
    int first = taps - (int)extent;
    for (int k = 0; k < count; k++) {
        // the source position this tap stands for, and the kernel's distance from the mapped position
        double at = (double)(first + k) * step;
        double distance = (centre - at) * step;
        weights[k] = CharonLanczos(distance, lobes);
        sum += weights[k];
    }
    if (sum != 0.0) {
        for (int k = 0; k < count; k++)
            weights[k] /= sum;
    }
}

// One row of one channel of a pixel, gathered: `load` reads the channel at a source index and `store`
// writes the result, and between them the weights and the source indices are all that is left. The eleven
// pixel types the corpus's shears name differ only in those two, which is why one engine serves all
// thirty-six functions.
typedef double (*CharonResampleLoad)(const void *row, vImagePixelCount index, void *context);
typedef void (*CharonResampleStore)(void *row, vImagePixelCount index, double value, void *context);

// One destination sample of one row, from the source row through the filter. `centre` is the mapped
// position in source pixels; the edging is the caller's, because `kvImageEdgeExtend` and
// `kvImageBackgroundColorFill` mean different things and the caller owns the backColor.
static inline double CharonResampleSample(const void *sourceRow, vImagePixelCount sourceCount, double centre,
                                          vImagePixelCount extent, uint32_t lobes, float scale,
                                          CharonResampleLoad load, void *loadContext)
{
    int count = (int)(2 * extent) + 1;
    int first = (int)floor(centre) - (int)extent;
    double weights[2 * 32 + 1];
    double sum = 0.0;
    if (count > (int)(sizeof weights / sizeof *weights))
        count = (int)(sizeof weights / sizeof *weights);
    CharonResampleWeights(centre, (int)floor(centre), extent, lobes, scale, weights);
    for (int k = 0; k < count; k++) {
        long index = (long)first + k;
        if (index < 0 || index >= (long)sourceCount)
            continue;   // outside the source: the caller's edging decides, and this contributes nothing
        sum += weights[k] * load(sourceRow, (vImagePixelCount)index, loadContext);
    }
    return sum;
}
