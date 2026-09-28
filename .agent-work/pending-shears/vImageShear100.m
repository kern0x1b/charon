// The shears of vImage at 10.0, over the mapping CharonShear.h carries: the translate-and-rescale
// path, measured and exact, and a `shearSlope` the port refuses rather than answers, for the reason
// CharonShear.h sets out and facts/Accelerate/vImageGeometry.md records.

#import <Accelerate/Accelerate.h>
#include "CharonShear.h"

#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#pragma clang diagnostic ignored "-Wpointer-bool-conversion"
#pragma clang diagnostic ignored "-Wnonnull"

vImage_Error vImageHorizontalShear_CbCr16U(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float horizontalTranslate, float shearSlope, ResamplingFilter filter,
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

vImage_Error vImageHorizontalShear_CbCr8(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float horizontalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_88 backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 2);
    return CharonShearRun(src, dest, ours, CharonCbCr8, YES, horizontalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageHorizontalShear_XRGB2101010W(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float horizontalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_32U backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    back[0] = (double)backColor;
    return CharonShearRun(src, dest, ours, CharonXRGB2101010W, YES, horizontalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageVerticalShear_CbCr16U(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float verticalTranslate, float shearSlope, ResamplingFilter filter,
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

vImage_Error vImageVerticalShear_CbCr8(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float verticalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_88 backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 2);
    return CharonShearRun(src, dest, ours, CharonCbCr8, NO, verticalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageVerticalShear_XRGB2101010W(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float verticalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_32U backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    back[0] = (double)backColor;
    return CharonShearRun(src, dest, ours, CharonXRGB2101010W, NO, verticalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}
