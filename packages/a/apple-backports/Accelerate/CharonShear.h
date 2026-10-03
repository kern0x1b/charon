// The shears of vImage: the resampling engine, and the mapping it is measured to have.
//
// **The mapping, in full, as measured.** A destination sample's mapped position along the shear is
//
//     horizontal:  alongPosition = along0 + along + 0.5 - translate + slope * (cross - dstCross + 0.5)
//                  centre        = alongPosition / scale - 0.5
//
//     vertical:    alongPosition = along0 + along + 0.5 + translate + slope * (cross + 0.5)
//                  centre        = dstAlong + (alongPosition - dstAlong) / scale - 0.5
//
// with `along` and `cross` the destination's own coordinates along and across the shear, `along0` and `cross0`
// the region's origins, `dstAlong` and `dstCross` the DESTINATION's extents, and the row each destination row
// reads its own: `row = cross0 + cross`. Every term of that was read off the host's own kernel rather than
// assumed, and the two lines that were wrong before are named:
//
// - **the vertical's scale is anchored to the destination's far edge and the horizontal's to its near edge.**
//   At a scale of two on a twelve-row source the vertical's destination row 0 maps to source row 5.75 and the
//   horizontal's destination column 0 to source column -0.25, and the offset is exactly
//   `dstAlong * (1 - 1/scale)` on one axis and zero on the other. The offset is the DESTINATION's extent and
//   not the source's: a twelve-row source into a twenty-row destination offsets by ten and not by six.
// - **the slope's cross coordinate is read from the opposite edge on each axis.** On the horizontal the amount
//   of shear grows as the distance from the bottom row, and on the vertical as the distance from the left
//   column, so the term is `slope * (cross - dstCross + 0.5)` and `slope * (cross + 0.5)` respectively. The two
//   axes are mirrors of each other, which is why the horizontal's is negated where the vertical's is not.
//
// The kernel is the published one and needs nothing measured here: Lanczos3, or Lanczos5 under
// `kvImageHighQualityResampling`, over `ceil(lobes / min(1, scale))` taps each side, normalised per phase.
// CharonResampling.h carries it, and the host's own weights agree with it to the fourth decimal (the
// residual of a fit is at rounding size in every case in facts/Accelerate/vImageGeometry.md).
//
// **The edging.** A tap outside the picture along the shear is REPLACED BY THE BACKCOLOR with its weight kept,
// not dropped: a source constant at 1.0 with a backColor of -1 makes the answer `2w - 1` and the host answers
// -0.000 and 1.223, which are weights and not gaps. Under `kvImageEdgeExtend` the tap is pulled back to the
// edge instead, which is the header's own "the edge pixels of the source are extended". Neither mode
// renormalises over the survivors, which is what the overshoot at the last row is.
//
// **The refusals**, and they are the release's own, measured on the host's own shears: a NULL buffer is
// `kvImageNullPointerArgument`, a NULL filter is `kvImageInvalidParameter`, and a region or a destination that
// does not fit across the shear is `kvImageBufferSizeMismatch`. No flag is refused - every one of the
// thirty-two bits comes back `kvImageNoError`.

#pragma once

#import <Accelerate/Accelerate.h>
#include "CharonChannels.h"
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
    case CharonARGB16U: case CharonARGB16S: case CharonARGB16F: return 8;
    case CharonARGBFFFF: return 16;
    case CharonPlanar16U: case CharonPlanar16S: case CharonPlanar16F: return 2;
    case CharonPlanarF: return 4;
    case CharonCbCr8: return 2;
    case CharonCbCr16U: case CharonCbCr16S: case CharonCbCr16F: return 4;
    case CharonCbCrF: return 8;
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

// The caller's backColor in the engine's own scale, one reader per storage the header's pixel types use.
// **These exist because reading a backColor as `sizeof(double) * channels` bytes is wrong for every one of
// them but the four-channel float form.** `Pixel_ARGB_16U` is four `uint16_t` and eight bytes, `Pixel_16U16U`
// is two of them and four bytes, `Pixel_88` is two bytes, and `Pixel_16U`, `Pixel_16S`, `Pixel_32U` and
// `Pixel_16F` are scalars, so the parameter is a POINTER and `(double)backColor` is the pointer's own value as
// a number. An earlier version of the four band files did both: it copied 32 bytes out of an eight-byte
// `Pixel_ARGB_16U` and out of a four-byte `Pixel_16U16U`, and it converted the pointer. Each element is read
// here as the type it is, and the half-precision forms go through the same conversion the samples do.
static inline void CharonShearBackU16(double *out, const uint16_t *values, unsigned channels)
{
    for (unsigned channel = 0; channel < channels; channel++)
        out[channel] = (double)values[channel];
}

static inline void CharonShearBackS16(double *out, const int16_t *values, unsigned channels)
{
    for (unsigned channel = 0; channel < channels; channel++)
        out[channel] = (double)values[channel];
}

static inline void CharonShearBackU8(double *out, const uint8_t *values, unsigned channels)
{
    for (unsigned channel = 0; channel < channels; channel++)
        out[channel] = (double)values[channel];
}

