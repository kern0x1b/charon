// The port's thirty-six shears against the host's own thirty-six, case by case, and both against an
// expectation this file computes for itself.
//
// Three answers per case, and all three compared byte for byte:
//   1. the host's own `vImageHorizontalShear_...`, called by name, out of this Mac's Accelerate;
//   2. the port's function of the same name, built from the package's objects with the package's own
//      -Os -Wall line (run.sh) and renamed so that it can be called here beside the host's (run.sh);
//   3. **this file's own loops**, written from the mapping the facts page records and NOT from the port's
//      engine: the Lanczos kernel, the two position rules, the two edging modes and the per-type clamp, all
//      re-derived here. A harness that asked the port what the port should have answered would pass a port
//      that is wrong in the same way twice, and one that only compared the two implementations would pass a
//      pair that had drifted from the release together.
//
// Every byte of every destination row is compared, including the padding past the destination's own width,
// which is filled with a guard first, so a write past the width is a difference and not an overrun. A shear
// COMPUTES a value rather than moving bytes, so the comparison is exact on the stored type and not a
// tolerance: the port and the host both accumulate in double and the question is whether they store the same
// number.
//
// The NULL arguments are handed over through variables and never written as literals: the declarations carry
// VIMAGE_NON_NULL, so a literal NULL is a front-end diagnostic and a call through a variable is the only way
// to ask the question at all.
#import <Foundation/Foundation.h>
#import <Accelerate/Accelerate.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// The port's own filter layout, so the harness can hand the port a filter it will read: CharonShear.h refuses a
// buffer that is not one of the port's, which is exactly what a host filter is. The scale and the flag are the
// same on both sides, so the two filters describe the same kernel.
#include "CharonResampling.h"

static int checks, failures;

// One of the thirty-six: the layout, how a channel is stored and clamped, and the two thunks that call it -
// the host's by name, and the port's under the `charon_host_` name run.sh's -D rename gives it. `scalar` says
// the header's pixel is a scalar, so the parameter is a value and not an array.
typedef struct {
    const char *name;
    int horizontal, channels, bytes, isHalf, isSigned, packed, translateIsDouble, scalar;
    double peak;
    unsigned acceptedFlags;   // the bits of the flag word the release takes, measured by surveyFlags() below
    vImage_Error (*host)(const vImage_Buffer *, const vImage_Buffer *, vImagePixelCount, vImagePixelCount,
                         double, double, ResamplingFilter, const void *, vImage_Flags);
    vImage_Error (*port)(const vImage_Buffer *, const vImage_Buffer *, vImagePixelCount, vImagePixelCount,
                         double, double, ResamplingFilter, const void *, vImage_Flags);
} Shear;

// The header's array pixel types decay to a pointer in the parameter, so the thunk casts to the
// element type rather than to the array type, which is not a type a cast can produce.
#define ARRAY_BACK(ELEMENT) ((const ELEMENT *)back)
#define SCALAR_BACK(TYPE) (*(const TYPE *)back)
#define HOST_THUNK(NAME, PIXEL, BACK, T)                                                            \
    static vImage_Error host_##NAME(const vImage_Buffer *s, const vImage_Buffer *d, vImagePixelCount ox, \
                                    vImagePixelCount oy, double t, double m, ResamplingFilter f,       \
                                    const void *back, vImage_Flags fl)                              \
    { return NAME(s, d, ox, oy, (T)t, (T)m, f, BACK, fl); }
#define PORT_THUNK(NAME, PIXEL, BACK, T)                                                            \
    static vImage_Error port_##NAME(const vImage_Buffer *s, const vImage_Buffer *d, vImagePixelCount ox, \
                                    vImagePixelCount oy, double t, double m, ResamplingFilter f,       \
                                    const void *back, vImage_Flags fl)                              \
    { return charon_host_##NAME(s, d, ox, oy, (T)t, (T)m, f, BACK, fl); }

#define DECLARE(NAME, PIXEL, BACK, T) \
    vImage_Error charon_host_##NAME(const vImage_Buffer *, const vImage_Buffer *, vImagePixelCount, \
                                    vImagePixelCount, T, T, ResamplingFilter, const PIXEL, vImage_Flags)

DECLARE(vImageHorizontalShearD_ARGB16S, Pixel_ARGB_16S, , double);
DECLARE(vImageHorizontalShearD_ARGB16U, Pixel_ARGB_16U, , double);
DECLARE(vImageHorizontalShear_ARGB16S, Pixel_ARGB_16S, , float);
DECLARE(vImageHorizontalShear_ARGB16U, Pixel_ARGB_16U, , float);
DECLARE(vImageVerticalShearD_ARGB16S, Pixel_ARGB_16S, , double);
DECLARE(vImageVerticalShearD_ARGB16U, Pixel_ARGB_16U, , double);
DECLARE(vImageVerticalShear_ARGB16S, Pixel_ARGB_16S, , float);
DECLARE(vImageVerticalShear_ARGB16U, Pixel_ARGB_16U, , float);
DECLARE(vImageHorizontalShear_Planar16S, Pixel_16S, , float);
DECLARE(vImageHorizontalShear_Planar16U, Pixel_16U, , float);
DECLARE(vImageVerticalShear_Planar16S, Pixel_16S, , float);
DECLARE(vImageVerticalShear_Planar16U, Pixel_16U, , float);
DECLARE(vImageHorizontalShear_CbCr16U, Pixel_16U16U, , float);
DECLARE(vImageHorizontalShear_CbCr8, Pixel_88, , float);
DECLARE(vImageHorizontalShear_XRGB2101010W, Pixel_32U, , float);
DECLARE(vImageVerticalShear_CbCr16U, Pixel_16U16U, , float);
DECLARE(vImageVerticalShear_CbCr8, Pixel_88, , float);
DECLARE(vImageVerticalShear_XRGB2101010W, Pixel_32U, , float);
DECLARE(vImageHorizontalShearD_ARGB16F, Pixel_ARGB_16F, , double);
DECLARE(vImageHorizontalShearD_CbCr16F, Pixel_16F16F, , double);
DECLARE(vImageHorizontalShearD_CbCr16S, Pixel_16S16S, , double);
DECLARE(vImageHorizontalShearD_CbCr16U, Pixel_16U16U, , double);
DECLARE(vImageHorizontalShearD_Planar16F, Pixel_16F, , double);
DECLARE(vImageHorizontalShear_ARGB16F, Pixel_ARGB_16F, , float);
DECLARE(vImageHorizontalShear_CbCr16F, Pixel_16F16F, , float);
DECLARE(vImageHorizontalShear_CbCr16S, Pixel_16S16S, , float);
DECLARE(vImageHorizontalShear_Planar16F, Pixel_16F, , float);
DECLARE(vImageVerticalShearD_ARGB16F, Pixel_ARGB_16F, , double);
DECLARE(vImageVerticalShearD_CbCr16F, Pixel_16F16F, , double);
DECLARE(vImageVerticalShearD_CbCr16S, Pixel_16S16S, , double);
DECLARE(vImageVerticalShearD_CbCr16U, Pixel_16U16U, , double);
DECLARE(vImageVerticalShearD_Planar16F, Pixel_16F, , double);
DECLARE(vImageVerticalShear_ARGB16F, Pixel_ARGB_16F, , float);
DECLARE(vImageVerticalShear_CbCr16F, Pixel_16F16F, , float);
DECLARE(vImageVerticalShear_CbCr16S, Pixel_16S16S, , float);
DECLARE(vImageVerticalShear_Planar16F, Pixel_16F, , float);

