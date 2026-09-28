// The shears of vImage at 8.0, over the mapping CharonShear.h carries: the translate-and-rescale
// path, measured and exact, and a `shearSlope` the port refuses rather than answers, for the reason
// CharonShear.h sets out and facts/Accelerate/vImageGeometry.md records.

#import <Accelerate/Accelerate.h>
#include "CharonShear.h"

#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#pragma clang diagnostic ignored "-Wpointer-bool-conversion"
#pragma clang diagnostic ignored "-Wnonnull"

vImage_Error vImageHorizontalShear_Planar16S(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float horizontalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_16S backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    back[0] = (double)backColor;
    return CharonShearRun(src, dest, ours, CharonPlanar16S, YES, horizontalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageHorizontalShear_Planar16U(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float horizontalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_16U backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    back[0] = (double)backColor;
    return CharonShearRun(src, dest, ours, CharonPlanar16U, YES, horizontalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageVerticalShear_Planar16S(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float verticalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_16S backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    back[0] = (double)backColor;
    return CharonShearRun(src, dest, ours, CharonPlanar16S, NO, verticalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageVerticalShear_Planar16U(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float verticalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_16U backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    back[0] = (double)backColor;
    return CharonShearRun(src, dest, ours, CharonPlanar16U, NO, verticalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}
