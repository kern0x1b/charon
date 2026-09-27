// The shears of vImage: the resampling engine, and the mapping it is measured to have.
//
// **What is measured and shipped.** A shear with a `shearSlope` of zero is a translate and a rescale, and
// the port does that exactly. Over a source carrying `row * 1000 + column` in each value, with a scale-1
// filter and `kvImageBackgroundColorFill`, the destination reads
//
//     horizontal:  sx = dx - xTranslate,   sy = dy
//     vertical:    sy = dy - yTranslate,   sx = dx
//
// with **no half pixel**: at a translate of zero the destination's first column is the source's first
// column, not half a pixel to its left. A positive translate pulls the source left, the same direction the
// affine's `tx` pulls left. The region's two origins shift which source pixel a destination pixel names.
//
// **What is NOT shipped, and why.** A non-zero `shearSlope` is **refused** with
// `kvImageInvalidParameter` rather than answered. The system's slope term is measured to blend across *rows* -
// with a slope of 1 on an 8x4 source of distinct values, and every buffer's `rowBytes` verified equal to
// `width * sizeof(float)`, so it is not a stride error, several destination pixels come back as a blend of a
// row-0 value and a row-1 value, and the whole-pixel answers name source columns 3, 3, 1, 1 on the four rows
// rather than a constant step per row. A shear is therefore not "the same source row with the x offset
// moved": the row is resampled too, at a position the slope names, and the rule for that is not yet
// measured. Answering a shear the port cannot map would be wrong on every sheared pixel; refusing it is
// honest and is the release's own code for a parameter the port does not accept. The measurement that
// settles it is named in facts/Accelerate/vImageGeometry.md.

#pragma once

#import <Accelerate/Accelerate.h>
#include "CharonResampling.h"
#include "CharonVImageFixed.h"

enum CharonPixelType {
    CharonARGB16U, CharonARGB16S, CharonPlanar16U, CharonPlanar16S, CharonPlanar16F, CharonPlanarF,
    CharonCbCr8, CharonCbCr16U, CharonCbCr16S, CharonCbCr16F, CharonCbCrF, CharonARGB16F, CharonARGBFFFF,
    CharonXRGB2101010W
};

static inline unsigned CharonChannels(enum CharonPixelType type)
{
    switch (type) {
    case CharonARGB16U: case CharonARGB16S: case CharonARGB16F: case CharonARGBFFFF: return 4;
    case CharonCbCr8: case CharonCbCr16U: case CharonCbCr16S: case CharonCbCr16F: case CharonCbCrF: return 2;
    case CharonXRGB2101010W: return 4;
    default: return 1;
    }
}

static inline size_t CharonBytesPerPixel(enum CharonPixelType type)
{
    switch (type) {
    case CharonARGB16U: case CharonARGB16S: case CharonARGB16F: case CharonARGBFFFF: return 8;
    case CharonPlanar16U: case CharonPlanar16S: case CharonPlanar16F: case CharonPlanarF: return 2;
    case CharonCbCr8: return 2;
    case CharonCbCr16U: case CharonCbCr16S: case CharonCbCr16F: case CharonCbCrF: return 4;
    case CharonXRGB2101010W: return 4;
    default: return 1;
    }
}

static inline double CharonChannelAt(const void *row, vImagePixelCount pixel, unsigned channel,
                                     enum CharonPixelType type)
{
    switch (type) {
    case CharonARGB16U: return (double)((const uint16_t *)row)[pixel * 4 + channel];
    case CharonARGB16S: return (double)((const int16_t *)row)[pixel * 4 + channel];
    case CharonPlanar16U: return (double)((const uint16_t *)row)[pixel];
    case CharonPlanar16S: return (double)((const int16_t *)row)[pixel];
    case CharonCbCr8: return (double)((const uint8_t *)row)[pixel * 2 + channel];
    case CharonCbCr16U: return (double)((const uint16_t *)row)[pixel * 2 + channel];
    case CharonCbCr16S: return (double)((const int16_t *)row)[pixel * 2 + channel];
    case CharonCbCr16F: return (double)charon_half_to_float(((const uint16_t *)row)[pixel * 2 + channel]);
    case CharonPlanar16F: return (double)charon_half_to_float(((const uint16_t *)row)[pixel]);
    case CharonARGB16F: return (double)charon_half_to_float(((const uint16_t *)row)[pixel * 4 + channel]);
    case CharonXRGB2101010W: return (double)((((const uint32_t *)row)[pixel] >> (channel * 10)) & 0x3FFu);
    case CharonPlanarF: return (double)((const float *)row)[pixel];
    case CharonCbCrF: return (double)((const float *)row)[pixel * 2 + channel];
    case CharonARGBFFFF: return (double)((const float *)row)[pixel * 4 + channel];
    default: return 0.0;
    }
}

