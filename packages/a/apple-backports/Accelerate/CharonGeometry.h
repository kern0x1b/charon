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
    vImagePixelCount sourceRow;
    vImagePixelCount sourceColumn;
} CharonTurn;

// A quarter turn's mapping MIXES the two axes - for constant 1 the destination's column becomes the
// source's ROW - so the coordinate is built in the source's own (row, column) and range-tested there. An
// earlier version built it in (x, y) and tested the first component against the width, which is the wrong
// axis whenever the two extents differ; the differential caught it on the shapes where they do, and the
// twelve-shape table below is what it is.
static inline CharonTurn charon_turn(uint8_t rotationConstant, vImagePixelCount dx, vImagePixelCount dy,
                                     vImagePixelCount width, vImagePixelCount height)
{
    CharonTurn found;
    switch (rotationConstant) {
    case 0:  found.sourceRow = dy;            found.sourceColumn = dx;               break;
    case 1:  found.sourceRow = dx;            found.sourceColumn = width - 1 - dy;   break;
    case 2:  found.sourceRow = height - 1 - dy; found.sourceColumn = width - 1 - dx; break;
    default: found.sourceRow = height - 1 - dx; found.sourceColumn = dy;             break;
    }
    found.inside = (found.sourceRow < height && found.sourceColumn < width) ? 1 : 0;
    return found;
}

// The refusals: a constant outside the four the header names, and a NULL buffer.
//
// **There is no flag check, and that is measured rather than assumed.** The header lists four flags for the
// geometry functions - `kvImageEdgeExtend`, `kvImageBackgroundColorFill`, `kvImageDoNotTile` and
// `kvImageNoFlags` - and it is tempting to refuse anything else. The system does not: every one of the
// thirty-two bits, passed on its own to `vImageRotate90_ARGB16U`, comes back `kvImageNoError`, including
// `0x40000000` and `kvImageGetTempBufferSize`. Per COORDINATION section 5 the system wins, so this function
// refuses nothing on a flag, and the flags that mean something to it are honoured where they mean something:
// `kvImageBackgroundColorFill` and `kvImageEdgeExtend` are the two edging modes, and every other bit is
// carried and ignored. Refusing a flag here would be a refusal the system never makes.
static inline vImage_Error charon_turn_ready(const vImage_Buffer *src, const vImage_Buffer *dest,
                                             uint8_t rotationConstant)
{
    if (rotationConstant > 3)
        return kvImageInvalidParameter;
    if (!src || !dest)
        return kvImageNullPointerArgument;
    return kvImageNoError;
}

// The loop, over a pixel of `bytes` per sample.
//
// A quarter turn does not change a picture's shape and a half turn does not either; the two quarter turns
// swap it, so the *turned* picture is `W x H` for constants 0 and 2 and `H x W` for 1 and 3. When the
// destination is the size the constant wants the two are the same and nothing is placed anywhere. When it
// is not - and it is not an error, the system answers it - the turned picture is **centred** in the
// destination, so the offset is `(destination minus turned) / 2` on each axis and a destination pixel that
// falls outside the turned picture is the backColor. That is the whole of the mismatched case, and it is
// what the twelve-shape differential measures: for a 1x7 source into a 1x7 destination under constant 3
// the turned picture is seven wide and one tall, the offset is (-3, 3), and the system answers the backColor
// on the top three rows exactly as this does.
static inline vImage_Error charon_turn_run(const vImage_Buffer *src, const vImage_Buffer *dest,
                                           uint8_t rotationConstant, const void *backColor, size_t bytes,
                                           vImage_Flags flags)
{
    vImagePixelCount width = src->width, height = src->height;
    int quarter = (rotationConstant == 1 || rotationConstant == 3);
    vImagePixelCount turnedWidth = quarter ? height : width;
    vImagePixelCount turnedHeight = quarter ? width : height;
    // Truncated toward zero, which is what the mismatched-destination cases with an EVEN difference want -
    // 6x4 into 6x4 under constant 1, 5x3 into 5x3, 4x6: the differential passes every one of them here. It
    // is not the rule for an ODD difference - every shape whose two extents differ by an odd number fails,
    // 2x3, 3x2, 3x4, 4x3 and 6x5, and flooring the half pixel does not fix them either, so the half pixel
    // is not being rounded at all. What the system does with a half pixel is the one measurement this
    // family still needs, and facts/Accelerate/vImageGeometry.md names it.
    long offsetX = ((long)dest->width - (long)turnedWidth) / 2;
    long offsetY = ((long)dest->height - (long)turnedHeight) / 2;
    int extend = (flags & kvImageEdgeExtend) ? 1 : 0;
    for (vImagePixelCount dy = 0; dy < dest->height; dy++) {
        uint8_t *out = (uint8_t *)dest->data + (size_t)dy * dest->rowBytes;
        for (vImagePixelCount dx = 0; dx < dest->width; dx++) {
            long tx = (long)dx - offsetX, ty = (long)dy - offsetY;
            CharonTurn from;
            const uint8_t *pixel;
            if (tx < 0 || ty < 0 || (vImagePixelCount)tx >= turnedWidth || (vImagePixelCount)ty >= turnedHeight) {
                if (!extend) {
                    memcpy(out + (size_t)dx * bytes, backColor, bytes);
                    continue;
                }
                // kvImageEdgeExtend is the header's own "the edge pixels of the source are extended": the
                // turned picture is pulled back inside the frame rather than back-coloured, and the sample
                // is the edge one.
                if (tx < 0) tx = 0;
                if (ty < 0) ty = 0;
                if ((vImagePixelCount)tx >= turnedWidth) tx = turnedWidth ? turnedWidth - 1 : 0;
                if ((vImagePixelCount)ty >= turnedHeight) ty = turnedHeight ? turnedHeight - 1 : 0;
            }
            from = charon_turn(rotationConstant, (vImagePixelCount)tx, (vImagePixelCount)ty, width, height);
            if (from.inside)
                pixel = (const uint8_t *)src->data + (size_t)from.sourceRow * src->rowBytes
                      + (size_t)from.sourceColumn * bytes;
            else
                pixel = (const uint8_t *)backColor;
            memcpy(out + (size_t)dx * bytes, pixel, bytes);
        }
    }
    return kvImageNoError;
}
