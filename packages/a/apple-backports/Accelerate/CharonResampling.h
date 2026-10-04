// The resampling filter of vImage's shears: **the caller's own object, read**.
//
// `ResamplingFilter` is a `void *`, and behind it on every release a shear row runs on is the RELEASE's own
// object: `vImageNewResamplingFilter` is exported from 5.0 (6.0.tsv), so the caller makes the filter with the
// system constructor and hands it to the shear. The port reads that object rather than making one of its own,
// and this file is the reader.
//
// **Why the port does not generate a table.** The kernel is Lanczos3, or Lanczos5 under
// `kvImageHighQualityResampling`, and its weights are exactly computable - but the release stores them as
// int16 Q14 and *the stored integers are the release's own single-precision `sinf`/`cosf`* (v-tail-a11 read the
// kernel function at 0x30418d48 on the 6.1.3 armv7 cache: `blx sinf`, `blx cosf`, and a `vcvt.s32.f32`
// truncation with no correction pass). There is no formula to reproduce, so a generated table is an
// approximation of the caller's own numbers by construction, and every sheared pixel would carry the
// difference. Reading the caller's object is exact by construction on every release, and it is what the
// release itself does: its worker sums the int16 row it is about to use (`ldrsh` over `numTaps` at
// 0x3040f488 on 6.1.3 armv7).
//
// **The layout is two shapes and the architecture decides which.** Both hold the same nine fields in the
// same order; a field is a 32-bit slot at byte `4k` on armv7/armv7s and a 64-bit slot at byte `8k` on arm64:
//
//   | field        | armv7 | arm64 | what it holds |
//   | --- | --- | --- | --- |
//   | reciprocal   | 0 | 0 | the double `1.0 / scale`, which is what the release multiplies a position by |
//   | numTaps      | 8 | 8 | the tap count, `(int)(2*min(lobes/scale, lobes) + 0.5)` |
//   | floatStride  | 12 | 16 | the float table's row stride, `(15 + 4*numTaps) & ~15` |
//   | int16Stride  | 16 | 24 | the Q14 row's stride in bytes, `(((2 + 2*numTaps) & ~3) + 15) & ~15` |
//   | phases       | 20 | 32 | the phase count, a power of two of at most 64 |
//   | exponent     | 24 | 40 | the phase exponent, `clamp(133 - exponent(float(1/scale)), 0, 6)` |
//   | offset       | 28 | 48 | **the Q14 table's end, as an OFFSET from the object** |
//   | table        | 32 | 56 | **the Q14 table's first byte, as a pointer** |
//   | base         | 36 | 64 | `(object + 55) & ~15` on armv7, `(object + 87) & ~15` on arm64 |
//
// Measured by disassembly of ten writers - 6.1.3, 7.0, 8.0, 9.3.6 and 10.3.4 armv7/armv7s, and 7.0, 7.0.1,
// 10.0.1, 11.0 and 12.0 arm64 - and by execution on an iPhone3,1 6.1.3 10B329 guest for the armv7 shape. **The
// arm64 shape is one shape on all five arm64 releases**: `stp x10, x13, [x0, #56]` on 7.0 stores bytes 56 and
// 64, and the next instruction stores the offset at byte 48, so the table's own pointer is in the object on
// every release read and nothing is computed from another field. An earlier reading of that store pair took
// `#56` for `#48` and claimed 7.0 overwrote the field; `d4ed12b1c` takes that back.
//
// **The offset is an offset on both shapes**, and this is the one that a reader gets wrong: a refusal that
// compares it against a pointer refuses the release's own filter, which is exactly what the first version of
// the 6.1.3 probe did - and that refusal was the measurement that word 7 is an offset. The identity the
// writer computes, and the one the refusal below checks, is
//
//     offset == (table - object) + phases * int16Stride
//
// which holds on all nine guest shapes and all ten host shapes, and which ties the table's pointer to the
// object so a buffer that is not a filter cannot be read as one. **It is not `offset == phases *
// int16Stride`**, which is false on every shape measured - the offset also carries the float table's size -
// and a refusal written that way would refuse every filter the port exists to read.
//
// **What the row is, and the two properties the engine relies on.** A row is `int16Stride/2` int16 Q14
// weights, and the tail past `numTaps` is zero in every row of every shape measured, so summing the row the
// port read is summing the release's own `numTaps` weights. The row's peak is **not at one index**: it sits at
// `K0` for the first half of the phases and at `K0 + 1` for the second, and is TIED at the half phase - which
// is how a table with one index per phase can carry a fractional position at all. `K0` is therefore the lowest
// index attaining **row 0's** maximum, and the engine uses that one index for every phase; it agrees with
// `(numTaps - 2)/2` on all nineteen shapes measured and is READ rather than recomputed, so a filter whose
// rows are shaped the other way round still reads correctly.
//
// **The divisor is the row's own sum.** On macOS every row sums to exactly 16384 and dividing by 16384 is
// indistinguishable; on 6.1.3 the sums are within 5 of it and 15 of the sixteen rows at a scale of 0.25 are
// not equal to it, so a constant divisor would be wrong on the release the rows are written for.

