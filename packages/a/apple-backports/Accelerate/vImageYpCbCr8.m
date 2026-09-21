#import <Accelerate/Accelerate.h>
#include <math.h>
#include <string.h>

#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#pragma clang diagnostic ignored "-Wpointer-bool-conversion"
#pragma clang diagnostic ignored "-Wnonnull"

static const vImage_YpCbCrToARGBMatrix charon_ypcbcr_601_4 = {1.0f, 1.40199995f, -0.714136302f, -0.344136298f, 1.77199996f};
static const vImage_YpCbCrToARGBMatrix charon_ypcbcr_709_2 = {1.0f, 1.57480001f, -0.46812427f, -0.187324271f, 1.8556f};
static const vImage_ARGBToYpCbCrMatrix charon_argb_601_4 = {0.298999995f, 0.587000012f, 0.114f, -0.168735892f, -0.331264108f, 0.5f, -0.418687582f, -0.0813124105f};
static const vImage_ARGBToYpCbCrMatrix charon_argb_709_2 = {0.212599993f, 0.715200007f, 0.0722000003f, -0.114572108f, -0.385427892f, 0.5f, -0.454152912f, -0.0458470918f};

const vImage_YpCbCrToARGBMatrix *kvImage_YpCbCrToARGBMatrix_ITU_R_601_4 = &charon_ypcbcr_601_4;
const vImage_YpCbCrToARGBMatrix *kvImage_YpCbCrToARGBMatrix_ITU_R_709_2 = &charon_ypcbcr_709_2;
const vImage_ARGBToYpCbCrMatrix *kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4 = &charon_argb_601_4;
const vImage_ARGBToYpCbCrMatrix *kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2 = &charon_argb_709_2;

enum {
    CharonYpCbCrToARGBMagic = 0x43597041,
    CharonARGBToYpCbCrMagic = 0x43597042
};

typedef struct {
    uint32_t magic;
    float Yp, Cr_R, Cr_G, Cb_G, Cb_B;
    float yScale, cScale;
    float Yp_bias, CbCr_bias;
    float YpMin, YpMax, CbCrMin, CbCrMax;
} CharonToARGB;

typedef struct {
    uint32_t magic;
    float R_Yp, G_Yp, B_Yp, R_Cb, G_Cb, B_Cb_R_Cr, G_Cr, B_Cr;
    float yScale, cScale;
    float Yp_bias, CbCr_bias;
    float YpMin, YpMax, CbCrMin, CbCrMax;
} CharonToYpCbCr;

static const vImage_Flags charon_vimage_conversion_flags = kvImageDoNotTile | kvImagePrintDiagnosticsToConsole;
static const vImage_Flags charon_vimage_generate_flags = kvImagePrintDiagnosticsToConsole;
static const vImage_Flags charon_vimage_channel_flags = kvImageDoNotTile | kvImageGetTempBufferSize | kvImagePrintDiagnosticsToConsole;

static float charon_clamp(float value, float low, float high)
{
    return value < low ? low : (value > high ? high : value);
}

static uint8_t charon_byte(float value)
{
    float rounded = roundf(value);
    return (uint8_t)charon_clamp(rounded, 0.0f, 255.0f);
}

static uint8_t charon_encoded(float value, float low, float high)
{
    return (uint8_t)charon_clamp(roundf(value), charon_clamp(low, 0.0f, 255.0f), charon_clamp(high, 0.0f, 255.0f));
}

static BOOL charon_permutation(const uint8_t permuteMap[4])
{
    uint8_t seen[4] = {0, 0, 0, 0};
    if (!permuteMap)
        return NO;
    for (unsigned index = 0; index < 4; index++) {
        if (permuteMap[index] > 3 || seen[permuteMap[index]])
            return NO;
        seen[permuteMap[index]] = 1;
    }
    return YES;
}

