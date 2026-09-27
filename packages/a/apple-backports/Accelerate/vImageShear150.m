// The shears of vImage at 15.0, over the mapping CharonShear.h carries: the translate-and-rescale
// path, measured and exact, and a `shearSlope` the port refuses rather than answers, for the reason
// CharonShear.h sets out and facts/Accelerate/vImageGeometry.md records.

#import <Accelerate/Accelerate.h>
#include "CharonShear.h"

#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#pragma clang diagnostic ignored "-Wpointer-bool-conversion"
#pragma clang diagnostic ignored "-Wnonnull"

vImage_Error vImageHorizontalShearD_ARGB16F(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                double horizontalTranslate, double shearSlope, ResamplingFilter filter,
                                const Pixel_ARGB_16F backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 4);
    return CharonShearRun(src, dest, ours, CharonARGB16F, YES, horizontalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageHorizontalShearD_CbCr16F(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                double horizontalTranslate, double shearSlope, ResamplingFilter filter,
                                const Pixel_16F16F backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 2);
    return CharonShearRun(src, dest, ours, CharonCbCr16F, YES, horizontalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageHorizontalShearD_CbCr16S(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                double horizontalTranslate, double shearSlope, ResamplingFilter filter,
                                const Pixel_16S16S backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 4);
    return CharonShearRun(src, dest, ours, CharonCbCr16S, YES, horizontalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageHorizontalShearD_CbCr16U(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                double horizontalTranslate, double shearSlope, ResamplingFilter filter,
                                const Pixel_16U16U backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 4);
    return CharonShearRun(src, dest, ours, CharonCbCr16U, YES, horizontalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageHorizontalShearD_Planar16F(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                double horizontalTranslate, double shearSlope, ResamplingFilter filter,
                                const Pixel_16F backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    back[0] = (double)backColor;
    return CharonShearRun(src, dest, ours, CharonPlanar16F, YES, horizontalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageHorizontalShear_ARGB16F(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float horizontalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_ARGB_16F backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 4);
    return CharonShearRun(src, dest, ours, CharonARGB16F, YES, horizontalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageHorizontalShear_CbCr16F(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float horizontalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_16F16F backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 2);
    return CharonShearRun(src, dest, ours, CharonCbCr16F, YES, horizontalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageHorizontalShear_CbCr16S(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float horizontalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_16S16S backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 4);
    return CharonShearRun(src, dest, ours, CharonCbCr16S, YES, horizontalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageHorizontalShear_Planar16F(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float horizontalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_16F backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    back[0] = (double)backColor;
    return CharonShearRun(src, dest, ours, CharonPlanar16F, YES, horizontalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageVerticalShearD_ARGB16F(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                double verticalTranslate, double shearSlope, ResamplingFilter filter,
                                const Pixel_ARGB_16F backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 4);
    return CharonShearRun(src, dest, ours, CharonARGB16F, NO, verticalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageVerticalShearD_CbCr16F(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                double verticalTranslate, double shearSlope, ResamplingFilter filter,
                                const Pixel_16F16F backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 2);
    return CharonShearRun(src, dest, ours, CharonCbCr16F, NO, verticalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageVerticalShearD_CbCr16S(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                double verticalTranslate, double shearSlope, ResamplingFilter filter,
                                const Pixel_16S16S backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 4);
    return CharonShearRun(src, dest, ours, CharonCbCr16S, NO, verticalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageVerticalShearD_CbCr16U(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                double verticalTranslate, double shearSlope, ResamplingFilter filter,
                                const Pixel_16U16U backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 4);
    return CharonShearRun(src, dest, ours, CharonCbCr16U, NO, verticalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageVerticalShearD_Planar16F(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                double verticalTranslate, double shearSlope, ResamplingFilter filter,
                                const Pixel_16F backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    back[0] = (double)backColor;
    return CharonShearRun(src, dest, ours, CharonPlanar16F, NO, verticalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageVerticalShear_ARGB16F(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float verticalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_ARGB_16F backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 4);
    return CharonShearRun(src, dest, ours, CharonARGB16F, NO, verticalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageVerticalShear_CbCr16F(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float verticalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_16F16F backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 2);
    return CharonShearRun(src, dest, ours, CharonCbCr16F, NO, verticalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageVerticalShear_CbCr16S(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float verticalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_16S16S backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 4);
    return CharonShearRun(src, dest, ours, CharonCbCr16S, NO, verticalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageVerticalShear_Planar16F(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float verticalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_16F backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    back[0] = (double)backColor;
    return CharonShearRun(src, dest, ours, CharonPlanar16F, NO, verticalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}
