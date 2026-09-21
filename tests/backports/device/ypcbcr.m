#import <Foundation/Foundation.h>
#import <Accelerate/Accelerate.h>
#include <dlfcn.h>
#include <math.h>
#include <stdlib.h>
#import "check.h"

static NSString *image_of(const void *address)
{
    Dl_info info;
    return dladdr(address, &info) ? @(info.dli_fname).lastPathComponent : @"?";
}

static vImage_Buffer make(vImagePixelCount width, vImagePixelCount height, unsigned channels)
{
    vImage_Buffer buffer = {NULL, height, width, ((size_t)width * channels + 15) & ~(size_t)15};
    buffer.data = calloc(buffer.rowBytes, height);
    return buffer;
}

static uint32_t seed = 20260921;

static uint8_t next_byte(void)
{
    seed = seed * 1103515245u + 12345u;
    return (uint8_t)((seed >> 16) & 0xFF);
}

int main(void)
{
    @autoreleasepool {
        struct { const char *name; const void *address; } carried[] = {
            {"vImageConvert_YpCbCrToARGB_GenerateConversion", (const void *)&vImageConvert_YpCbCrToARGB_GenerateConversion},
            {"vImageConvert_ARGBToYpCbCr_GenerateConversion", (const void *)&vImageConvert_ARGBToYpCbCr_GenerateConversion},
            {"vImageConvert_420Yp8_CbCr8ToARGB8888", (const void *)&vImageConvert_420Yp8_CbCr8ToARGB8888},
            {"vImageConvert_420Yp8_Cb8_Cr8ToARGB8888", (const void *)&vImageConvert_420Yp8_Cb8_Cr8ToARGB8888},
            {"vImageConvert_ARGB8888To420Yp8_CbCr8", (const void *)&vImageConvert_ARGB8888To420Yp8_CbCr8},
            {"vImageConvert_ARGB8888To420Yp8_Cb8_Cr8", (const void *)&vImageConvert_ARGB8888To420Yp8_Cb8_Cr8},
            {"vImageExtractChannel_ARGB8888", (const void *)&vImageExtractChannel_ARGB8888}
        };
        for (unsigned index = 0; index < sizeof carried / sizeof carried[0]; index++)
            CHECK_EQUAL(image_of(carried[index].address), @"libAccelerateBackports.dylib",
                        ([NSString stringWithFormat:@"%s comes from the backports library", carried[index].name].UTF8String));
        CHECK(kvImage_YpCbCrToARGBMatrix_ITU_R_601_4 != NULL && kvImage_YpCbCrToARGBMatrix_ITU_R_709_2 != NULL
              && kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4 != NULL && kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2 != NULL,
              "the four matrices are there");
        CHECK(kvImage_YpCbCrToARGBMatrix_ITU_R_601_4->Yp == 1.0f
              && fabsf(kvImage_YpCbCrToARGBMatrix_ITU_R_601_4->Cr_R - 1.40199995f) < 1e-7f
              && fabsf(kvImage_YpCbCrToARGBMatrix_ITU_R_601_4->Cb_B - 1.77199996f) < 1e-7f,
              "the 601-4 backward matrix holds the coefficients the newer release holds");
        CHECK(fabsf(kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2->R_Yp - 0.212599993f) < 1e-7f
              && fabsf(kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2->B_Cr + 0.0458470918f) < 1e-7f,
              "the 709-2 forward matrix holds the coefficients the newer release holds");

        vImage_YpCbCrPixelRange range = {16, 128, 235, 240, 255, 0, 255, 1};
        vImage_ARGBToYpCbCr forward;
        vImage_YpCbCrToARGB backward;
        CHECK(vImageConvert_ARGBToYpCbCr_GenerateConversion(kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4, &range, &forward,
                                                            kvImageARGB8888, kvImage420Yp8_CbCr8, kvImageNoFlags) == kvImageNoError,
              "the forward conversion is generated");
        CHECK(vImageConvert_YpCbCrToARGB_GenerateConversion(kvImage_YpCbCrToARGBMatrix_ITU_R_601_4, &range, &backward,
                                                            kvImage420Yp8_CbCr8, kvImageARGB8888, kvImageNoFlags) == kvImageNoError,
              "the backward conversion is generated");
        CHECK(vImageConvert_YpCbCrToARGB_GenerateConversion(kvImage_YpCbCrToARGBMatrix_ITU_R_601_4, &range, &backward,
                                                            kvImage444CrYpCb10, kvImageARGB8888, kvImageNoFlags) == kvImageUnsupportedConversion,
              "a type the port does not carry is refused as unsupported");
        CHECK(vImageConvert_YpCbCrToARGB_GenerateConversion(kvImage_YpCbCrToARGBMatrix_ITU_R_601_4, &range, &backward,
                                                            kvImage420Yp8_CbCr8, kvImageARGB8888, (vImage_Flags)0x40000000) == kvImageUnknownFlagsBit,
              "an unknown flag is refused");
        vImageConvert_YpCbCrToARGB_GenerateConversion(kvImage_YpCbCrToARGBMatrix_ITU_R_601_4, &range, &backward,
                                                      kvImage420Yp8_CbCr8, kvImageARGB8888, kvImageNoFlags);

        const vImagePixelCount width = 34, height = 18;
        const vImagePixelCount chromaWidth = width / 2, chromaHeight = height / 2;
        vImage_Buffer source = make(width, height, 4);
        for (vImagePixelCount row = 0; row < height; row++) {
            uint8_t *line = (uint8_t *)source.data + row * source.rowBytes;
            for (vImagePixelCount column = 0; column < width * 4; column++)
                line[column] = next_byte();
        }
        static const uint8_t permute[4] = {0, 1, 2, 3};
        vImage_Buffer luma = make(width, height, 1), chroma = make(chromaWidth, chromaHeight, 2);
        CHECK(vImageConvert_ARGB8888To420Yp8_CbCr8(&source, &luma, &chroma, &forward, permute, kvImageNoFlags) == kvImageNoError,
              "ARGB becomes 420 with an interleaved chroma plane");

        const vImage_ARGBToYpCbCrMatrix *m = kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4;
        double yScale = (double)(range.YpRangeMax - range.Yp_bias) / 255.0;
        double cScale = 2.0 * (double)(range.CbCrRangeMax - range.CbCr_bias) / 255.0;
        int widest = 0;
        unsigned long apart = 0, counted = 0;
        for (vImagePixelCount row = 0; row < height; row++) {
            const uint8_t *in = (const uint8_t *)source.data + row * source.rowBytes;
            const uint8_t *out = (const uint8_t *)luma.data + row * luma.rowBytes;
            for (vImagePixelCount column = 0; column < width; column++) {
                const uint8_t *pixel = in + column * 4;
                double wanted = range.Yp_bias + (pixel[1] * (double)m->R_Yp + pixel[2] * (double)m->G_Yp
                                                 + pixel[3] * (double)m->B_Yp) * yScale;
                int difference = abs((int)out[column] - (int)lround(wanted));
                counted++;
                if (difference) {
                    apart++;
                    if (difference > widest)
                        widest = difference;
                }
            }
        }
        charon_check(widest <= 1, "every luma byte is the arithmetic of the header, within the last bit",
                     [NSString stringWithFormat:@"%lu of %lu bytes apart, the widest by %d", apart, counted, widest]);

        widest = 0; apart = 0; counted = 0;
        for (vImagePixelCount row = 0; row < chromaHeight; row++) {
            const uint8_t *out = (const uint8_t *)chroma.data + row * chroma.rowBytes;
            for (vImagePixelCount column = 0; column < chromaWidth; column++) {
                double blue = 0, red = 0;
                for (unsigned down = 0; down < 2; down++) {
                    const uint8_t *in = (const uint8_t *)source.data + (row * 2 + down) * source.rowBytes;
                    for (unsigned across = 0; across < 2; across++) {
                        const uint8_t *pixel = in + (column * 2 + across) * 4;
                        blue += pixel[1] * (double)m->R_Cb + pixel[2] * (double)m->G_Cb + pixel[3] * (double)m->B_Cb_R_Cr;
                        red += pixel[1] * (double)m->B_Cb_R_Cr + pixel[2] * (double)m->G_Cr + pixel[3] * (double)m->B_Cr;
                    }
                }
                double wantedCb = range.CbCr_bias + blue * cScale / 4.0;
                double wantedCr = range.CbCr_bias + red * cScale / 4.0;
                int first = abs((int)out[column * 2] - (int)lround(wantedCb));
                int second = abs((int)out[column * 2 + 1] - (int)lround(wantedCr));
                counted += 2;
                if (first) { apart++; if (first > widest) widest = first; }
                if (second) { apart++; if (second > widest) widest = second; }
            }
        }
        charon_check(widest <= 1, "every chroma byte is the mean of its block, within the last bit",
                     [NSString stringWithFormat:@"%lu of %lu bytes apart, the widest by %d", apart, counted, widest]);

        vImage_Buffer picture = make(width, height, 4);
        CHECK(vImageConvert_420Yp8_CbCr8ToARGB8888(&luma, &chroma, &picture, &backward, permute, 0x7F, kvImageNoFlags) == kvImageNoError,
              "420 with an interleaved chroma plane becomes ARGB");
        BOOL alphaKept = YES;
        for (vImagePixelCount row = 0; row < height && alphaKept; row++) {
            const uint8_t *line = (const uint8_t *)picture.data + row * picture.rowBytes;
            for (vImagePixelCount column = 0; column < width; column++)
                if (line[column * 4] != 0x7F) {
                    alphaKept = NO;
                    break;
                }
        }
        CHECK(alphaKept, "the alpha the caller gave is in every pixel");

        vImage_Buffer cb = make(chromaWidth, chromaHeight, 1), cr = make(chromaWidth, chromaHeight, 1);
        vImage_Buffer planarLuma = make(width, height, 1);
        CHECK(vImageConvert_ARGB8888To420Yp8_Cb8_Cr8(&source, &planarLuma, &cb, &cr, &forward, permute, kvImageNoFlags) == kvImageNoError,
              "ARGB becomes 420 with three planes");
        BOOL sameLuma = YES;
        for (vImagePixelCount row = 0; row < height && sameLuma; row++)
            sameLuma = memcmp((const uint8_t *)luma.data + row * luma.rowBytes,
                              (const uint8_t *)planarLuma.data + row * planarLuma.rowBytes, width) == 0;
        CHECK(sameLuma, "the luma is the same whichever chroma layout is asked for");
        BOOL sameChroma = YES;
        for (vImagePixelCount row = 0; row < chromaHeight && sameChroma; row++) {
            const uint8_t *interleaved = (const uint8_t *)chroma.data + row * chroma.rowBytes;
            const uint8_t *blue = (const uint8_t *)cb.data + row * cb.rowBytes;
            const uint8_t *red = (const uint8_t *)cr.data + row * cr.rowBytes;
            for (vImagePixelCount column = 0; column < chromaWidth; column++)
                if (interleaved[column * 2] != blue[column] || interleaved[column * 2 + 1] != red[column]) {
                    sameChroma = NO;
                    break;
                }
        }
        CHECK(sameChroma, "the chroma is the same whichever layout is asked for");

        for (long channel = 0; channel < 4; channel++) {
            vImage_Buffer plane = make(width, height, 1);
            CHECK(vImageExtractChannel_ARGB8888(&source, &plane, channel, kvImageNoFlags) == kvImageNoError,
                  "a channel is extracted");
            BOOL same = YES;
            for (vImagePixelCount row = 0; row < height && same; row++) {
                const uint8_t *in = (const uint8_t *)source.data + row * source.rowBytes;
                const uint8_t *out = (const uint8_t *)plane.data + row * plane.rowBytes;
                for (vImagePixelCount column = 0; column < width; column++)
                    if (out[column] != in[column * 4 + channel]) {
                        same = NO;
                        break;
                    }
            }
            CHECK(same, "the channel is the bytes of the picture");
            free(plane.data);
        }
        vImage_Buffer plane = make(width, height, 1);
        CHECK(vImageExtractChannel_ARGB8888(&source, &plane, 4, kvImageNoFlags) == kvImageInvalidParameter,
              "a channel outside the pixel is refused");
        CHECK(vImageExtractChannel_ARGB8888(&source, &plane, 0, kvImageGetTempBufferSize) == 0,
              "asked for a temporary buffer the function needs none");
        vImage_Buffer bigger = make(width * 2, height, 1);
        CHECK(vImageExtractChannel_ARGB8888(&source, &bigger, 0, kvImageNoFlags) == kvImageRoiLargerThanInputBuffer,
              "a destination wider than the source is refused");

        free(source.data); free(luma.data); free(chroma.data); free(picture.data);
        free(cb.data); free(cr.data); free(planarLuma.data); free(plane.data); free(bigger.data);
        printf("%d of %d checks failed\n", charon_failures, charon_checks);
        return charon_failures;
    }
}
