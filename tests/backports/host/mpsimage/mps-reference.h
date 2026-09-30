// mps-reference.h - the reference the MPSImage cases are checked against, computed from the release's
// own stated formulas and NOT from this port.
//
// WHY A REFERENCE IN C AND NOT THE HOST'S KERNEL. The host cannot be the oracle on this machine: the
// release's own MPSImageThresholdToZero resolves, by dladdr on its encode method, to
//
//   /System/Library/Frameworks/MetalPerformanceShaders.framework/Versions/A/Frameworks/MPSImage.framework/…
//
// and then the process dies with
//
//   '-[AGXG16XFamilyCommandBuffer mtlnext computeCommandEncoderWithDispatchType:]': unrecognized selector
//
// because this host's AGX family does not implement the encoder selector the framework calls. It answers
// nothing here, so the reference is the header's formula, computed in this file, and every registry row for
// this family says so in its reason.
//
// THE FORMULAS, as the headers state them, cited by file and line so a reader can check them:
//
//   MPSImageThreshold.h:194  MPSImageThresholdToZero         dst = src > threshold ? src : 0
//   MPSImageThreshold.h:246  MPSImageThresholdToZeroInverse  dst = src > threshold ? 0 : src
//   MPSImageThreshold.h:141  MPSImageThresholdTruncate       dst = src > threshold ? threshold : src
//   MPSImageThreshold.h:21   MPSImageThresholdBinary         dst = src > threshold ? maximum : 0
//   MPSImageThreshold.h:81   MPSImageThresholdBinaryInverse  dst = src > threshold ? 0 : maximum
//   MPSImageMath.h           MPSImageArithmetic              primary*primaryScale OP secondary*secondaryScale + bias
//
// The comparison is a whole float32 ulp of the expected answer, because these kernels accumulate in double
// and store float32: the difference between "the port is right" and "the port is one rounding off" is
// exactly that, and a tolerance wider than it would hide a real defect while a narrower one would fail
// every case.
#ifndef CHARON_MPS_REFERENCE_H
#define CHARON_MPS_REFERENCE_H

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// Which of the five thresholds a case runs, and which of the four arithmetic operations.
typedef enum {
    CharonRefToZero,
    CharonRefToZeroInverse,
    CharonRefBinary,
    CharonRefBinaryInverse,
    CharonRefTruncate,
} CharonRefThreshold;

typedef enum {
    CharonRefAdd,
    CharonRefSubtract,
    CharonRefMultiply,
    CharonRefDivide,
} CharonRefOperation;

// How many elements have been compared and how many were further than one ulp from the reference. The
// case returns non-zero on any, so a regression cannot pass the harness.
static NSUInteger gCompared = 0;
static NSUInteger gMismatches = 0;

// One float32 ulp at `value`, as a difference. The bit pattern is put in the order that increases with
// magnitude - a negative float's pattern is reflected about zero first - stepped by one, and reflected
// back, so the answer is the spacing on the side of the value where the spacing is. A NaN has no spacing
// and says so; a zero's is the smallest denormal.
static double CharonOneUlp(double value)
{
    float f = (float)value;
    if (!(f == f))
        return (double)NAN;                  // nothing is within any bound of a NaN
    if (f == 0.0f)
        return (double)1.40129846e-45f;      // the smallest denormal
    uint32_t bits;
    memcpy(&bits, &f, sizeof(bits));
    uint32_t negative = bits & 0x80000000u;
    uint32_t magnitude = negative ? ~bits + 1u : bits;   // the value's own order
    uint32_t stepped = magnitude + 1u;
    if (negative)
        stepped = ~stepped + 1u;                          // back into the negative half
    float next;
    memcpy(&next, &stepped, sizeof(next));
    double delta = (double)next - (double)f;
    return delta < 0.0 ? -delta : delta;
}