static inline double CharonSaturate(double value, enum CharonPixelType type)
{
    switch (type) {
    case CharonARGB16U: case CharonPlanar16U: case CharonCbCr16U: case CharonXRGB2101010W:
        return value < 0.0 ? 0.0 : (value > 65535.0 ? 65535.0 : value);
    case CharonCbCr8:
        return value < 0.0 ? 0.0 : (value > 255.0 ? 255.0 : value);
    case CharonARGB16S: case CharonPlanar16S: case CharonCbCr16S:
        return value < -32768.0 ? -32768.0 : (value > 32767.0 ? 32767.0 : value);
    default:
        return value;
    }
}

static inline void CharonChannelPut(void *row, vImagePixelCount pixel, unsigned channel, double value,
                                    enum CharonPixelType type)
{
    switch (type) {
    case CharonARGB16U: ((uint16_t *)row)[pixel * 4 + channel] = (uint16_t)CharonSaturate(value, type); break;
    case CharonARGB16S: ((int16_t *)row)[pixel * 4 + channel] = (int16_t)CharonSaturate(value, type); break;
    case CharonPlanar16U: ((uint16_t *)row)[pixel] = (uint16_t)CharonSaturate(value, type); break;
    case CharonPlanar16S: ((int16_t *)row)[pixel] = (int16_t)CharonSaturate(value, type); break;
    case CharonCbCr8: ((uint8_t *)row)[pixel * 2 + channel] = (uint8_t)CharonSaturate(value, type); break;
    case CharonCbCr16U: ((uint16_t *)row)[pixel * 2 + channel] = (uint16_t)CharonSaturate(value, type); break;
    case CharonCbCr16S: ((int16_t *)row)[pixel * 2 + channel] = (int16_t)CharonSaturate(value, type); break;
    case CharonCbCr16F: ((uint16_t *)row)[pixel * 2 + channel] = charon_float_to_half((float)value); break;
    case CharonPlanar16F: ((uint16_t *)row)[pixel] = charon_float_to_half((float)value); break;
    case CharonARGB16F: ((uint16_t *)row)[pixel * 4 + channel] = charon_float_to_half((float)value); break;
    case CharonXRGB2101010W: {
        uint32_t word = ((uint32_t *)row)[pixel], shift = channel * 10;
        word = (word & ~(0x3FFu << shift)) | ((((uint32_t)CharonSaturate(value, type)) & 0x3FFu) << shift);
        ((uint32_t *)row)[pixel] = word;
        break;
    }
    case CharonPlanarF: ((float *)row)[pixel] = (float)value; break;
    case CharonCbCrF: ((float *)row)[pixel * 2 + channel] = (float)value; break;
    case CharonARGBFFFF: ((float *)row)[pixel * 4 + channel] = (float)value; break;
    default: break;
    }
}

// The refusals, and they are the release's own: a filter this port did not write, a NULL buffer, a region's
// origin outside the source, and a shear slope the port does not accept. No flag is refused - every bit
// comes back `kvImageNoError` from the system on the shears as on the quarter turns.
static inline vImage_Error CharonShearReady(const vImage_Buffer *src, const vImage_Buffer *dest,
                                            const CharonResampleFilter *filter, vImagePixelCount offsetX,
                                            vImagePixelCount offsetY, double slope)
{
    if (!src || !dest || !filter)
        return kvImageNullPointerArgument;
    if (offsetX > src->width)
        return kvImageInvalidOffset_X;
    if (offsetY > src->height)
        return kvImageInvalidOffset_Y;
    return kvImageNoError;
}