static inline void CharonShearBackF16(double *out, const uint16_t *values, unsigned channels)
{
    for (unsigned channel = 0; channel < channels; channel++)
        out[channel] = (double)charon_half_to_float(values[channel]);
}

// **The flag word, measured per shape over all thirty-two bits**, because the shears do not all take the same
// set and neither the header nor an earlier measurement says so. The three half-precision shapes -
// `ARGB16F`, `CbCr16F`, `Planar16F` - take seven bits and answer `kvImageUnknownFlagsBit` for the other
// twenty-five; **every other shape takes all thirty-two**, which is what a first pass over the family measured
// and what the header's silence suggests. A bit outside the set is refused rather than ignored.
//
// The seven are `kvImageBackgroundColorFill`, `kvImageEdgeExtend`, `kvImageDoNotTile`,
// `kvImageHighQualityResampling`, `kvImageGetTempBufferSize`, `kvImagePrintDiagnosticsToConsole` and
// `kvImageUseFP16Accumulator` - the mask is 0x11bc - and the three refused ones are
// `kvImageLeaveAlphaUnchanged` (0x1), `kvImageCopyInPlace` (0x2) and `kvImageTruncateKernel` (0x40).
static inline unsigned CharonShearFlags(enum CharonPixelType type)
{
    switch (type) {
    case CharonARGB16F: case CharonCbCr16F: case CharonPlanar16F:
        return (unsigned)(kvImageBackgroundColorFill | kvImageEdgeExtend | kvImageDoNotTile
                          | kvImageHighQualityResampling | kvImageGetTempBufferSize
                          | kvImagePrintDiagnosticsToConsole | kvImageUseFP16Accumulator);
    default:
        return 0xFFFFFFFFu;
    }
}

// The refusals, in the order the release makes them. Measured on the host's own shears, over a NULL buffer, a
// NULL filter, every bit of the flag word, and the region's two origins against the destination's two extents.
//
// **The NULL test is CharonChannelsIsNull's, reused rather than written again**: `src` and `dest` are declared
// `VIMAGE_NON_NULL(1,2)`, so an attributed parameter is assumed non-null inside the function and a plain
// `if (!src)` is folded away at -Os - there is no compare against zero anywhere in the object - while a
// volatile read is a memory access the optimizer has to honour. The four spellings and their disassembly are
// in CharonChannels.h's own comment, and that is where the measurement lives.
//
// `filter` is NOT attributed (`VIMAGE_NON_NULL(1,2)` names only the two buffers), so CharonResampleFilterOf's
// plain test survives at -Os and needs nothing; it returns NULL for a NULL filter and for a buffer that is not
// one of the port's, and the host answers `kvImageInvalidParameter` for the first of those.
//
// The cross extent is the one the release checks: `cross0 + destCross > srcCross` is
// `kvImageBufferSizeMismatch`, measured over three destination extents and both axes, and it is the ONLY shape
// condition - the destination's along extent is free, and so is the along offset, which a source nine wide
// accepts at twelve.
static inline vImage_Error CharonShearReady(const vImage_Buffer *src, const vImage_Buffer *dest,
                                            const CharonResampleFilter *filter, int horizontal,
                                            vImagePixelCount offsetX, vImagePixelCount offsetY)
{
    if (CharonChannelsIsNull(src) || CharonChannelsIsNull(dest))
        return kvImageNullPointerArgument;
    if (!filter || filter->magic != CharonResampleMagic)
        return kvImageInvalidParameter;
    vImagePixelCount cross0 = horizontal ? offsetY : offsetX;
    vImagePixelCount dstCross = horizontal ? dest->height : dest->width;
    vImagePixelCount srcCross = horizontal ? src->height : src->width;
    if (cross0 + dstCross > srcCross)
        return kvImageBufferSizeMismatch;
    return kvImageNoError;
}