HOST_THUNK(vImageHorizontalShearD_ARGB16S, Pixel_ARGB_16S, ARRAY_BACK(int16_t), double)
PORT_THUNK(vImageHorizontalShearD_ARGB16S, Pixel_ARGB_16S, ARRAY_BACK(int16_t), double)
HOST_THUNK(vImageHorizontalShearD_ARGB16U, Pixel_ARGB_16U, ARRAY_BACK(uint16_t), double)
PORT_THUNK(vImageHorizontalShearD_ARGB16U, Pixel_ARGB_16U, ARRAY_BACK(uint16_t), double)
HOST_THUNK(vImageHorizontalShear_ARGB16S, Pixel_ARGB_16S, ARRAY_BACK(int16_t), float)
PORT_THUNK(vImageHorizontalShear_ARGB16S, Pixel_ARGB_16S, ARRAY_BACK(int16_t), float)
HOST_THUNK(vImageHorizontalShear_ARGB16U, Pixel_ARGB_16U, ARRAY_BACK(uint16_t), float)
PORT_THUNK(vImageHorizontalShear_ARGB16U, Pixel_ARGB_16U, ARRAY_BACK(uint16_t), float)
HOST_THUNK(vImageVerticalShearD_ARGB16S, Pixel_ARGB_16S, ARRAY_BACK(int16_t), double)
PORT_THUNK(vImageVerticalShearD_ARGB16S, Pixel_ARGB_16S, ARRAY_BACK(int16_t), double)
HOST_THUNK(vImageVerticalShearD_ARGB16U, Pixel_ARGB_16U, ARRAY_BACK(uint16_t), double)
PORT_THUNK(vImageVerticalShearD_ARGB16U, Pixel_ARGB_16U, ARRAY_BACK(uint16_t), double)
HOST_THUNK(vImageVerticalShear_ARGB16S, Pixel_ARGB_16S, ARRAY_BACK(int16_t), float)
PORT_THUNK(vImageVerticalShear_ARGB16S, Pixel_ARGB_16S, ARRAY_BACK(int16_t), float)
HOST_THUNK(vImageVerticalShear_ARGB16U, Pixel_ARGB_16U, ARRAY_BACK(uint16_t), float)
PORT_THUNK(vImageVerticalShear_ARGB16U, Pixel_ARGB_16U, ARRAY_BACK(uint16_t), float)

HOST_THUNK(vImageHorizontalShear_Planar16S, Pixel_16S, SCALAR_BACK(int16_t), float)
PORT_THUNK(vImageHorizontalShear_Planar16S, Pixel_16S, SCALAR_BACK(int16_t), float)
HOST_THUNK(vImageHorizontalShear_Planar16U, Pixel_16U, SCALAR_BACK(uint16_t), float)
PORT_THUNK(vImageHorizontalShear_Planar16U, Pixel_16U, SCALAR_BACK(uint16_t), float)
HOST_THUNK(vImageVerticalShear_Planar16S, Pixel_16S, SCALAR_BACK(int16_t), float)
PORT_THUNK(vImageVerticalShear_Planar16S, Pixel_16S, SCALAR_BACK(int16_t), float)
HOST_THUNK(vImageVerticalShear_Planar16U, Pixel_16U, SCALAR_BACK(uint16_t), float)
PORT_THUNK(vImageVerticalShear_Planar16U, Pixel_16U, SCALAR_BACK(uint16_t), float)

HOST_THUNK(vImageHorizontalShear_CbCr16U, Pixel_16U16U, ARRAY_BACK(uint16_t), float)
PORT_THUNK(vImageHorizontalShear_CbCr16U, Pixel_16U16U, ARRAY_BACK(uint16_t), float)
HOST_THUNK(vImageHorizontalShear_CbCr8, Pixel_88, ARRAY_BACK(uint8_t), float)
PORT_THUNK(vImageHorizontalShear_CbCr8, Pixel_88, ARRAY_BACK(uint8_t), float)
HOST_THUNK(vImageHorizontalShear_XRGB2101010W, Pixel_32U, SCALAR_BACK(uint32_t), float)
PORT_THUNK(vImageHorizontalShear_XRGB2101010W, Pixel_32U, SCALAR_BACK(uint32_t), float)
HOST_THUNK(vImageVerticalShear_CbCr16U, Pixel_16U16U, ARRAY_BACK(uint16_t), float)
PORT_THUNK(vImageVerticalShear_CbCr16U, Pixel_16U16U, ARRAY_BACK(uint16_t), float)
HOST_THUNK(vImageVerticalShear_CbCr8, Pixel_88, ARRAY_BACK(uint8_t), float)
PORT_THUNK(vImageVerticalShear_CbCr8, Pixel_88, ARRAY_BACK(uint8_t), float)
HOST_THUNK(vImageVerticalShear_XRGB2101010W, Pixel_32U, SCALAR_BACK(uint32_t), float)
PORT_THUNK(vImageVerticalShear_XRGB2101010W, Pixel_32U, SCALAR_BACK(uint32_t), float)