#pragma once

#import <Accelerate/Accelerate.h>

enum {
    // A field is a 32-bit slot at byte 4k on armv7 and armv7s, and a 64-bit slot at byte 8k on arm64. The
    // compiler's own architecture macros name which, so the port keys the layout on the target and not on a
    // release number it cannot see from here.
    CharonResampleSlot = (int)(sizeof(void *) >= 8 ? 8 : 4),
    // The phase count the release's own writer clamps to, and the bound the sum array below is sized by.
    CharonResampleMaxPhases = 64
};

// Field `index` of the object, as the width that architecture gives it.
#define CHARON_RESAMPLE_SLOT(object, index, type) \
    (*(type *)(void *)((const char *)(object) + (size_t)(index) * (size_t)CharonResampleSlot))

// The filter, as the engine wants it: the release's table, described. `reciprocal` is the release's own double
// and the engine multiplies positions by it, because that is what the release's worker does with the value it
// kept beside `floor` of it; `scale` is the same number divided back, for anything that wants the scale itself.
typedef struct CharonResampleFilter {
    double reciprocal;
    double scale;
    const int16_t *row;
    unsigned width;              // int16Stride / 2, the Q14 row's own width in int16
    unsigned phases;
    unsigned taps;               // numTaps
    unsigned centre;             // K0: the lowest index attaining row 0's maximum
    unsigned offset;             // the Q14 table's end, as an offset from the object
} CharonResampleFilter;