// The five, as the header's five formulas.
static double CharonReferenceThreshold(CharonRefThreshold which, double src, double threshold, double maximum)
{
    switch (which) {
    case CharonRefToZero: return src > threshold ? src : 0.0;
    case CharonRefToZeroInverse: return src > threshold ? 0.0 : src;
    case CharonRefBinary: return src > threshold ? maximum : 0.0;
    case CharonRefBinaryInverse: return src > threshold ? 0.0 : maximum;
    case CharonRefTruncate: return src > threshold ? threshold : src;
    }
    return src;
}

// The four, at the header's default scales of one and a bias of zero, which is what the cases build.
static double CharonReferenceArithmetic(CharonRefOperation op, double primary, double secondary)
{
    switch (op) {
    case CharonRefAdd: return primary + secondary;
    case CharonRefSubtract: return primary - secondary;
    case CharonRefMultiply: return primary * secondary;
    case CharonRefDivide: return secondary == 0.0 ? 0.0 : primary / secondary;
    }
    return primary;
}

static void CharonRecord(const char *name, NSUInteger index, double want, double got)
{
    gCompared++;
    if (want == 0.0 && got == 0.0)
        return;
    double ulp = CharonOneUlp(want);
    if (fabs(got - want) > ulp) {
        gMismatches++;
        printf("  MISMATCH %s [%lu] reference %.9g port %.9g, one ulp %.3g\n",
               name, (unsigned long)index, want, got, ulp);
    }
}

// CharonCompareUnary: the five threshold cases. `src` is what the case fed in and `out` is what the port
// answered, `n` elements of each.
static void CharonCompareUnary(const char *name, const float *src, NSUInteger n, const float *out,
                              CharonRefThreshold kind, double threshold, double maximum)
{
    printf("reference %s %lu", name, (unsigned long)n);
    for (NSUInteger i = 0; i < n; i++) {
        double want = CharonReferenceThreshold(kind, (double)src[i], threshold, maximum);
        printf(" %.9g", want);
        CharonRecord(name, i, want, (double)out[i]);
    }
    printf("\n");
}

// CharonCompareBinary: the four arithmetic cases, over the two images the case built.
static void CharonCompareBinary(const char *name, const float *primary, const float *secondary,
                                NSUInteger n, const float *out, CharonRefOperation op)
{
    printf("reference %s %lu", name, (unsigned long)n);
    for (NSUInteger i = 0; i < n; i++) {
        double want = CharonReferenceArithmetic(op, (double)primary[i], (double)secondary[i]);
        printf(" %.9g", want);
        CharonRecord(name, i, want, (double)out[i]);
    }
    printf("\n");
}

// CharonReferenceTranspose: the transpose of a region, from the header's own words.
//
//   MPSImageTranspose.h:16   "The MPSImageTranspose transposes an image"
//   MPSImageTranspose.h:18   "This kernel accepts uint and int textures in addition to unorm and
//                            floating-point textures."
//   MPSImageTranspose.h:21   MPSImageTranspose : MPSUnaryImageKernel
//   MPSImageKernel.h:141-144 clipRect "A MTLRegion that indicates which part of the destination to
//                            overwrite. If the clipRect does not lie completely within the destination
//                            image, the intersection between clip rectangle and destination bounds
//                            [is] used. Default: MPSRectNoClip … indicating the entire image."
//
// So: destination(row, column) takes source(column, row), over the intersection of the clip rectangle
// with the destination, and MPSRectNoClip is the whole destination. The header says "transposes" and
// nothing more about the arithmetic - there is none, and this is the whole of what the kernel computes.
//
// The value moves unchanged, so the reference is the same array read at the transposed index: there is no
// arithmetic to differ by an ulp, and `CharonCompareTranspose` therefore compares for equality rather
// than against a bound, and a single bit of difference is a failure.
static void CharonReferenceTranspose(const char *name, const float *src, NSUInteger srcWidth,
                                     NSUInteger srcHeight, const float *out, NSUInteger dstWidth,
                                     NSUInteger dstHeight)
{
    printf("reference %s %lu", name, (unsigned long)(dstWidth * dstHeight));
    for (NSUInteger row = 0; row < dstHeight; row++) {
        for (NSUInteger column = 0; column < dstWidth; column++) {
            double want = (double)src[column * srcWidth + row];
            printf(" %.9g", want);
            gCompared++;
            double got = (double)out[row * dstWidth + column];
            if (got != want) {
                gMismatches++;
                printf("\n  MISMATCH %s destination(%lu,%lu) reference %.9g port %.9g"
                       " (a transpose moves bits, so this is exact)\n",
                       name, (unsigned long)row, (unsigned long)column, want, got);
            }
        }
    }
    printf("\n");
}