HOST_THUNK(vImageHorizontalShearD_ARGB16F, Pixel_ARGB_16F, ARRAY_BACK(uint16_t), double)
PORT_THUNK(vImageHorizontalShearD_ARGB16F, Pixel_ARGB_16F, ARRAY_BACK(uint16_t), double)
HOST_THUNK(vImageHorizontalShearD_CbCr16F, Pixel_16F16F, ARRAY_BACK(uint16_t), double)
PORT_THUNK(vImageHorizontalShearD_CbCr16F, Pixel_16F16F, ARRAY_BACK(uint16_t), double)
HOST_THUNK(vImageHorizontalShearD_CbCr16S, Pixel_16S16S, ARRAY_BACK(int16_t), double)
PORT_THUNK(vImageHorizontalShearD_CbCr16S, Pixel_16S16S, ARRAY_BACK(int16_t), double)
HOST_THUNK(vImageHorizontalShearD_CbCr16U, Pixel_16U16U, ARRAY_BACK(uint16_t), double)
PORT_THUNK(vImageHorizontalShearD_CbCr16U, Pixel_16U16U, ARRAY_BACK(uint16_t), double)
HOST_THUNK(vImageHorizontalShearD_Planar16F, Pixel_16F, SCALAR_BACK(uint16_t), double)
PORT_THUNK(vImageHorizontalShearD_Planar16F, Pixel_16F, SCALAR_BACK(uint16_t), double)
HOST_THUNK(vImageHorizontalShear_ARGB16F, Pixel_ARGB_16F, ARRAY_BACK(uint16_t), float)
PORT_THUNK(vImageHorizontalShear_ARGB16F, Pixel_ARGB_16F, ARRAY_BACK(uint16_t), float)
HOST_THUNK(vImageHorizontalShear_CbCr16F, Pixel_16F16F, ARRAY_BACK(uint16_t), float)
PORT_THUNK(vImageHorizontalShear_CbCr16F, Pixel_16F16F, ARRAY_BACK(uint16_t), float)
HOST_THUNK(vImageHorizontalShear_CbCr16S, Pixel_16S16S, ARRAY_BACK(int16_t), float)
PORT_THUNK(vImageHorizontalShear_CbCr16S, Pixel_16S16S, ARRAY_BACK(int16_t), float)
HOST_THUNK(vImageHorizontalShear_Planar16F, Pixel_16F, SCALAR_BACK(uint16_t), float)
PORT_THUNK(vImageHorizontalShear_Planar16F, Pixel_16F, SCALAR_BACK(uint16_t), float)
HOST_THUNK(vImageVerticalShearD_ARGB16F, Pixel_ARGB_16F, ARRAY_BACK(uint16_t), double)
PORT_THUNK(vImageVerticalShearD_ARGB16F, Pixel_ARGB_16F, ARRAY_BACK(uint16_t), double)
HOST_THUNK(vImageVerticalShearD_CbCr16F, Pixel_16F16F, ARRAY_BACK(uint16_t), double)
PORT_THUNK(vImageVerticalShearD_CbCr16F, Pixel_16F16F, ARRAY_BACK(uint16_t), double)
HOST_THUNK(vImageVerticalShearD_CbCr16S, Pixel_16S16S, ARRAY_BACK(int16_t), double)
PORT_THUNK(vImageVerticalShearD_CbCr16S, Pixel_16S16S, ARRAY_BACK(int16_t), double)
HOST_THUNK(vImageVerticalShearD_CbCr16U, Pixel_16U16U, ARRAY_BACK(uint16_t), double)
PORT_THUNK(vImageVerticalShearD_CbCr16U, Pixel_16U16U, ARRAY_BACK(uint16_t), double)
HOST_THUNK(vImageVerticalShearD_Planar16F, Pixel_16F, SCALAR_BACK(uint16_t), double)
PORT_THUNK(vImageVerticalShearD_Planar16F, Pixel_16F, SCALAR_BACK(uint16_t), double)
HOST_THUNK(vImageVerticalShear_ARGB16F, Pixel_ARGB_16F, ARRAY_BACK(uint16_t), float)
PORT_THUNK(vImageVerticalShear_ARGB16F, Pixel_ARGB_16F, ARRAY_BACK(uint16_t), float)
HOST_THUNK(vImageVerticalShear_CbCr16F, Pixel_16F16F, ARRAY_BACK(uint16_t), float)
PORT_THUNK(vImageVerticalShear_CbCr16F, Pixel_16F16F, ARRAY_BACK(uint16_t), float)
HOST_THUNK(vImageVerticalShear_CbCr16S, Pixel_16S16S, ARRAY_BACK(int16_t), float)
PORT_THUNK(vImageVerticalShear_CbCr16S, Pixel_16S16S, ARRAY_BACK(int16_t), float)
HOST_THUNK(vImageVerticalShear_Planar16F, Pixel_16F, SCALAR_BACK(uint16_t), float)
PORT_THUNK(vImageVerticalShear_Planar16F, Pixel_16F, SCALAR_BACK(uint16_t), float)