vImage_Error vImageConvert_YpCbCrToARGB_GenerateConversion(const vImage_YpCbCrToARGBMatrix *matrix,
                                                           const vImage_YpCbCrPixelRange *pixelRange,
                                                           vImage_YpCbCrToARGB *outInfo,
                                                           vImageYpCbCrType inYpCbCrType,
                                                           vImageARGBType outARGBType,
                                                           vImage_Flags flags)
{
    if (flags & ~charon_vimage_generate_flags)
        return kvImageUnknownFlagsBit;
    if (!matrix || !pixelRange || !outInfo)
        return kvImageNullPointerArgument;
    if (outARGBType != kvImageARGB8888)
        return kvImageUnsupportedConversion;
    if (inYpCbCrType != kvImage420Yp8_Cb8_Cr8 && inYpCbCrType != kvImage420Yp8_CbCr8)
        return kvImageUnsupportedConversion;
    int32_t yRange = pixelRange->YpRangeMax - pixelRange->Yp_bias;
    int32_t cRange = pixelRange->CbCrRangeMax - pixelRange->CbCr_bias;
    if (yRange == 0 || cRange == 0)
        return kvImageInvalidParameter;
    CharonToARGB found = {
        .magic = CharonYpCbCrToARGBMagic,
        .Yp = matrix->Yp,
        .Cr_R = matrix->Cr_R,
        .Cr_G = matrix->Cr_G,
        .Cb_G = matrix->Cb_G,
        .Cb_B = matrix->Cb_B,
        .yScale = 255.0f / (float)yRange,
        .cScale = 255.0f / (2.0f * (float)cRange),
        .Yp_bias = (float)pixelRange->Yp_bias,
        .CbCr_bias = (float)pixelRange->CbCr_bias,
        .YpMin = (float)pixelRange->YpMin,
        .YpMax = (float)pixelRange->YpMax,
        .CbCrMin = (float)pixelRange->CbCrMin,
        .CbCrMax = (float)pixelRange->CbCrMax
    };
    memset(outInfo, 0, sizeof *outInfo);
    memcpy(outInfo, &found, sizeof found);
    return kvImageNoError;
}

vImage_Error vImageConvert_ARGBToYpCbCr_GenerateConversion(const vImage_ARGBToYpCbCrMatrix *matrix,
                                                           const vImage_YpCbCrPixelRange *pixelRange,
                                                           vImage_ARGBToYpCbCr *outInfo,
                                                           vImageARGBType inARGBType,
                                                           vImageYpCbCrType outYpCbCrType,
                                                           vImage_Flags flags)
{
    if (flags & ~charon_vimage_generate_flags)
        return kvImageUnknownFlagsBit;
    if (!matrix || !pixelRange || !outInfo)
        return kvImageNullPointerArgument;
    if (inARGBType != kvImageARGB8888)
        return kvImageUnsupportedConversion;
    if (outYpCbCrType != kvImage420Yp8_Cb8_Cr8 && outYpCbCrType != kvImage420Yp8_CbCr8)
        return kvImageUnsupportedConversion;
    int32_t yRange = pixelRange->YpRangeMax - pixelRange->Yp_bias;
    int32_t cRange = pixelRange->CbCrRangeMax - pixelRange->CbCr_bias;
    CharonToYpCbCr found = {
        .magic = CharonARGBToYpCbCrMagic,
        .R_Yp = matrix->R_Yp,
        .G_Yp = matrix->G_Yp,
        .B_Yp = matrix->B_Yp,
        .R_Cb = matrix->R_Cb,
        .G_Cb = matrix->G_Cb,
        .B_Cb_R_Cr = matrix->B_Cb_R_Cr,
        .G_Cr = matrix->G_Cr,
        .B_Cr = matrix->B_Cr,
        .yScale = (float)yRange / 255.0f,
        .cScale = 2.0f * (float)cRange / 255.0f,
        .Yp_bias = (float)pixelRange->Yp_bias,
        .CbCr_bias = (float)pixelRange->CbCr_bias,
        .YpMin = (float)pixelRange->YpMin,
        .YpMax = (float)pixelRange->YpMax,
        .CbCrMin = (float)pixelRange->CbCrMin,
        .CbCrMax = (float)pixelRange->CbCrMax
    };
    memset(outInfo, 0, sizeof *outInfo);
    memcpy(outInfo, &found, sizeof found);
    return kvImageNoError;
}