// MPSImageCopyToMatrix, from MPSImageCopy.h:19-24: "The MPSImageCopyToMatrix copies image data to a
// MPSMatrix. The image data is stored in a row of a matrix. The dataLayout specifies the order in which
// the feature channels in the MPSImage get stored in the matrix. If MPSImage stores a batch of images,
// the images are copied into multiple rows, one row per image." And the two orders, as MPSImage.h:300-303
// gives them in the surface's own comments:
//   MPSDataLayoutFeatureChannelsxHeightxWidth   [imageNum][featureChannels][imageHeight][imageWidth]
//   MPSDataLayoutHeightxWidthxFeatureChannels   [imageNum][imageHeight][imageWidth][featureChannels]
// The default at MPSImageCopy.h:37 is MPSDataLayoutFeatureChannelsxHeightxWidth.
//
// So image (y, x, channel) lands at element
//   channel * width * height + y * width + x        in MPSDataLayoutFeatureChannelsxHeightxWidth
//   (y * width + x) * channels + channel            in MPSDataLayoutHeightxWidthxFeatureChannels
// in the row the kernel's origin x names, plus the image's own index - one row per image, MPSImageCopy.h:22-23
// - each row `rowElements` long, which MPSImageCopy.h:26-29 requires to be at least width * height *
// featureChannels.
//
// A copy moves the bits, so this compares exactly, like the transpose: one bit of difference is a failure
// and there is no tolerance. `layout` is the order the kernel was asked for, so the same call checks both
// of the header's two orders - and the two differ only where there is more than one feature channel, which
// is why the case's image has two. `originRow` and `originColumn` are the kernel's destinationMatrixOrigin
// of MPSImageCopy.h:23, and the element is read out of the matrix's own row, so a kernel that wrote at the
// wrong place reads back as a mismatch instead of passing.
static void CharonReferenceImageCopyToMatrix(const char *name, const float *src, NSUInteger width,
                                             NSUInteger height, NSUInteger channels, NSUInteger images,
                                             MPSDataLayout layout, NSUInteger originRow, NSUInteger originColumn,
                                             const float *out, NSUInteger rowElements)
{
    NSUInteger perImage = width * height * channels;
    printf("reference %s layout %lu origin %lux%lu %lu", name, (unsigned long)layout,
           (unsigned long)originRow, (unsigned long)originColumn, (unsigned long)(perImage * images));
    for (NSUInteger image = 0; image < images; image++) {
        for (NSUInteger element = 0; element < perImage; element++) {
            NSUInteger y, x, channel;
            if (layout == MPSDataLayoutHeightxWidthxFeatureChannels) {
                channel = element % channels;
                NSUInteger pixel = element / channels;
                y = pixel / width;
                x = pixel % width;
            } else {
                y = (element / width) % height;
                x = element % width;
                channel = element / (width * height);
            }
            float want = src[image * perImage + (y * width + x) * channels + channel];
            gCompared++;
            double got = (double)out[(originRow + image) * rowElements + originColumn + element];
            if (got != (double)want) {
                gMismatches++;
                printf("\n  MISMATCH %s layout %lu image %lu element %lu reference %.9g port %.9g"
                       " (a copy moves bits, so this is exact)\n",
                       name, (unsigned long)layout, (unsigned long)image, (unsigned long)element,
                       (double)want, got);
            }
            printf(" %.9g", (double)want);
        }
    }
    printf("\n");
}

#endif /* CHARON_MPS_REFERENCE_H */
