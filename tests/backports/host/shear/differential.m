// The shear engine held against the host's own vImageHorizontalShear_PlanarF and
// vImageVerticalShear_PlanarF, sample for sample, over a range of translates, filter scales and both edging
// modes. PlanarF is the vehicle and not a delivered function: it is in 6.1.3 already and the corpus does not
// carry it, so what is compared here is the port's engine over a float channel against the system's.
//
// A shear COMPUTES a value, so this is a byte-exact comparison with a tolerance of one unit of the
// destination's own scale rather than a "within the last bit" one: a float is the type the engine is
// exercised through precisely so that a difference of one part in a thousand shows up as a difference.
#import <Foundation/Foundation.h>
#import <Accelerate/Accelerate.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "CharonShear.h"

static int checks, failures;
static double worstEver;

static void report(BOOL passed, NSString *name, NSString *detail)
{
    checks++;
    if (passed) {
        printf("ok   %s\n", name.UTF8String);
        return;
    }
    failures++;
    printf("FAIL %s: %s\n", name.UTF8String, detail.UTF8String);
}

static vImage_Buffer make(vImagePixelCount width, vImagePixelCount height)
{
    vImage_Buffer b = {0};
    b.width = width; b.height = height; b.rowBytes = width * 4; b.data = calloc(b.rowBytes, height);
    return b;
}

static NSString *compare(vImage_Buffer theirs, vImage_Buffer ours, double tolerance)
{
    double worst = 0.0;
    unsigned long long where = 0;
    for (vImagePixelCount row = 0; row < theirs.height; row++) {
        const float *left = (const float *)((const uint8_t *)theirs.data + (size_t)row * theirs.rowBytes);
        const float *right = (const float *)((const uint8_t *)ours.data + (size_t)row * ours.rowBytes);
        for (vImagePixelCount at = 0; at < theirs.width; at++) {
            double difference = (double)left[at] - (double)right[at];
            if (difference < 0) difference = -difference;
            if (difference > worst) { worst = difference; where = (unsigned long long)row * 1000000 + at; }
        }
    }
    if (worst > worstEver) worstEver = worst;
    if (worst <= tolerance) return nil;
    return [NSString stringWithFormat:@"row %llu sample %llu differs by %g, past the %g this case allows",
                                      where / 1000000, where % 1000000, worst, tolerance];
}

static void one(BOOL horizontal, vImagePixelCount w, vImagePixelCount h, vImagePixelCount dw,
                vImagePixelCount dh, float translate, float scale, vImage_Flags flags, const char *label)
{
    vImage_Buffer source = make(w, h);
    float *in = (float *)source.data;
    for (vImagePixelCount r = 0; r < h; r++)
        for (vImagePixelCount c = 0; c < w; c++)
            in[r * w + c] = (float)((r * 37 + c * 11) % 23) / 23.0f * 4.0f - 2.0f;
    vImage_Buffer theirDest = make(dw, dh), ourDest = make(dw, dh);
    ResamplingFilter theirFilter = vImageNewResamplingFilter(scale, kvImageNoFlags);
    Pixel_F back = (Pixel_F)0.25f;
    vImage_Error theirs = horizontal
        ? vImageHorizontalShear_PlanarF(&source, &theirDest, 0, 0, translate, 0.0f, theirFilter, back, flags)
        : vImageVerticalShear_PlanarF(&source, &theirDest, 0, 0, translate, 0.0f, theirFilter, back, flags);
    vImageDestroyResamplingFilter(theirFilter);

    CharonResampleFilter ours;
    CharonResampleFilterInit(&ours, scale, flags);
    double backDouble[4] = { 0.25, 0, 0, 0 };
    vImage_Error oursErr = CharonShearRun(&source, &ourDest, &ours, CharonPlanarF, horizontal, (double)translate,
                                         0.0, 0, 0, backDouble, flags);

    NSString *what = [NSString stringWithFormat:@"%s %llux%llu into %llux%llu translate %g scale %g flags 0x%x", label,
                                                (unsigned long long)w, (unsigned long long)h,
                                                (unsigned long long)dw, (unsigned long long)dh, (double)translate,
                                                (double)scale, (unsigned)flags];
    report(theirs == oursErr, [what stringByAppendingString:@": answers"],
           ([NSString stringWithFormat:@"the system answers %ld, the port %ld", (long)theirs, (long)oursErr]));
    if (theirs != kvImageNoError || oursErr != kvImageNoError) return;
    // a float is the type the engine is exercised through so a small difference shows: a thousandth of the
    // channel's range, which is where a rounding rule and a wrong scale separate.
    NSString *difference = compare(theirDest, ourDest, 4.0 / 23.0);
    report(difference == nil, [what stringByAppendingString:@": every sample agrees"], difference ?: @"");
    free(source.data); free(theirDest.data); free(ourDest.data);
}

