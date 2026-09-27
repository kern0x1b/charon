// The shears of vImage at 7.0, over the mapping CharonShear.h carries: the translate-and-rescale
// path, measured and exact, and a `shearSlope` the port refuses rather than answers, for the reason
// CharonShear.h sets out and facts/Accelerate/vImageGeometry.md records.

#import <Accelerate/Accelerate.h>
#include "CharonShear.h"

#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#pragma clang diagnostic ignored "-Wpointer-bool-conversion"
#pragma clang diagnostic ignored "-Wnonnull"

vImage_Error vImageHorizontalShearD_ARGB16S(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                double horizontalTranslate, double shearSlope, ResamplingFilter filter,
                                const Pixel_ARGB_16S backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 4);
    return CharonShearRun(src, dest, ours, CharonARGB16S, YES, horizontalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageHorizontalShearD_ARGB16U(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                double horizontalTranslate, double shearSlope, ResamplingFilter filter,
                                const Pixel_ARGB_16U backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 4);
    return CharonShearRun(src, dest, ours, CharonARGB16U, YES, horizontalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageHorizontalShear_ARGB16S(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float horizontalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_ARGB_16S backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 4);
    return CharonShearRun(src, dest, ours, CharonARGB16S, YES, horizontalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageHorizontalShear_ARGB16U(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float horizontalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_ARGB_16U backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 4);
    return CharonShearRun(src, dest, ours, CharonARGB16U, YES, horizontalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageVerticalShearD_ARGB16S(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                double verticalTranslate, double shearSlope, ResamplingFilter filter,
                                const Pixel_ARGB_16S backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 4);
    return CharonShearRun(src, dest, ours, CharonARGB16S, NO, verticalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageVerticalShearD_ARGB16U(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                double verticalTranslate, double shearSlope, ResamplingFilter filter,
                                const Pixel_ARGB_16U backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 4);
    return CharonShearRun(src, dest, ours, CharonARGB16U, NO, verticalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageVerticalShear_ARGB16S(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float verticalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_ARGB_16S backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 4);
    return CharonShearRun(src, dest, ours, CharonARGB16S, NO, verticalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}

vImage_Error vImageVerticalShear_ARGB16U(const vImage_Buffer *src, const vImage_Buffer *dest,
                                vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y,
                                float verticalTranslate, float shearSlope, ResamplingFilter filter,
                                const Pixel_ARGB_16U backColor, vImage_Flags flags)
{
    const CharonResampleFilter *ours = CharonResampleFilterOf(filter);
    vImage_Error ready = CharonShearReady(src, dest, ours, srcOffsetToROI_X, srcOffsetToROI_Y, shearSlope);
    if (ready != kvImageNoError)
        return ready;
    double back[4] = { 0, 0, 0, 0 };
    memcpy(back, backColor, sizeof(double) * 4);
    return CharonShearRun(src, dest, ours, CharonARGB16U, NO, verticalTranslate, shearSlope, srcOffsetToROI_X,
                          srcOffsetToROI_Y, back, flags);
}