static const CharonToARGB *charon_to_argb(const vImage_YpCbCrToARGB *info)
{
    const CharonToARGB *found = (const CharonToARGB *)info;
    return found && found->magic == CharonYpCbCrToARGBMagic ? found : NULL;
}

static const CharonToYpCbCr *charon_to_ypcbcr(const vImage_ARGBToYpCbCr *info)
{
    const CharonToYpCbCr *found = (const CharonToYpCbCr *)info;
    return found && found->magic == CharonARGBToYpCbCrMagic ? found : NULL;
}

static void charon_argb_pixel(const CharonToARGB *conversion, float luma, float cb, float cr, uint8_t alpha,
                              const uint8_t permuteMap[4], uint8_t *out)
{
    float y = (charon_clamp(luma, conversion->YpMin, conversion->YpMax) - conversion->Yp_bias) * conversion->yScale * conversion->Yp;
    float blue = (charon_clamp(cb, conversion->CbCrMin, conversion->CbCrMax) - conversion->CbCr_bias) * conversion->cScale;
    float red = (charon_clamp(cr, conversion->CbCrMin, conversion->CbCrMax) - conversion->CbCr_bias) * conversion->cScale;
    uint8_t pixel[4];
    pixel[0] = alpha;
    pixel[1] = charon_byte(y + red * conversion->Cr_R);
    pixel[2] = charon_byte(y + blue * conversion->Cb_G + red * conversion->Cr_G);
    pixel[3] = charon_byte(y + blue * conversion->Cb_B);
    out[0] = pixel[permuteMap[0]];
    out[1] = pixel[permuteMap[1]];
    out[2] = pixel[permuteMap[2]];
    out[3] = pixel[permuteMap[3]];
}

static vImage_Error charon_420_to_argb(const vImage_Buffer *srcYp, const vImage_Buffer *srcCb, const vImage_Buffer *srcCr,
                                       const vImage_Buffer *srcCbCr, const vImage_Buffer *dest,
                                       const vImage_YpCbCrToARGB *info, const uint8_t *permuteMap, uint8_t alpha,
                                       vImage_Flags flags)
{
    static const uint8_t identity[4] = {0, 1, 2, 3};
    if (flags & ~charon_vimage_conversion_flags)
        return kvImageUnknownFlagsBit;
    const CharonToARGB *conversion = charon_to_argb(info);
    if (!srcYp || !dest || !conversion)
        return kvImageNullPointerArgument;
    if (!permuteMap)
        permuteMap = identity;
    else if (!charon_permutation(permuteMap))
        return kvImageInvalidParameter;
    vImagePixelCount width = dest->width, height = dest->height;
    if (srcYp->width < width || srcYp->height < height)
        return kvImageRoiLargerThanInputBuffer;
    vImagePixelCount chromaWidth = (width + 1) / 2, chromaHeight = (height + 1) / 2;
    if (srcCbCr) {
        if (srcCbCr->width < chromaWidth || srcCbCr->height < chromaHeight)
            return kvImageRoiLargerThanInputBuffer;
    } else {
        if (!srcCb || !srcCr)
            return kvImageNullPointerArgument;
        if (srcCb->width < chromaWidth || srcCb->height < chromaHeight
            || srcCr->width < chromaWidth || srcCr->height < chromaHeight)
            return kvImageRoiLargerThanInputBuffer;
    }
    for (vImagePixelCount row = 0; row < height; row++) {
        const uint8_t *luma = (const uint8_t *)srcYp->data + row * srcYp->rowBytes;
        uint8_t *out = (uint8_t *)dest->data + row * dest->rowBytes;
        vImagePixelCount chromaRow = row / 2;
        const uint8_t *cbcr = srcCbCr ? (const uint8_t *)srcCbCr->data + chromaRow * srcCbCr->rowBytes : NULL;
        const uint8_t *cbRow = srcCb ? (const uint8_t *)srcCb->data + chromaRow * srcCb->rowBytes : NULL;
        const uint8_t *crRow = srcCr ? (const uint8_t *)srcCr->data + chromaRow * srcCr->rowBytes : NULL;
        for (vImagePixelCount column = 0; column < width; column++) {
            vImagePixelCount chromaColumn = column / 2;
            float cb = cbcr ? (float)cbcr[chromaColumn * 2] : (float)cbRow[chromaColumn];
            float cr = cbcr ? (float)cbcr[chromaColumn * 2 + 1] : (float)crRow[chromaColumn];
            charon_argb_pixel(conversion, (float)luma[column], cb, cr, alpha, permuteMap, out + column * 4);
        }
    }
    return kvImageNoError;
}