// Reading the caller's object, and refusing everything that is not one. Returns 1 and fills `out` when the
// object is a resampling filter of a shape measured, and 0 with `out` zeroed otherwise; the caller turns the
// 0 into `kvImageInvalidParameter`, which is what the host answers for a NULL filter.
//
// The six refusals, each of which is a field the writer computed and not a value this file invented:
//
//   1. `reciprocal > 0` - the release's writer divides 1.0 by the scale and stores the result, so a filter
//      that has one is a filter whose scale is finite.
//   2. `numTaps >= 1`.
//   3. `int16Stride >= 2` and even, so a row is at least one int16 and is addressable by `int16_t *`.
//   4. `phases` a power of two of at most 64 - the writer's own `1 << clamp(133 - exponent, 0, 6)`.
//   5. the table strictly inside `[object, object + offset)`: it starts inside the object and ends at or
//      before the offset, which is the bound the release itself uses. **`vImageGetResamplingFilterSize` is not
//      that bound and must not be used as one**: it answers two runs of the same binary two different numbers
//      (3168 and 3160 for one shape), because the size is computed on the caller's stack where `((sp+55)&~15)
//      - sp` is 16 or 8 by that frame's alignment, while the stored offset is not.
//   6. `offset == (table - object) + phases * int16Stride`, the writer's own arithmetic. This is the check that
//      refuses a buffer that is not a filter, and it is checked as an offset on both shapes.
//
// **There is deliberately no check on the row's sum.** The release's own rows sum to `16384 +- 5` on 6.1.3 and
// to exactly 16384 on macOS, so a refusal built on the sum refuses the filter this port exists to read - the
// defect v-tail-a11 measured when its first probe did exactly that.
static inline int CharonResampleFilterOf(ResamplingFilter filter, CharonResampleFilter *out)
{
    out->reciprocal = 0.0;
    out->scale = 0.0;
    out->row = 0;
    out->width = 0;
    out->phases = 0;
    out->taps = 0;
    out->centre = 0;
    out->offset = 0;
    if (!filter || !out)
        return 0;

    double reciprocal = CHARON_RESAMPLE_SLOT(filter, 0, double);
    unsigned taps = CHARON_RESAMPLE_SLOT(filter, 1, unsigned);
    unsigned floatStride = CHARON_RESAMPLE_SLOT(filter, 2, unsigned);
    unsigned int16Stride = CHARON_RESAMPLE_SLOT(filter, 3, unsigned);
    unsigned phases = CHARON_RESAMPLE_SLOT(filter, 4, unsigned);
    unsigned offset = CHARON_RESAMPLE_SLOT(filter, 6, unsigned);
    const char *table = (const char *)CHARON_RESAMPLE_SLOT(filter, 7, const char *);

    if (!(reciprocal > 0.0) || taps < 1 || int16Stride < 2 || (int16Stride & 1))
        return 0;
    if (phases == 0 || phases > (unsigned)CharonResampleMaxPhases || (phases & (phases - 1)) != 0)
        return 0;
    // The offset is an OFFSET: `table - object` is what the writer subtracted, and comparing the field against
    // a pointer instead is what refused all nine guest shapes in the first version of this reader.
    if (!table || table <= (const char *)filter)
        return 0;
    size_t inside = (size_t)(table - (const char *)filter);
    if (inside >= (size_t)offset)
        return 0;
    if (inside + (size_t)phases * (size_t)int16Stride > (size_t)offset)
        return 0;
    if ((size_t)offset != inside + (size_t)phases * (size_t)int16Stride)
        return 0;
    // The float table sits between the base and the Q14 table and is `phases + 1` rows of it, which is the
    // writer's own last `madd`. Checked because it is free and it is the one arithmetic that ties the table's
    // pointer to the header's own numbers rather than only to its own offset.
    const char *base = CHARON_RESAMPLE_SLOT(filter, 8, const char *);
    if (!base || base > table)
        return 0;
    size_t fromBase = (size_t)(table - base);
    if (fromBase != (size_t)floatStride * (size_t)(phases + 1))
        return 0;

    const int16_t *row = (const int16_t *)table;
    unsigned width = int16Stride / 2;
    int best = -(1 << 30);
    unsigned centre = 0;
    for (unsigned k = 0; k < width; k++) {
        int value = row[k];
        if (value > best) {
            best = value;
            centre = k;
        }
    }

    out->reciprocal = reciprocal;
    out->scale = 1.0 / reciprocal;
    out->row = row;
    out->width = width;
    out->phases = phases;
    out->taps = taps;
    out->centre = centre;
    out->offset = offset;
    return 1;
}