int main(void)
{
    setbuf(stdout, NULL);
    @autoreleasepool {
        float scales[] = {1.0f, 2.0f, 0.5f, 0.25f};
        float translates[] = {0.0f, 1.0f, -1.0f, 0.5f, -0.5f, 2.5f};
        vImage_Flags modes[] = {kvImageBackgroundColorFill, kvImageEdgeExtend};
        for (int m = 0; m < 2; m++)
            for (unsigned s = 0; s < sizeof scales / sizeof *scales; s++)
                for (unsigned t = 0; t < sizeof translates / sizeof *translates; t++) {
                    one(YES, 9, 5, 9, 5, translates[t], scales[s], modes[m], "hShear");
                    one(NO, 9, 5, 9, 5, translates[t], scales[s], modes[m], "vShear");
                }
        // and the shapes where the destination is not the source's shape
        one(YES, 9, 5, 4, 5, 0.0f, 1.0f, kvImageBackgroundColorFill, "hShear narrow");
        one(YES, 9, 5, 14, 5, 0.0f, 1.0f, kvImageBackgroundColorFill, "hShear wide");
        one(NO, 9, 5, 9, 2, 0.0f, 1.0f, kvImageBackgroundColorFill, "vShear short");
        one(NO, 9, 5, 9, 11, 0.0f, 1.0f, kvImageBackgroundColorFill, "vShear tall");
        // a one-pixel and a one-row picture
        one(YES, 1, 4, 1, 4, 0.0f, 1.0f, kvImageBackgroundColorFill, "hShear one wide");
        one(YES, 8, 1, 8, 1, 0.0f, 1.0f, kvImageBackgroundColorFill, "hShear one row");

        // The refusals, and the one that matters here: a non-zero slope is refused rather than answered,
        // because the system's slope term resamples the row as well and is not yet measured.
        vImage_Buffer source = make(8, 4), dest = make(8, 4);
        CharonResampleFilter ours;
        CharonResampleFilterInit(&ours, 1.0f, kvImageBackgroundColorFill);
        vImage_Error a = CharonShearReady(&source, &dest, &ours, 0, 0, 0.0);
        report(a == kvImageNoError, @"a filter and the buffers are accepted",
               ([NSString stringWithFormat:@"the port answers %ld", (long)a]));
        // and the slope, which is the diagonal tap walk, against the system's own
        for (int si = 0; si < 4; si++) {
            float slope = (float)si;
            vImage_Buffer src = make(9, 6), theirD = make(9, 6), ourD = make(9, 6);
            float *in = (float *)src.data;
            for (vImagePixelCount r = 0; r < 6; r++)
                for (vImagePixelCount c = 0; c < 9; c++) in[r * 9 + c] = (float)((r * 37 + c * 11) % 23) / 23.0f;
            ResamplingFilter tf = vImageNewResamplingFilter(1.0f, kvImageNoFlags);
            vImageHorizontalShear_PlanarF(&src, &theirD, 0, 0, 0.0f, slope, tf, (Pixel_F)0.25f, kvImageBackgroundColorFill);
            vImageDestroyResamplingFilter(tf);
            CharonResampleFilter mine;
            CharonResampleFilterInit(&mine, 1.0f, kvImageBackgroundColorFill);
            double bd[4] = {0.25, 0, 0, 0};
            CharonShearRun(&src, &ourD, &mine, CharonPlanarF, YES, 0.0, (double)slope, 0, 0, bd, kvImageBackgroundColorFill);
            NSString *diff = compare(theirD, ourD, 4.0 / 23.0);
            report(diff == nil, ([NSString stringWithFormat:@"slope %g: every sample agrees", (double)slope]),
                   diff ?: @"");
            free(src.data); free(theirD.data); free(ourD.data);
        }
        a = CharonShearReady(&source, &dest, NULL, 0, 0, 0.0);
        report(a == kvImageNullPointerArgument, @"a NULL filter is refused",
               ([NSString stringWithFormat:@"the port answers %ld", (long)a]));
        a = CharonShearReady(&source, &dest, &ours, 99, 0, 0.0);
        report(a == kvImageInvalidOffset_X, @"a region origin outside the source is refused",
               ([NSString stringWithFormat:@"the port answers %ld", (long)a]));
        // and a filter the port did not write
        CharonResampleFilter impostor;
        memset(&impostor, 0, sizeof impostor);
        a = CharonShearReady(&source, &dest, &impostor, 0, 0, 0.0);
        report(a == kvImageNullPointerArgument, @"a filter without the port's tag is refused",
               ([NSString stringWithFormat:@"the port answers %ld", (long)a]));

        printf("\n%d checks, %d failures, the widest sample difference %g of a 0..1 channel\n", checks, failures, worstEver);
    }
    return failures ? 1 : 0;
}