vImage_Error vImageConvert_420Yp8_CbCr8ToARGB8888(const vImage_Buffer *srcYp, const vImage_Buffer *srcCbCr,
                                                  const vImage_Buffer *dest, const vImage_YpCbCrToARGB *info,
                                                  const uint8_t permuteMap[4], const uint8_t alpha, vImage_Flags flags)
{
    return charon_420_to_argb(srcYp, NULL, NULL, srcCbCr, dest, info, permuteMap, alpha, flags);
}

vImage_Error vImageConvert_420Yp8_Cb8_Cr8ToARGB8888(const vImage_Buffer *srcYp, const vImage_Buffer *srcCb,
                                                    const vImage_Buffer *srcCr, const vImage_Buffer *dest,
                                                    const vImage_YpCbCrToARGB *info, const uint8_t permuteMap[4],
                                                    const uint8_t alpha, vImage_Flags flags)
{
    return charon_420_to_argb(srcYp, srcCb, srcCr, NULL, dest, info, permuteMap, alpha, flags);
}

static vImage_Error charon_argb_to_420(const vImage_Buffer *src, const vImage_Buffer *destYp,
                                       const vImage_Buffer *destCb, const vImage_Buffer *destCr,
                                       const vImage_Buffer *destCbCr, const vImage_ARGBToYpCbCr *info,
                                       const uint8_t *permuteMap, vImage_Flags flags)
{
    static const uint8_t identity[4] = {0, 1, 2, 3};
    if (flags & ~charon_vimage_conversion_flags)
        return kvImageUnknownFlagsBit;
    const CharonToYpCbCr *conversion = charon_to_ypcbcr(info);
    if (!src || !destYp || !conversion)
        return kvImageNullPointerArgument;
    if (!permuteMap)
        permuteMap = identity;
    else if (!charon_permutation(permuteMap))
        return kvImageInvalidParameter;
    vImagePixelCount width = destYp->width, height = destYp->height;
    if (src->width < width || src->height < height)
        return kvImageRoiLargerThanInputBuffer;
    vImagePixelCount chromaWidth = (width + 1) / 2, chromaHeight = (height + 1) / 2;
    if (destCbCr) {
        if (destCbCr->width < chromaWidth || destCbCr->height < chromaHeight)
            return kvImageRoiLargerThanInputBuffer;
    } else {
        if (!destCb || !destCr)
            return kvImageNullPointerArgument;
        if (destCb->width < chromaWidth || destCb->height < chromaHeight
            || destCr->width < chromaWidth || destCr->height < chromaHeight)
            return kvImageRoiLargerThanInputBuffer;
    }
    for (vImagePixelCount row = 0; row < height; row++) {
        const uint8_t *in = (const uint8_t *)src->data + row * src->rowBytes;
        uint8_t *luma = (uint8_t *)destYp->data + row * destYp->rowBytes;
        for (vImagePixelCount column = 0; column < width; column++) {
            const uint8_t *pixel = in + column * 4;
            float red = (float)pixel[permuteMap[1]], green = (float)pixel[permuteMap[2]], blue = (float)pixel[permuteMap[3]];
            luma[column] = charon_encoded(conversion->Yp_bias + (red * conversion->R_Yp + green * conversion->G_Yp
                                          + blue * conversion->B_Yp) * conversion->yScale, conversion->YpMin, conversion->YpMax);
        }
    }
    for (vImagePixelCount row = 0; row < chromaHeight; row++) {
        uint8_t *cbcr = destCbCr ? (uint8_t *)destCbCr->data + row * destCbCr->rowBytes : NULL;
        uint8_t *cbRow = destCb ? (uint8_t *)destCb->data + row * destCb->rowBytes : NULL;
        uint8_t *crRow = destCr ? (uint8_t *)destCr->data + row * destCr->rowBytes : NULL;
        for (vImagePixelCount column = 0; column < chromaWidth; column++) {
            float blue = 0, red = 0;
            unsigned counted = 0;
            for (vImagePixelCount step = 0; step < 2; step++) {
                vImagePixelCount sourceRow = row * 2 + step;
                if (sourceRow >= height)
                    continue;
                const uint8_t *in = (const uint8_t *)src->data + sourceRow * src->rowBytes;
                for (vImagePixelCount across = 0; across < 2; across++) {
                    vImagePixelCount sourceColumn = column * 2 + across;
                    if (sourceColumn >= width)
                        continue;
                    const uint8_t *pixel = in + sourceColumn * 4;
                    float r = (float)pixel[permuteMap[1]], g = (float)pixel[permuteMap[2]], b = (float)pixel[permuteMap[3]];
                    blue += r * conversion->R_Cb + g * conversion->G_Cb + b * conversion->B_Cb_R_Cr;
                    red += r * conversion->B_Cb_R_Cr + g * conversion->G_Cr + b * conversion->B_Cr;
                    counted++;
                }
            }
            if (counted == 0)
                continue;
            uint8_t cb = charon_encoded(conversion->CbCr_bias + blue * conversion->cScale / (float)counted, conversion->CbCrMin, conversion->CbCrMax);
            uint8_t cr = charon_encoded(conversion->CbCr_bias + red * conversion->cScale / (float)counted, conversion->CbCrMin, conversion->CbCrMax);
            if (cbcr) {
                cbcr[column * 2] = cb;
                cbcr[column * 2 + 1] = cr;
            } else {
                cbRow[column] = cb;
                crRow[column] = cr;
            }
        }
    }
    return kvImageNoError;
}