// The shear. `horizontal` picks the axis; the two lines of the mapping are at the top of this file and each of
// them is there for a measurement the facts page records.
static inline vImage_Error CharonShearRun(const vImage_Buffer *src, const vImage_Buffer *dest,
                                          const CharonResampleFilter *filter, enum CharonPixelType type,
                                          int horizontal, double translate, double slope,
                                          vImagePixelCount offsetX, vImagePixelCount offsetY,
                                          const double *backColor, vImage_Flags flags)
{
    // The flags are read LAST, after the buffers, the filter and the region's shape: measured on a call that
    // breaks two rules at once, a bad flag beside an across offset of one answers the offset, and a NULL
    // destination beside a bad flag answers the NULL. So this refusal sits here rather than in
    // CharonShearReady, which has already answered the other three by the time the engine is reached.
    if (flags & ~CharonShearFlags(type))
        return kvImageUnknownFlagsBit;
    vImagePixelCount extent = CharonResampleExtent(filter->scale, filter->lobes);
    int taps = (int)(2 * extent) + 1;
    double weights[2 * 32 + 1];
    if (taps > (int)(sizeof weights / sizeof *weights))
        taps = (int)(sizeof weights / sizeof *weights);
    unsigned channels = CharonChannels(type);
    vImagePixelCount srcAlong = horizontal ? src->width : src->height;
    vImagePixelCount dstAlong = horizontal ? dest->width : dest->height;
    vImagePixelCount dstCross = horizontal ? dest->height : dest->width;
    vImagePixelCount along0 = horizontal ? offsetX : offsetY;
    vImagePixelCount cross0 = horizontal ? offsetY : offsetX;
    double scale = (double)filter->scale;
    int extend = (flags & kvImageEdgeExtend) ? 1 : 0;

    // The two axes are kept apart on purpose, because they are different and mixing them is what read past
    // the caller's buffer. `at` is the position ALONG the shear and is bounded by srcAlong - the width for
    // a horizontal shear, the HEIGHT for a vertical one. `row` is the position ACROSS the shear and is
    // bounded by srcCross, the other extent. The ADDRESS is the only place the two swap: it is always
    // `data + ROW * rowBytes + COL * pixelBytes`, with ROW the across value and the along value the other
    // way round according to the axis. Clamping the across value against srcCross and then multiplying it
    // by rowBytes is the bug AddressSanitizer named at CharonShear.h:225 - for the vertical shear srcCross
    // is the width, so a "row" clamped to srcCross - 1 was 8, and 8 * 36 is 288 bytes into a 180-byte image.
    //
    // `row` needs no clamp: CharonShearReady has refused every call where `cross0 + cross` could reach
    // srcCross, so for a call that gets here it is inside the picture by construction.
    const size_t pixelBytes = CharonBytesPerPixel(type);
#define CHARON_SHEAR_AT(img, along_, cross_) \
    ((uint8_t *)(img)->data + (size_t)(horizontal ? (cross_) : (along_)) * (img)->rowBytes \
     + (size_t)(horizontal ? (along_) : (cross_)) * pixelBytes)

    for (vImagePixelCount cross = 0; cross < dstCross; cross++) {
        long sourceCross = (long)cross0 + (long)cross;
        for (vImagePixelCount along = 0; along < dstAlong; along++) {
            // The shear shifts the ALONG position by the slope times the CROSS coordinate of the destination,
            // once for the whole row - not once per tap. The row a destination row reads is its own; what
            // moves sideways is where along that row it looks. The half pixel is in the cross coordinate
            // because a row is sampled at its centre.
            //
            // `edge` is that cross coordinate counted from the edge the axis reads it at: the horizontal's
            // amounts grow as the distance from the BOTTOM row, so `edge` runs down from `dstCross`, and the
            // vertical's grow as the distance from the LEFT column, so `edge` runs up from zero. The two
            // axes are mirrors, which is why the horizontal's term carries the slope negated and the
            // vertical's does not - and the vertical's near edge is one further than the horizontal's, so
            // that both come out of the same `edge - 0.5`.
            double edge = horizontal ? (double)dstCross - (double)cross : (double)cross + 1.0;
            double alongPosition = (double)(along0 + along) + 0.5
                                   + (horizontal ? -translate : translate)
                                   + (horizontal ? -slope : slope) * (edge - 0.5);
            // The scale's anchor: the horizontal's near edge is the origin, the vertical's far edge is.
            double centre = horizontal ? alongPosition / scale - 0.5
                                       : (double)dstAlong + (alongPosition - (double)dstAlong) / scale - 0.5;
            int base = (int)floor(centre);
            CharonResampleWeights(centre, base, extent, filter->lobes, filter->scale, weights);
            long first = (long)base - (long)extent;
            for (unsigned channel = 0; channel < channels; channel++) {
                double sum = 0.0;
                for (int k = 0; k < taps; k++) {
                    long at = first + k;
                    // A tap outside ALONG the shear is replaced by the BACKCOLOR with its weight kept, not
                    // dropped: a source constant at 1.0 with a backColor of -1 makes the answer `2w - 1`,
                    // and the system answers -0.000 and 1.223, which are weights and not gaps. At a
                    // whole-pixel phase the out-of-range lobes are exactly zero, so the two cannot be
                    // told apart there.
                    if (at < 0 || at >= (long)srcAlong) {
                        // kvImageEdgeExtend is the header's own "the edge pixels of the source are
                        // extended": the tap is pulled back to the edge and keeps its weight, where
                        // kvImageBackgroundColorFill substitutes the backColor instead.
                        if (!extend) {
                            sum += weights[k] * backColor[channel];
                            continue;
                        }
                        at = at < 0 ? 0 : (srcAlong ? (long)srcAlong - 1 : 0);
                    }
                    sum += weights[k] * CharonChannelAt(CHARON_SHEAR_AT(src, at, sourceCross), 0, channel, type);
                }
                CharonChannelPut(CHARON_SHEAR_AT(dest, along, cross), 0, channel, sum, type);
            }
        }
    }
#undef CHARON_SHEAR_AT
    return kvImageNoError;
}