// The pair the row is read at: which of the release's `phases` rows, and which source pixel its centre tap
// is. The mapped position is `centre`, in source pixels, with **no half pixel** - source pixel `c` is at
// position `c` and destination pixel `x` is at position `x`, which is why a scale of one is an exact identity
// and why a scale of two puts source `c` at destination `2c`.
//
// The fractional part picks the row by rounding to NEAREST with a CARRY: `q` runs from 0 to `phases` as the
// fraction runs from 0 to 1, `q == phases` means the position has crossed the next whole pixel, and the carry
// advances the base while the phase wraps back to zero. The carry is not decoration - it is what makes row 0's
// peak land on the next source pixel at the top of the range instead of one pixel behind it.
//
// **The two functions do not read the row the same way, and the difference only shows at an inexact reciprocal.**
//
// | | horizontal | vertical |
// | --- | --- | --- |
// | how the position becomes a row | `q = floor(frac*phases + 0.5)`, then a carry | `phase = floor(frac*phases)`, no carry |
// | a position at half a phase | the upper row | the lower row |
// | the centre's arrangement | `position*recip - 0.5` | `position*recip + A*(1 - recip) - 0.5` |
//
// At scales 1, 2, 0.5 and 0.25 the stored reciprocal is exact and every position the sweep asks for is a whole
// phase or half a phase, so the two rows are indistinguishable and the whole family reads the same. 0.75 stores
// `1.3333333333333333` and separates all three.
//
// **The horizontal's tie goes UP.** Measured on the host's own bytes, both axes asked for the SAME mapped centre
// - the horizontal's centre is `along - translate` and the vertical's is `along + translate`, so horizontal
// translate `-t` and vertical translate `+t` land on one centre (`tie.m`, committed beside the harness because
// a claim in this file rests on it):
//
// | mapped centre (scale one, slope zero) | horizontal | vertical |
// | --- | --- | --- |
// | 0.0078125, `x = 0.5` | phase 1 | phase 0 |
// | 0.0234375, `x = 1.5` | phase 2 | phase 1 |
// | 0.0390625, `x = 2.5` | phase 3 | phase 2 |
// | 0.9921875, `x = 63.5` | phase 0, **base carried** | phase 63, no carry |
// | -0.0078125, `x = 63.5` | phase 0, **base carried** | phase 63, no carry |
//
// Every non-tie agrees between the axes and every tie disagrees, at the bottom of the range, in the middle of it
// and at the top, where the tie is where the horizontal's CARRY shows: `floor` reaches `q == phases`, wraps the
// phase to zero and advances the base, and the horizontal does exactly that while the vertical stays at
// `q == phases - 1`. The m = 1 tie is what rules out round-to-nearest-TIES-TO-EVEN, which would answer phase 2
// there and which the horizontal does not do either.
//
// **The vertical TRUNCATES.** `phase = floor(frac*phases)` and `base = floor(centre)`, with no carry at all -
// which is not the same rule with the tie moved, it is a different reading of the position, and the host's bytes
// name it: at 0.75, translate zero and slope zero, the host's five destination rows read rows (32, base -2),
// (53, base -1), (10, base 1), (31, base 2), (53, base 3), and truncating reproduces all five while rounding
// answers 53, 11, 32, 53 and misses four of them. `base = floor(centre)` with `phase = floor(frac*phases)` is
// the whole rule: `floor(floor(x*P)/P) == floor(x)` for a positive integer P, so the carry a rounding rule needs
// is the identity here and there is nothing to get wrong about it.
//
// A tie is reachable only where the translate is a dyadic rational that lands half a phase from a whole one,
// which is why the sweep's off-grid translate 1/128 is the only one that reaches the horizontal's tie: it is
// exactly half of one of the 64 phases at a scale of one and half of one of the 32 at a scale of one half. **At
// a scale of two no tie is reachable** - the reciprocal halves the translate, so the same position is a quarter
// of a phase - and at 0.75 the product is not a tie either.
//
// `ceil` and `floor` are the right primitives rather than `floor` adjusted by hand because each is monotone
// across its own boundary from both sides: `x` a hair under 0.5 gives 0 and a hair over gives 1, with no epsilon
// and no special case.
//
// Measured on iPhone3,1 6.1.3 10B329 against the release's own stored bytes, by exhaustion over all 64 rows
// and every base tap for every destination column of a one-column delta: 1344 of 1344 at a scale of two, 768
// of 768 at one, 480 of 480 at a half, 596 of 624 at 0.75, and 32 of 32 / 56 of 56 / 32 of 32 / 32 of 32 on a
// ramp at translates 0, 0.5, 0.25 and 0.125 - where the four other spellings of the translate score 7, 7, 5
// and 4 of the same 56. The translate is inside the parenthesis with the coordinate and the whole is divided
// by the scale.
static inline void CharonResamplePhase(const CharonResampleFilter *filter, double centre, int horizontal,
                                       unsigned *phase, long *base)
{
    double whole = floor(centre);
    double fraction = centre - whole;
    long low = (long)whole;
    long q;
    if (horizontal) {
        // Round to nearest, the tie to the upper row, with the carry that wraps the phase and advances the base.
        q = (long)floor(fraction * (double)filter->phases + 0.5);
        long carry = q / (long)filter->phases;
        *phase = (unsigned)(q - carry * (long)filter->phases);
        *base = low + carry;
    } else {
        // Truncate the fraction. No carry and no tie to settle.
        long q = (long)floor(fraction * (double)filter->phases);
        *phase = (unsigned)q;
        *base = low;
    }
}

// The row's own sum, which is the divisor. **Not 16384**: on 6.1.3 the rows are within 5 of it and at a scale
// of 0.25 all sixteen rows are not equal to it, while the release's own worker sums the row it is about to
// use. On macOS the sum is exactly 16384 on every row of every shape, which is why the host differential
// cannot tell the two spellings apart and why the device is the oracle for this one.
static inline double CharonResampleRowSum(const CharonResampleFilter *filter, unsigned phase)
{
    const int16_t *row = filter->row + (size_t)phase * filter->width;
    long sum = 0;
    for (unsigned k = 0; k < filter->width; k++)
        sum += row[k];
    return (double)sum;
}