// The table. `peak` is the largest value a source channel may carry for this layout, chosen so that no
// channel ever clips: the test is about the mapping, and a clipped source would hide a wrong weight behind a
// saturated sum. The 8-bit form's peak is 255 because that is its whole range, so its ramp is small and its
// values distinct instead.
static const Shear shears[] = {
#define ENTRY(NAME, H, C, B, HALF, SIGNED, PACKED, T, SCALAR, PEAK, FLAGS) \
    { #NAME, H, C, B, HALF, SIGNED, PACKED, T, SCALAR, PEAK, FLAGS, host_##NAME, port_##NAME }
    ENTRY(vImageHorizontalShearD_ARGB16S, 1, 4, 2, 0, 1, 0, 1, 0, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageHorizontalShearD_ARGB16U, 1, 4, 2, 0, 0, 0, 1, 0, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageHorizontalShear_ARGB16S, 1, 4, 2, 0, 1, 0, 0, 0, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageHorizontalShear_ARGB16U, 1, 4, 2, 0, 0, 0, 0, 0, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageVerticalShearD_ARGB16S, 0, 4, 2, 0, 1, 0, 1, 0, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageVerticalShearD_ARGB16U, 0, 4, 2, 0, 0, 0, 1, 0, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageVerticalShear_ARGB16S, 0, 4, 2, 0, 1, 0, 0, 0, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageVerticalShear_ARGB16U, 0, 4, 2, 0, 0, 0, 0, 0, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageHorizontalShear_Planar16S, 1, 1, 2, 0, 1, 0, 0, 1, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageHorizontalShear_Planar16U, 1, 1, 2, 0, 0, 0, 0, 1, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageVerticalShear_Planar16S, 0, 1, 2, 0, 1, 0, 0, 1, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageVerticalShear_Planar16U, 0, 1, 2, 0, 0, 0, 0, 1, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageHorizontalShear_CbCr16U, 1, 2, 2, 0, 0, 0, 0, 0, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageHorizontalShear_CbCr8, 1, 2, 1, 0, 0, 0, 0, 0, 255.0, 0xFFFFFFFFu),
    ENTRY(vImageHorizontalShear_XRGB2101010W, 1, 4, 0, 0, 0, 1, 0, 1, 1023.0, 0xFFFFFFFFu),
    ENTRY(vImageVerticalShear_CbCr16U, 0, 2, 2, 0, 0, 0, 0, 0, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageVerticalShear_CbCr8, 0, 2, 1, 0, 0, 0, 0, 0, 255.0, 0xFFFFFFFFu),
    ENTRY(vImageVerticalShear_XRGB2101010W, 0, 4, 0, 0, 0, 1, 0, 1, 1023.0, 0xFFFFFFFFu),
    ENTRY(vImageHorizontalShearD_ARGB16F, 1, 4, 0, 1, 0, 0, 1, 0, 3.0, 0x000011bcu),
    ENTRY(vImageHorizontalShearD_CbCr16F, 1, 2, 0, 1, 0, 0, 1, 0, 3.0, 0x000011bcu),
    ENTRY(vImageHorizontalShearD_CbCr16S, 1, 2, 2, 0, 1, 0, 1, 0, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageHorizontalShearD_CbCr16U, 1, 2, 2, 0, 0, 0, 1, 0, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageHorizontalShearD_Planar16F, 1, 1, 0, 1, 0, 0, 1, 1, 3.0, 0x000011bcu),
    ENTRY(vImageHorizontalShear_ARGB16F, 1, 4, 0, 1, 0, 0, 0, 0, 3.0, 0x000011bcu),
    ENTRY(vImageHorizontalShear_CbCr16F, 1, 2, 0, 1, 0, 0, 0, 0, 3.0, 0x000011bcu),
    ENTRY(vImageHorizontalShear_CbCr16S, 1, 2, 2, 0, 1, 0, 0, 0, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageHorizontalShear_Planar16F, 1, 1, 0, 1, 0, 0, 0, 1, 3.0, 0x000011bcu),
    ENTRY(vImageVerticalShearD_ARGB16F, 0, 4, 0, 1, 0, 0, 1, 0, 3.0, 0x000011bcu),
    ENTRY(vImageVerticalShearD_CbCr16F, 0, 2, 0, 1, 0, 0, 1, 0, 3.0, 0x000011bcu),
    ENTRY(vImageVerticalShearD_CbCr16S, 0, 2, 2, 0, 1, 0, 1, 0, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageVerticalShearD_CbCr16U, 0, 2, 2, 0, 0, 0, 1, 0, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageVerticalShearD_Planar16F, 0, 1, 0, 1, 0, 0, 1, 1, 3.0, 0x000011bcu),
    ENTRY(vImageVerticalShear_ARGB16F, 0, 4, 0, 1, 0, 0, 0, 0, 3.0, 0x000011bcu),
    ENTRY(vImageVerticalShear_CbCr16F, 0, 2, 0, 1, 0, 0, 0, 0, 3.0, 0x000011bcu),
    ENTRY(vImageVerticalShear_CbCr16S, 0, 2, 2, 0, 1, 0, 0, 0, 30000.0, 0xFFFFFFFFu),
    ENTRY(vImageVerticalShear_Planar16F, 0, 1, 0, 1, 0, 0, 0, 1, 3.0, 0x000011bcu),
#undef ENTRY
};
static const int shearCount = (int)(sizeof shears / sizeof *shears);

// Half precision, packed and unpacked HERE rather than through the port's header, so the expectation does not
// share a conversion with the thing it is checking.
static uint16_t packHalf(double value)
{
    uint32_t bits;
    double magnitude = fabs(value);
    if (magnitude >= 65520.0) {
        bits = 0x7BFF;                                   // the largest finite half, and every infinity above it
    } else if (magnitude < 6.103515625e-05) {
        double scaled = magnitude / 5.9604644775390625e-08;   // the smallest subnormal is 2^-24
        uint32_t mantissa = (uint32_t)(scaled + 0.5);
        bits = mantissa > 1023 ? 1023 : mantissa;
    } else {
        int exponent = 0;
        double scaled = magnitude;
        while (scaled >= 2.0) { scaled /= 2.0; exponent++; }
        while (scaled < 1.0) { scaled *= 2.0; exponent--; }
        uint32_t round = (uint32_t)((scaled - 1.0) * 1024.0 + 0.5);
        uint32_t exponentField = (uint32_t)(exponent + 15);
        if (round >= 1024) { round = 0; exponentField++; }
        bits = exponentField >= 31 ? 0x7C00u : ((exponentField << 10) | round);
    }
    return (uint16_t)((value < 0.0) ? (bits | 0x8000u) : bits);
}

static double unpackHalf(uint16_t bits)
{
    uint32_t exponent = (bits >> 10) & 0x1Fu, mantissa = bits & 0x3FFu;
    double value;
    if (exponent == 0) value = (double)mantissa * 5.9604644775390625e-08;
    else if (exponent == 31) value = mantissa ? 0.0 / 0.0 : 1.0 / 0.0;
    else value = ldexp((double)(mantissa + 1024) / 1024.0, (int)exponent - 15);
    return (bits & 0x8000u) ? -value : value;
}

static size_t bytesPerPixel(const Shear *shear)
{
    if (shear->packed) return 4;
    if (shear->isHalf) return (size_t)shear->channels * 2;
    return (size_t)shear->channels * (size_t)shear->bytes;
}

static double loadChannel(const void *pixel, unsigned channel, const Shear *shear)
{
    if (shear->isHalf) return unpackHalf(((const uint16_t *)pixel)[channel]);
    switch (shear->bytes) {
    case 1: return (double)((const uint8_t *)pixel)[channel];
    case 2: return shear->isSigned ? (double)((const int16_t *)pixel)[channel]
                                   : (double)((const uint16_t *)pixel)[channel];
    default: break;
    }
    return (double)((*((const uint32_t *)pixel) >> (channel * 10)) & 0x3FFu);
}

static double clampChannel(double value, int isSigned, int bytes)
{
    if (bytes == 1) return value < 0.0 ? 0.0 : (value > 255.0 ? 255.0 : value);
    if (isSigned) return value < -32768.0 ? -32768.0 : (value > 32767.0 ? 32767.0 : value);
    return value < 0.0 ? 0.0 : (value > 65535.0 ? 65535.0 : value);
}

static void storeChannel(void *pixel, unsigned channel, double value, const Shear *shear)
{
    if (shear->isHalf) {
        ((uint16_t *)pixel)[channel] = packHalf(value);
        return;
    }
    switch (shear->bytes) {
    case 1: ((uint8_t *)pixel)[channel] = (uint8_t)clampChannel(value, 0, 1); return;
    case 2:
        if (shear->isSigned) ((int16_t *)pixel)[channel] = (int16_t)clampChannel(value, 1, 2);
        else ((uint16_t *)pixel)[channel] = (uint16_t)clampChannel(value, 0, 2);
        return;
    default: break;
    }
    uint32_t word = *(uint32_t *)pixel, shift = channel * 10;
    word = (word & ~(0x3FFu << shift)) | (((uint32_t)clampChannel(value, 0, 2) & 0x3FFu) << shift);
    *(uint32_t *)pixel = word;
}

// The kernel and the mapping, written here from the measurement. Nothing below is taken from the port.
static double sincOf(double x)
{
    if (x == 0.0) return 1.0;
    return sin(M_PI * x) / (M_PI * x);
}

static double lanczos(double x, double lobes)
{
    if (x <= -lobes || x >= lobes) return 0.0;
    return sincOf(x) * sincOf(x / lobes);
}

// One destination sample: the tap walk, the two edging modes, and the per-phase normalisation. `first` and
// `taps` come in so the tap window is computed once per sample rather than per channel.
static double expectSample(const Shear *shear, const uint8_t *srcRow, size_t srcStep, vImagePixelCount srcAlong,
                           int extent, int lobes, float scale, int extend, const double *back, unsigned channel,
                           double centre, int first, int taps)
{
    double weights[1024], total = 0.0, sum = 0.0;
    for (int k = 0; k < taps; k++) {
        // The distance from the MAPPED POSITION, fractional part and all. An earlier version took it from the
        // tap index alone, which silently computed every sample at the phase of the nearest whole pixel - so
        // the identity, the only case whose centre is a whole pixel, was the only case that agreed.
        double distance = ((double)(first + k) - centre) * (scale < 1.0f ? (double)scale : 1.0);
        weights[k] = lanczos(distance, lobes);
        total += weights[k];
    }
    if (total == 0.0) return back[channel];
    for (int k = 0; k < taps; k++) {
        long at = first + k;
        double weight = weights[k] / total;
        // A tap outside the picture keeps its weight and takes the backColor, which is the header's
        // kvImageBackgroundColorFill read literally, or the edge element under kvImageEdgeExtend.
        double value;
        if (at < 0 || at >= (long)srcAlong) {
            if (!extend) value = back[channel];
            else value = loadChannel(srcRow + (size_t)(at < 0 ? 0 : (long)srcAlong - 1) * srcStep, channel, shear);
        } else {
            value = loadChannel(srcRow + (size_t)at * srcStep, channel, shear);
        }
        sum += weight * value;
    }
    return sum;
}

// The whole expected destination, from this file's own loops.
static void expectDestination(const Shear *shear, const vImage_Buffer *src, const vImage_Buffer *dest,
                              vImagePixelCount along0, vImagePixelCount cross0, double translate, double slope,
                              float scale, int lobes, int extend, const double *back, vImage_Buffer *out)
{
    vImagePixelCount srcAlong = shear->horizontal ? src->width : src->height;
    vImagePixelCount dstAlong = shear->horizontal ? dest->width : dest->height;
    vImagePixelCount dstCross = shear->horizontal ? dest->height : dest->width;
    int extent = (int)ceil((double)lobes / (scale < 1.0f ? (double)scale : 1.0) - 1.0e-4);
    int taps = 2 * extent + 1;
    size_t pixelBytes = bytesPerPixel(shear);
    for (vImagePixelCount cross = 0; cross < dstCross; cross++) {
        long sourceCross = (long)cross0 + (long)cross;
        // The base of the run of taps: a row for the horizontal and a column for the vertical, and the tap
        // walk steps by `src->rowBytes` from there.
        const uint8_t *srcRow = shear->horizontal
                                    ? (const uint8_t *)src->data + (size_t)sourceCross * src->rowBytes
                                    : (const uint8_t *)src->data + (size_t)sourceCross * pixelBytes;
        for (vImagePixelCount along = 0; along < dstAlong; along++) {
            double edge = shear->horizontal ? (double)dstCross - (double)cross : (double)cross + 1.0;
            double alongPosition = (double)(along0 + along) + 0.5
                                   + (shear->horizontal ? -translate : translate)
                                   + (shear->horizontal ? -slope : slope) * (edge - 0.5);
            double centre = shear->horizontal
                                ? alongPosition / (double)scale - 0.5
                                : (double)dstAlong + (alongPosition - (double)dstAlong) / (double)scale - 0.5;
            int first = (int)floor(centre) - extent;
            uint8_t *pixel = shear->horizontal
                                 ? (uint8_t *)out->data + (size_t)cross * out->rowBytes + (size_t)along * pixelBytes
                                 : (uint8_t *)out->data + (size_t)along * out->rowBytes + (size_t)cross * pixelBytes;
            for (unsigned channel = 0; channel < (unsigned)shear->channels; channel++) {
                double sample = expectSample(shear, srcRow,
                                          shear->horizontal ? pixelBytes : src->rowBytes, srcAlong, extent, lobes,
                                          scale, extend, back, channel, centre, first, taps);
                storeChannel(pixel, channel, sample, shear);
            }
        }
    }
}

// The buffers, filled with a guard so a write past the destination's own width is a difference.
#define GUARD 0xA5

static vImage_Buffer makeBuffer(vImagePixelCount width, vImagePixelCount height, size_t pixelBytes, size_t pad)
{
    vImage_Buffer b = {0};
    b.width = width;
    b.height = height;
    b.rowBytes = width * pixelBytes + pad;
    b.data = malloc((size_t)b.rowBytes * height);
    memset(b.data, GUARD, (size_t)b.rowBytes * height);
    return b;
}

// A source whose every channel is distinct and inside the layout's range, so a wrong weight cannot hide
// behind a saturated sum and no two pixels are alike.
static void fillSource(vImage_Buffer *src, const Shear *shear)
{
    size_t pixelBytes = bytesPerPixel(shear);
    for (vImagePixelCount row = 0; row < src->height; row++)
        for (vImagePixelCount column = 0; column < src->width; column++) {
            uint8_t *pixel = (uint8_t *)src->data + (size_t)row * src->rowBytes + (size_t)column * pixelBytes;
            for (unsigned channel = 0; channel < (unsigned)shear->channels; channel++) {
                double value = 1.0 + (double)((row * 7 + column * 13 + channel * 29) % 61) * (shear->peak / 61.0);
                storeChannel(pixel, channel, value, shear);
            }
        }
}

// The backColor in the parameter's own storage, and in the engine's own scale.
static void fillBackColor(const Shear *shear, void *back, double *backScale)
{
    for (unsigned channel = 0; channel < 4; channel++) {
        double value = channel < (unsigned)shear->channels ? -(0.5 + 0.25 * channel) : 0.0;
        backScale[channel] = value;
        if (channel < (unsigned)shear->channels) storeChannel(back, channel, value, shear);
    }
    // The engine reads `backColor[channel]` as a double of the stored value, so the scalar and packed forms
    // are unpacked the way CharonShear.h's readers unpack them.
    for (unsigned channel = 0; channel < (unsigned)shear->channels; channel++)
        backScale[channel] = loadChannel(back, channel, shear);
}

// Whether two whole buffers are byte for byte equal, and if they are not, where the first difference is. It
// RETURNS the answer rather than leaving it in the message: a version of this that only wrote a sentence and
// let the caller test the sentence's first letter could not fail, and the second red control - the vertical's
// far-edge anchor planted away - came back green because of it. The check is the return value.
static int sameBuffer(char *into, size_t n, const char *prefix, const uint8_t *a, const uint8_t *b,
                      const vImage_Buffer *buffer, const char *what)
{
    size_t total = (size_t)buffer->rowBytes * buffer->height;
    for (size_t at = 0; at < total; at++) {
        if (a[at] == b[at]) continue;
        snprintf(into, n, "%s at byte %zu of a %ux%u buffer, %g against %g (%s)", prefix, at, (unsigned)buffer->width,
                 (unsigned)buffer->height, (double)a[at], (double)b[at], what);
        return 0;
    }
    snprintf(into, n, "%s, and the buffers are byte for byte equal", prefix);
    return 1;
}

static void one(const Shear *shear, vImagePixelCount srcW, vImagePixelCount srcH, vImagePixelCount dstW,
                vImagePixelCount dstH, vImagePixelCount along0, vImagePixelCount cross0, double translate,
                double slope, float scale, vImage_Flags flags, int lobes, const char *label)
{
    size_t pixelBytes = bytesPerPixel(shear);
    // The padding past the width, so a write past it is a difference - and EVEN, because an odd one starts every
    // second row at an odd address and a sixteen-bit shape then takes a misaligned store, which
    // UndefinedBehaviorSanitizer names in the port's own header and which has nothing to do with the port.
    size_t pad = pixelBytes + 3;
    if (pad % 2) pad++;
    vImage_Buffer src = makeBuffer(srcW, srcH, pixelBytes, 0), theirDest = makeBuffer(dstW, dstH, pixelBytes, pad),
                 ourDest = makeBuffer(dstW, dstH, pixelBytes, pad), mine = makeBuffer(dstW, dstH, pixelBytes, pad);
    fillSource(&src, shear);
    uint8_t back[8];
    memset(back, 0, sizeof back);
    double backScale[4];
    fillBackColor(shear, back, backScale);

    ResamplingFilter theirFilter = vImageNewResamplingFilter(scale, (flags & kvImageHighQualityResampling));
    vImage_Error theirs = shear->host(&src, &theirDest, along0, cross0, translate, slope, theirFilter, back, flags);
    vImageDestroyResamplingFilter(theirFilter);

    CharonResampleFilter portFilter;
    CharonResampleFilterInit(&portFilter, scale, flags);
    vImage_Error ours = shear->port(&src, &ourDest, along0, cross0, translate, slope, &portFilter, back, flags);

    static int dumped = 0;
    char what[256], note[320];
    snprintf(what, sizeof what, "%s %s %ux%u into %ux%u offsets %u,%u translate %g slope %g scale %g flags 0x%x",
             shear->name, label, (unsigned)srcW, (unsigned)srcH, (unsigned)dstW, (unsigned)dstH,
             (unsigned)along0, (unsigned)cross0, translate, slope, (double)scale, (unsigned)flags);

    checks++;
    if (theirs != ours) {
        failures++;
        printf("FAIL %s: the host answers %ld and the port %ld\n", what, (long)theirs, (long)ours);
    }
    if (theirs != kvImageNoError) {
        // The expectation is NOT computed for a refused case, and AddressSanitizer says why it must not be:
        // the release refuses a destination whose across extent exceeds the source's, so this harness's own
        // walk would name a source row that does not exist and read past the caller's buffer.
        //
        // A refused case writes nothing on either side, and the guards must still be intact: the whole
        // destination is the guard byte, on both sides.
        if (!sameBuffer(note, sizeof note, "the case was refused and one side wrote over the guard",
                        (const uint8_t *)theirDest.data, (const uint8_t *)ourDest.data, &theirDest,
                        "host against port")) {
            failures++;
            printf("FAIL %s: %s\n", what, note);
        }
        free(src.data); free(theirDest.data); free(ourDest.data); free(mine.data);
        return;
    }
    // DUMP=1 prints the first row of all three answers for the first few divergences, which is what says WHERE
    // two of them part company; the byte offset alone does not.
    expectDestination(shear, &src, &theirDest, along0, cross0, translate, slope, scale, lobes,
                      (flags & kvImageEdgeExtend) ? 1 : 0, backScale, &mine);

    if (!sameBuffer(note, sizeof note, "the port and the host differ",
                    (const uint8_t *)theirDest.data, (const uint8_t *)ourDest.data, &theirDest,
                    "host against port")) {
        failures++;
        printf("FAIL %s: %s\n", what, note);
        if (getenv("DUMP") && dumped < 3) {
            dumped++;
            for (int side = 0; side < 3; side++) {
                const vImage_Buffer *buffer = side == 0 ? &theirDest : (side == 1 ? &ourDest : &mine);
                for (vImagePixelCount r = 0; r < buffer->height; r++) {
                    printf("      %-5s row %u:", side == 0 ? "host" : (side == 1 ? "port" : "loops"),
                           (unsigned)r);
                    for (vImagePixelCount c = 0; c < buffer->width; c++)
                        printf(" %6ld", (long)loadChannel((const uint8_t *)buffer->data
                                                          + (size_t)r * buffer->rowBytes + (size_t)c * pixelBytes,
                                                          0, shear));
                    printf("\n");
                }
            }
        }
    }
    if (!sameBuffer(note, sizeof note, "the port and this file's own loops differ",
                    (const uint8_t *)theirDest.data, (const uint8_t *)mine.data, &theirDest,
                    "host against expectation")) {
        failures++;
        printf("FAIL %s: %s\n", what, note);
    }
    if (!sameBuffer(note, sizeof note, "the host and this file's own loops differ",
                    (const uint8_t *)ourDest.data, (const uint8_t *)mine.data, &ourDest,
                    "port against expectation")) {
        failures++;
        printf("FAIL %s: %s\n", what, note);
    }
    free(src.data); free(theirDest.data); free(ourDest.data); free(mine.data);
}

// The refusals, asked of both sides through variables, because the declarations are VIMAGE_NON_NULL and a
// literal NULL would be a compile-time diagnostic instead of a question.
static void refusals(const Shear *shear)
{
    vImage_Buffer src = makeBuffer(9, 5, bytesPerPixel(shear), 0), dest = makeBuffer(9, 5, bytesPerPixel(shear), 0);
    fillSource(&src, shear);
    uint8_t back[8];
    memset(back, 0, sizeof back);
    double backScale[4];
    fillBackColor(shear, back, backScale);
    ResamplingFilter filter = vImageNewResamplingFilter(1.0f, kvImageNoFlags);
    CharonResampleFilter portFilter;
    CharonResampleFilterInit(&portFilter, 1.0f, kvImageNoFlags);
    char what[256], note[256];

    struct { const char *name; const vImage_Buffer *src; const vImage_Buffer *dest; ResamplingFilter filter; }
    cases[] = {
        { "a NULL source", NULL, &dest, filter },
        { "a NULL destination", &src, NULL, filter },
        { "a NULL filter", &src, &dest, NULL },
    };
    for (unsigned c = 0; c < 3; c++) {
        vImage_Error theirs = shear->host(cases[c].src, cases[c].dest, 0, 0, 0.0, 0.0, cases[c].filter, back,
                                          kvImageBackgroundColorFill);
        vImage_Error ours = shear->port(cases[c].src, cases[c].dest, 0, 0, 0.0, 0.0,
                                        cases[c].filter ? &portFilter : NULL, back, kvImageBackgroundColorFill);
        checks++;
        snprintf(what, sizeof what, "%s: %s", shear->name, cases[c].name);
        if (theirs != ours) {
            failures++;
            printf("FAIL %s: the host answers %ld and the port %ld\n", what, (long)theirs, (long)ours);
        }
    }

    // The region and the shapes, stated along/across the shear and mapped onto the axis's own two offsets:
    // the horizontal's along offset is srcOffsetToROI_X and its across one srcOffsetToROI_Y, and the vertical's
    // are the other way round. `kvImageBufferSizeMismatch` is the ACROSS extent that does not fit - the region
    // offset plus the destination's across extent against the source's - and it is the only shape condition:
    // the destination's extent ALONG the shear is free, and so is the along offset.
    struct { const char *name; vImagePixelCount sa, sc, da, dc, along, cross; vImage_Error want; } shapes[] = {
        { "the region at the origin", 9, 5, 9, 5, 0, 0, kvImageNoError },
        { "an across offset of one", 9, 5, 9, 5, 0, 1, kvImageBufferSizeMismatch },
        { "an across offset of one with a destination of three", 9, 5, 9, 3, 0, 1, kvImageNoError },
        { "an across offset of three with a destination of three", 9, 5, 9, 3, 0, 3, kvImageBufferSizeMismatch },
        { "a destination wider across than the source", 9, 5, 9, 6, 0, 0, kvImageBufferSizeMismatch },
        { "a destination longer along than the source", 9, 5, 12, 5, 0, 0, kvImageNoError },
        { "an along offset of two", 9, 5, 9, 5, 2, 0, kvImageNoError },
        { "an along offset beyond the source", 9, 5, 9, 5, 12, 0, kvImageNoError },
    };
    for (unsigned c = 0; c < sizeof shapes / sizeof *shapes; c++) {
        vImagePixelCount sw = shear->horizontal ? shapes[c].sa : shapes[c].sc;
        vImagePixelCount sh = shear->horizontal ? shapes[c].sc : shapes[c].sa;
        vImagePixelCount dw = shear->horizontal ? shapes[c].da : shapes[c].dc;
        vImagePixelCount dh = shear->horizontal ? shapes[c].dc : shapes[c].da;
        vImagePixelCount ox = shear->horizontal ? shapes[c].along : shapes[c].cross;
        vImagePixelCount oy = shear->horizontal ? shapes[c].cross : shapes[c].along;
        // The source is made at THIS case's own shape, not at the one the NULL and flag cases above used: a
        // fixed 9x5 source would make every "wider across than the source" case a lie, because the
        // destination would be narrower than the buffer it is compared against.
        vImage_Buffer shaped = makeBuffer(sw, sh, bytesPerPixel(shear), 0);
        vImage_Buffer wide = makeBuffer(dw, dh, bytesPerPixel(shear), 0);
        fillSource(&shaped, shear);
        fillSource(&wide, shear);
        vImage_Error theirs = shear->host(&shaped, &wide, ox, oy, 0.0, 0.0, filter, back, kvImageBackgroundColorFill);
        vImage_Error ours = shear->port(&shaped, &wide, ox, oy, 0.0, 0.0, &portFilter, back, kvImageBackgroundColorFill);
        checks++;
        snprintf(what, sizeof what, "%s: %s", shear->name, shapes[c].name);
        snprintf(note, sizeof note, "the host answers %ld, the port %ld, and the measurement is %ld",
                 (long)theirs, (long)ours, (long)shapes[c].want);
        if (theirs != shapes[c].want || ours != shapes[c].want) {
            failures++;
            printf("FAIL %s: %s\n", what, note);
        }
        free(wide.data);
        free(shaped.data);
    }

    // Every bit of the flag word, which the shears take all of.
    for (unsigned bit = 0; bit < 32; bit++) {
        vImage_Flags flags = (vImage_Flags)1u << bit;
        vImage_Error theirs = shear->host(&src, &dest, 0, 0, 0.0, 0.0, filter, back, flags);
        vImage_Error ours = shear->port(&src, &dest, 0, 0, 0.0, 0.0, &portFilter, back, flags);
        // The expectation is the measured table, not the host's answer: a bit the function takes is
        // kvImageNoError and a bit it does not is kvImageUnknownFlagsBit.
        vImage_Error want = (shear->acceptedFlags & (1u << bit)) ? kvImageNoError : kvImageUnknownFlagsBit;
        checks++;
        if (theirs != want || ours != want) {
            failures++;
            snprintf(what, sizeof what, "%s: the flag 0x%x", shear->name, (unsigned)flags);
            snprintf(note, sizeof note, "the host answers %ld, the port %ld, and the measurement is %ld",
                     (long)theirs, (long)ours, (long)want);
            printf("FAIL %s: %s\n", what, note);
        }
    }
    vImageDestroyResamplingFilter(filter);
    free(src.data);
    free(dest.data);
}

// Which bits of the flag word each of the thirty-six takes, measured rather than assumed: a shear's header
// lists a handful of flags and nothing says the rest are refused, and an earlier measurement on one function
// (PlanarF, which is in 6.1.3 already and is not one of these thirty-six) said all thirty-two are accepted,
// which is wrong for at least some of these. SURVEY=1 prints the table and stops.
static void surveyFlags(void)
{
    uint8_t back[8];
    memset(back, 0, sizeof back);
    printf("SURVEY the bits of the flag word each function accepts\n");
    for (int s = 0; s < shearCount; s++) {
        const Shear *shear = &shears[s];
        vImage_Buffer src = makeBuffer(9, 5, bytesPerPixel(shear), 0), dest = makeBuffer(9, 5, bytesPerPixel(shear), 0);
        fillSource(&src, shear);
        unsigned mask = 0;
        for (unsigned bit = 0; bit < 32; bit++) {
            vImage_Flags flags = (vImage_Flags)1u << bit;
            ResamplingFilter filter = vImageNewResamplingFilter(1.0f, flags);
            vImage_Error answer = shear->host(&src, &dest, 0, 0, 0.0, 0.0, filter, back, flags);
            vImageDestroyResamplingFilter(filter);
            if (answer == kvImageNoError) mask |= 1u << bit;
        }
        printf("SURVEY %-40s 0x%08x\n", shear->name, mask);
        free(src.data);
        free(dest.data);
    }
}

int main(void)
{
    setbuf(stdout, NULL);
    @autoreleasepool {
        if (getenv("SURVEY")) { surveyFlags(); return 0; }
        float scales[] = { 1.0f, 2.0f, 0.5f, 0.25f };
        double translates[] = { 0.0, 1.0, -1.0, 0.5, -0.5, 2.5 };
        double slopes[] = { 0.0, 1.0, -0.5, 2.0 };
        vImage_Flags modes[] = { kvImageBackgroundColorFill, kvImageEdgeExtend };
        // The shapes: the destination the same size, wider, narrower, taller, shorter, and the destination
        // transposed relative to the source so that both axes are exercised at a shape that is not square.
        struct { vImagePixelCount sw, sh, dw, dh; const char *label; } shapes[] = {
            { 9, 5, 9, 5, "" }, { 9, 5, 14, 5, " wide" }, { 9, 5, 4, 5, " narrow" },
            { 9, 5, 9, 2, " short" }, { 9, 5, 9, 8, " tall" }, { 5, 12, 12, 5, " transposed" },
        };
        for (int s = 0; s < shearCount; s++) {
            const Shear *shear = &shears[s];
            for (int m = 0; m < 2; m++)
                for (unsigned sc = 0; sc < 4; sc++)
                    for (unsigned t = 0; t < 6; t++)
                        for (unsigned sl = 0; sl < 4; sl++)
                            one(shear, 9, 5, 9, 5, 0, 0, translates[t], slopes[sl], scales[sc],
                                modes[m] | (sc == 3 ? kvImageHighQualityResampling : kvImageNoFlags),
                                (sc == 3) ? 5 : 3, "sweep");
            for (unsigned sh = 0; sh < 6; sh++)
                one(shear, shapes[sh].sw, shapes[sh].sh, shapes[sh].dw, shapes[sh].dh, 0, 0, 0.5, 1.0, 1.0f,
                    kvImageBackgroundColorFill, 3, shapes[sh].label);
            // The along offset, which the release takes at any value.
            one(shear, 9, 5, 9, 5, 2, 0, 0.0, 0.0, 1.0f, kvImageBackgroundColorFill, 3, " along offset 2");
            one(shear, 9, 5, 9, 5, 12, 0, 0.0, 0.0, 1.0f, kvImageBackgroundColorFill, 3, " along offset 12");
            refusals(shear);
        }
        printf("\n%d checks, %d failures\n", checks, failures);
    }
    return failures ? 1 : 0;
}