vImage_Error vImageConvert_ARGB8888To420Yp8_CbCr8(const vImage_Buffer *src, const vImage_Buffer *destYp,
                                                  const vImage_Buffer *destCbCr, const vImage_ARGBToYpCbCr *info,
                                                  const uint8_t permuteMap[4], vImage_Flags flags)
{
    return charon_argb_to_420(src, destYp, NULL, NULL, destCbCr, info, permuteMap, flags);
}

vImage_Error vImageConvert_ARGB8888To420Yp8_Cb8_Cr8(const vImage_Buffer *src, const vImage_Buffer *destYp,
                                                    const vImage_Buffer *destCb, const vImage_Buffer *destCr,
                                                    const vImage_ARGBToYpCbCr *info, const uint8_t permuteMap[4],
                                                    vImage_Flags flags)
{
    return charon_argb_to_420(src, destYp, destCb, destCr, NULL, info, permuteMap, flags);
}

vImage_Error vImageExtractChannel_ARGB8888(const vImage_Buffer *src, const vImage_Buffer *dest, long channelIndex,
                                           vImage_Flags flags)
{
    if (flags & ~charon_vimage_channel_flags)
        return kvImageUnknownFlagsBit;
    if (flags & kvImageGetTempBufferSize)
        return 0;
    if (!src || !dest)
        return kvImageNullPointerArgument;
    if (channelIndex < 0 || channelIndex > 3)
        return kvImageInvalidParameter;
    if (src->width < dest->width || src->height < dest->height)
        return kvImageRoiLargerThanInputBuffer;
    for (vImagePixelCount row = 0; row < dest->height; row++) {
        const uint8_t *in = (const uint8_t *)src->data + row * src->rowBytes;
        uint8_t *out = (uint8_t *)dest->data + row * dest->rowBytes;
        for (vImagePixelCount column = 0; column < dest->width; column++)
            out[column] = in[column * 4 + (size_t)channelIndex];
    }
    return kvImageNoError;
}