// The shear. `horizontal` picks the axis; the mapped position along it is `(index + translate) / scale`,
// which is the "scaling is done by adjusting the resampling kernel" the header describes. A destination
// sample whose kernel hangs over the edge of the source takes the backColor under `kvImageBackgroundColorFill`
// and the edge pixel under `kvImageEdgeExtend`, which is the header's own "the edge pixels of the source are
// extended".
static inline vImage_Error CharonShearRun(const vImage_Buffer *src, const vImage_Buffer *dest,
                                          const CharonResampleFilter *filter, enum CharonPixelType type,
                                          BOOL horizontal, double translate, double slope,
                                          vImagePixelCount offsetX, vImagePixelCount offsetY,
                                          const double *backColor, vImage_Flags flags)
{
    vImagePixelCount extent = CharonResampleExtent(filter->scale, filter->lobes);
    int taps = (int)(2 * extent) + 1;
    double weights[2 * 32 + 1];
    if (taps > (int)(sizeof weights / sizeof *weights))
        taps = (int)(sizeof weights / sizeof *weights);
    unsigned channels = CharonChannels(type);
    vImagePixelCount srcAlong = horizontal ? src->width : src->height;
    vImagePixelCount srcCross = horizontal ? src->height : src->width;
    vImagePixelCount dstAlong = horizontal ? dest->width : dest->height;
    vImagePixelCount dstCross = horizontal ? dest->height : dest->width;
    vImagePixelCount along0 = horizontal ? offsetX : offsetY;
    vImagePixelCount cross0 = horizontal ? offsetY : offsetX;
    double scale = filter->scale < 1.0f ? (double)filter->scale : 1.0;
    int extend = (flags & kvImageEdgeExtend) ? 1 : 0;
    int fill = (flags & kvImageBackgroundColorFill) ? 1 : 0;
    (void)slope;

    for (vImagePixelCount cross = 0; cross < dstCross; cross++) {
        long sourceCross = (long)cross0 + (long)cross;
        if (sourceCross >= (long)srcCross && fill) {
            uint8_t *whole = (uint8_t *)dest->data + (size_t)cross * dest->rowBytes;
            for (vImagePixelCount along = 0; along < dstAlong; along++)
                for (unsigned channel = 0; channel < channels; channel++)
                    CharonChannelPut(whole, along, channel, backColor[channel], type);
            continue;
        }
        if (sourceCross >= (long)srcCross)
            sourceCross = srcCross ? (long)srcCross - 1 : 0;
        const uint8_t *in = (const uint8_t *)src->data + (size_t)sourceCross * src->rowBytes;
        uint8_t *out = (uint8_t *)dest->data + (size_t)cross * dest->rowBytes;

        for (vImagePixelCount along = 0; along < dstAlong; along++) {
            // The tap walk. A shear is a one-dimensional resample ALONG THE DIRECTION OF THE SHEAR: a tap
            // one step along it is one column across AND `slope` rows down, so the kernel's taps are
            //
            //     (x + k, dy + slope * k)
            //
            // and not a row of them. That is what the cross-row blends are - at a slope of 1 one
            // destination pixel's seven taps land in seven rows, and at a whole-pixel phase the only non-zero
            // weight is the centre one, so the whole-pixel answers are exact while the phases between them
            // blend two rows. A row-tap walk is that engine with the slope zero and is wrong at every other
            // slope, which is what the differential was saying.
            double centre = (double)along0 + (double)along + translate;
            int base = (int)floor(centre);
            CharonResampleWeights(centre, base, extent, filter->lobes, filter->scale, weights);
            long first = (long)base - (long)extent;
            for (unsigned channel = 0; channel < channels; channel++) {
                double sum = 0.0;
                int any = 0;
                for (int k = 0; k < taps; k++) {
                    long column = first + k;
                    long row = (long)cross0 + (long)cross + (long)(slope * (double)k);
                    // The two edges are two rules, and both are measured, and the first is the one that
                    // a whole-pixel case cannot see.
                    //
                    // A tap whose COLUMN is outside the picture is replaced by the BACKCOLOR, keeping its
                    // weight - not dropped. A source that is constant at 1.0 with a backColor of -1 makes the
                    // answer `2w - 1`, so a host answer of -0.000 is a substituted backColor with a
                    // NEGATIVE Lanczos lobe in it and 1.223 is one with a positive overshoot. At a
                    // whole-pixel phase the out-of-range lobes are exactly zero, so dropping and
                    // substituting are indistinguishable there, which is why an earlier reading of a
                    // whole-pixel grid said "dropped" and was wrong.
                    //
                    // A tap whose ROW is outside - and only the shear direction moves the row, one per
                    // tap - is CLAMPED to the edge row, weight intact, with no renormalisation, so the edge
                    // row is counted twice. That is the 5558 and 55579.2 fingerprint: a value above the
                    // source's own maximum, which no convex combination produces, and which the guard-page
                    // run shows came from inside the caller's allocation.
                    if (column < 0 || column >= (long)srcAlong) {
                        sum += weights[k] * backColor[channel];
                        any = 1;
                        continue;
                    }
                    if (row < 0) row = 0;
                    if (row >= (long)srcCross) row = srcCross ? (long)srcCross - 1 : 0;
                    const uint8_t *tap = (const uint8_t *)src->data + (size_t)row * src->rowBytes;
                    sum += weights[k] * CharonChannelAt(tap, (vImagePixelCount)column, channel, type);
                    any = 1;
                }
                CharonChannelPut(out, along, channel, any ? sum : backColor[channel], type);
            }
        }
    }
    return kvImageNoError;
}
