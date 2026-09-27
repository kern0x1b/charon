// The geometry of vImage: one mapping, one loop, and the per-pixel-type facts the rest of the family
// shares.
//
// A quarter turn of a WxH picture is an HxW picture, so the destination is `W x H` for constants 0 and 2 and
// `H x W` for 1 and 3 - and a destination of the *other* shape is not an error: the system turns the picture
// and centres it in the frame it was given, so the parts that do not fit are the backColor. Measured both
// ways over eight shapes, 6x4, 4x6, 4x3, 5x3, 5x5, 2x3, 3x2 and 6x5, with every source pixel carrying its
// own coordinates: with the destination the constant wants, every cell of every grid is a source pixel, and
// with the other one the same formula runs and the samples outside the source are the backColor. So there is
// one formula per constant and a range test, and **no shape test at all**.
//
//   constant 0   src(dx, dy)
//   constant 1   src(dy, W-1-dx)
//   constant 2   src(W-1-dx, H-1-dy)
//   constant 3   src(dy, H-1-dx)
//
// Nothing in a quarter turn resamples: every destination pixel is one source pixel, copied. That is why the
// loop moves bytes and never looks at a value - there is no rounding to get wrong and no channel to clamp,
// and it is what the measurements show (not one background pixel in a grid whose destination the constant
// wants, and not one interpolated value).

#pragma once

#import <Accelerate/Accelerate.h>
#include <string.h>

// Where one destination pixel comes from, and whether that is inside the source at all. `W` and `H` are the
// source's extents, which is all the constant needs.
typedef struct CharonTurn {
    int inside;
    vImagePixelCount sourceX;
    vImagePixelCount sourceY;
} CharonTurn;

static inline CharonTurn charon_turn(uint8_t rotationConstant, vImagePixelCount dx, vImagePixelCount dy,
                                     vImagePixelCount width, vImagePixelCount height)
{
    CharonTurn found;
    vImagePixelCount x, y;
    switch (rotationConstant) {
    case 0: x = dx;          y = dy;          break;
    case 1: x = dy;          y = width - 1 - dx; break;
    case 2: x = width - 1 - dx; y = height - 1 - dy; break;
    default: x = dy;         y = height - 1 - dx; break;
    }
    found.inside = (x < width && y < height) ? 1 : 0;
    found.sourceX = x;
    found.sourceY = y;
    return found;
}

// The refusals, and they are the release's own: the flags the header lists for these functions, a NULL
// buffer, and a constant outside the four the header names. GetTempBufferSize is not in that list, so it is
// not accepted here either.
static inline vImage_Error charon_turn_ready(const vImage_Buffer *src, const vImage_Buffer *dest,
                                             uint8_t rotationConstant, vImage_Flags flags, BOOL halfPrecision)
{
    vImage_Flags allowed = kvImageEdgeExtend | kvImageBackgroundColorFill | kvImageDoNotTile | kvImageNoFlags;
    if (halfPrecision)
        allowed |= kvImageUseFP16Accumulator;
    if (flags & ~allowed)
        return kvImageUnknownFlagsBit;
    if (rotationConstant > 3)
        return kvImageInvalidParameter;
    if (!src || !dest)
        return kvImageNullPointerArgument;
    return kvImageNoError;
}

// The loop, over a pixel of `bytes` per sample. A destination pixel outside the source is the backColor,
// or - under kvImageEdgeExtend, which is the header's own "the edge pixels of the source are extended" -
// the nearest pixel inside it, which is the mapping clamped to the source's own extent.
static inline vImage_Error charon_turn_run(const vImage_Buffer *src, const vImage_Buffer *dest,
                                           uint8_t rotationConstant, const void *backColor, size_t bytes,
                                           vImage_Flags flags)
{
    vImagePixelCount width = src->width, height = src->height;
    int extend = (flags & kvImageEdgeExtend) ? 1 : 0;
    for (vImagePixelCount dy = 0; dy < dest->height; dy++) {
        uint8_t *out = (uint8_t *)dest->data + (size_t)dy * dest->rowBytes;
        for (vImagePixelCount dx = 0; dx < dest->width; dx++) {
            CharonTurn from = charon_turn(rotationConstant, dx, dy, width, height);
            if (!from.inside && extend) {
                from.sourceX = from.sourceX < width ? from.sourceX : (width ? width - 1 : 0);
                from.sourceY = from.sourceY < height ? from.sourceY : (height ? height - 1 : 0);
            }
            const uint8_t *pixel;
            if (from.inside) {
                pixel = (const uint8_t *)src->data + (size_t)from.sourceY * src->rowBytes
                      + (size_t)from.sourceX * bytes;
            } else {
                pixel = (const uint8_t *)backColor;
            }
            memcpy(out + (size_t)dx * bytes, pixel, bytes);
        }
    }
    return kvImageNoError;
}
