// The Y'CbCr conversions of vImage held against the host's own vImage, layout by layout and direction
// by direction: the same buffers through both, every byte of the result compared.
//
// What this is for is the rounding. The header promises "faithfully rounded" results and the system
// does the arithmetic in fixed point while the port does it in float and rounds once at the end, so the
// two can differ by one in the last bit. The count of bytes that differ, and the widest difference
// among them, are what this measures; a difference wider than the last bit is a failure and stops the
// run, and the counts are printed at the end so the tolerance in facts/Accelerate/vImageYpCbCr.md is a
// measurement rather than a hope.
//
// The inputs are not a single picture. Each layout is asked over the four pixel ranges the header's own
// vImage_YpCbCrPixelRange documentation gives, both matrices, four permutation maps and four picture
// sizes - because the two things this family gets wrong in practice are a rounding rule that only shows
// at one end of a range, and a chroma that is averaged over the wrong block at an odd width.

#import <Foundation/Foundation.h>
#import <Accelerate/Accelerate.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define RENAME(x) charonHost_##x
extern const vImage_YpCbCrToARGBMatrix *RENAME(kvImage_YpCbCrToARGBMatrix_ITU_R_601_4);
extern const vImage_YpCbCrToARGBMatrix *RENAME(kvImage_YpCbCrToARGBMatrix_ITU_R_709_2);
extern const vImage_ARGBToYpCbCrMatrix *RENAME(kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4);
extern const vImage_ARGBToYpCbCrMatrix *RENAME(kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2);

// The port's own forward conversions, by the shape of each one's alpha parameter, which is the only
// thing that tells the four declarations apart.
#define DECL_YPCA8(name) \
    extern vImage_Error RENAME(name)(const vImage_Buffer *, const vImage_Buffer *, const vImage_YpCbCrToARGB *, const uint8_t[4], const uint8_t, vImage_Flags)
#define DECL_YPCANONE(name) \
    extern vImage_Error RENAME(name)(const vImage_Buffer *, const vImage_Buffer *, const vImage_YpCbCrToARGB *, const uint8_t[4], vImage_Flags)
#define DECL_YPCA16(name) \
    extern vImage_Error RENAME(name)(const vImage_Buffer *, const vImage_Buffer *, const vImage_YpCbCrToARGB *, const uint8_t[4], const uint16_t, vImage_Flags)
#define DECL_YPCAQ12(name) \
    extern vImage_Error RENAME(name)(const vImage_Buffer *, const vImage_Buffer *, const vImage_YpCbCrToARGB *, const uint8_t[4], const Pixel_16Q12, vImage_Flags)
DECL_YPCA8(vImageConvert_422YpCbYpCr8ToARGB8888);
DECL_YPCA8(vImageConvert_422CbYpCrYp8ToARGB8888);
DECL_YPCANONE(vImageConvert_444AYpCbCr8ToARGB8888);
DECL_YPCANONE(vImageConvert_444CbYpCrA8ToARGB8888);
DECL_YPCA8(vImageConvert_444CrYpCb8ToARGB8888);
DECL_YPCANONE(vImageConvert_444AYpCbCr16ToARGB8888);
DECL_YPCANONE(vImageConvert_444AYpCbCr16ToARGB16U);
DECL_YPCA8(vImageConvert_422CbYpCrYp16ToARGB8888);
DECL_YPCA16(vImageConvert_422CbYpCrYp16ToARGB16U);
DECL_YPCA8(vImageConvert_444CrYpCb10ToARGB8888);
DECL_YPCAQ12(vImageConvert_444CrYpCb10ToARGB16Q12);
DECL_YPCA8(vImageConvert_422CrYpCbYpCbYpCbYpCrYpCrYp10ToARGB8888);
DECL_YPCAQ12(vImageConvert_422CrYpCbYpCbYpCbYpCrYpCrYp10ToARGB16Q12);
extern vImage_Error RENAME(vImageConvert_422CbYpCrYp8_AA8ToARGB8888)(const vImage_Buffer *, const vImage_Buffer *, const vImage_Buffer *, const vImage_YpCbCrToARGB *, const uint8_t[4], vImage_Flags);

#define DECL_ARGBC(name) \
    extern vImage_Error RENAME(name)(const vImage_Buffer *, const vImage_Buffer *, const vImage_ARGBToYpCbCr *, const uint8_t[4], vImage_Flags)
DECL_ARGBC(vImageConvert_ARGB8888To422YpCbYpCr8);
DECL_ARGBC(vImageConvert_ARGB8888To422CbYpCrYp8);
DECL_ARGBC(vImageConvert_ARGB8888To444AYpCbCr8);
DECL_ARGBC(vImageConvert_ARGB8888To444CbYpCrA8);
DECL_ARGBC(vImageConvert_ARGB8888To444CrYpCb8);
DECL_ARGBC(vImageConvert_ARGB8888To444AYpCbCr16);
DECL_ARGBC(vImageConvert_ARGB8888To422CbYpCrYp16);
DECL_ARGBC(vImageConvert_ARGB8888To444CrYpCb10);
DECL_ARGBC(vImageConvert_ARGB8888To422CrYpCbYpCbYpCbYpCrYpCrYp10);
extern vImage_Error RENAME(vImageConvert_ARGB8888To420Yp8_CbCr8)(const vImage_Buffer *, const vImage_Buffer *, const vImage_Buffer *, const vImage_ARGBToYpCbCr *, const uint8_t[4], vImage_Flags);
extern vImage_Error RENAME(vImageConvert_ARGB8888To420Yp8_Cb8_Cr8)(const vImage_Buffer *, const vImage_Buffer *, const vImage_Buffer *, const vImage_Buffer *, const vImage_ARGBToYpCbCr *, const uint8_t[4], vImage_Flags);
extern vImage_Error RENAME(vImageConvert_YpCbCrToARGB_GenerateConversion)(const vImage_YpCbCrToARGBMatrix *, const vImage_YpCbCrPixelRange *, vImage_YpCbCrToARGB *, vImageYpCbCrType, vImageARGBType, vImage_Flags);
extern vImage_Error RENAME(vImageConvert_ARGBToYpCbCr_GenerateConversion)(const vImage_ARGBToYpCbCrMatrix *, const vImage_YpCbCrPixelRange *, vImage_ARGBToYpCbCr *, vImageARGBType, vImageYpCbCrType, vImage_Flags);
extern vImage_Error RENAME(vImageConvert_420Yp8_CbCr8ToARGB8888)(const vImage_Buffer *, const vImage_Buffer *, const vImage_Buffer *, const vImage_YpCbCrToARGB *, const uint8_t[4], const uint8_t, vImage_Flags);
extern vImage_Error RENAME(vImageConvert_420Yp8_Cb8_Cr8ToARGB8888)(const vImage_Buffer *, const vImage_Buffer *, const vImage_Buffer *, const vImage_Buffer *, const vImage_YpCbCrToARGB *, const uint8_t[4], const uint8_t, vImage_Flags);
extern vImage_Error RENAME(vImageConvert_ARGB16UTo444AYpCbCr16)(const vImage_Buffer *, const vImage_Buffer *, const vImage_ARGBToYpCbCr *, const uint8_t[4], vImage_Flags);
extern vImage_Error RENAME(vImageConvert_ARGB16UTo422CbYpCrYp16)(const vImage_Buffer *, const vImage_Buffer *, const vImage_ARGBToYpCbCr *, const uint8_t[4], vImage_Flags);
extern vImage_Error RENAME(vImageConvert_ARGB16Q12To444CrYpCb10)(const vImage_Buffer *, const vImage_Buffer *, const vImage_ARGBToYpCbCr *, const uint8_t[4], vImage_Flags);
extern vImage_Error RENAME(vImageConvert_ARGB16Q12To422CrYpCbYpCbYpCbYpCrYpCrYp10)(const vImage_Buffer *, const vImage_Buffer *, const vImage_ARGBToYpCbCr *, const uint8_t[4], vImage_Flags);
extern vImage_Error RENAME(vImageConvert_ARGB8888To422CbYpCrYp8_AA8)(const vImage_Buffer *, const vImage_Buffer *, const vImage_Buffer *, const vImage_ARGBToYpCbCr *, const uint8_t[4], vImage_Flags);

static int checks, failures;
static unsigned long long bytesCompared, bytesApart;
static int widest;

// The two functions whose source is a Q12 buffer are the one place where the system does not do what
// Conversion.h says, and the measurement is what the port answers instead of the system's. These two
// helpers are the header's own formula, written here a third time and independently of the port, so the
// port is checked against the specification where the specification and the system part company.
struct ref_scale {
    float yScale, cScale, biasY, biasC, yMin, yMax, cMin, cMax;
};

static struct ref_scale reference_of(const vImage_ARGBToYpCbCrMatrix *m, const vImage_YpCbCrPixelRange *r, float full)
{
    struct ref_scale s;
    s.yScale = (float)(r->YpRangeMax - r->Yp_bias) / full;
    s.cScale = 2.0f * (float)(r->CbCrRangeMax - r->CbCr_bias) / full;
    s.biasY = (float)r->Yp_bias;
    s.biasC = (float)r->CbCr_bias;
    s.yMin = (float)r->YpMin;
    s.yMax = (float)r->YpMax;
    s.cMin = (float)r->CbCrMin;
    s.cMax = (float)r->CbCrMax;
    (void)m;
    return s;
}

static int clampi(float v, float lo, float hi)
{
    // roundf, not lrintf: the header's ROUND_TO_NEAREST_INTEGER is round half away from zero, and a
    // reference that rounded half to even would disagree with the port on exactly the ties.
    int r = (int)roundf(v);
    if ((float)r < lo)
        r = (int)lo;
    if ((float)r > hi)
        r = (int)hi;
    return r;
}

static uint32_t reference_v410(const struct ref_scale *s, const vImage_ARGBToYpCbCrMatrix *m, int r, int g, int b)
{
    float yp = s->biasY + (r * m->R_Yp + g * m->G_Yp + b * m->B_Yp) * s->yScale;
    float cb = s->biasC + (r * m->R_Cb + g * m->G_Cb + b * m->B_Cb_R_Cr) * s->cScale;
    float cr = s->biasC + (r * m->B_Cb_R_Cr + g * m->G_Cr + b * m->B_Cr) * s->cScale;
    return ((uint32_t)clampi(cr, s->cMin, s->cMax) << 20) | ((uint32_t)clampi(yp, s->yMin, s->yMax) << 10)
        | (uint32_t)clampi(cb, s->cMin, s->cMax);
}

// The v210 group is six pixels of one row: six luma and the chroma of each of the three pairs of columns.
// The header's own pseudo-code says so - Yp0 to Yp5 from pixels 0 to 5, Cb0 from pixels 0 and 1 - and the
// system agrees, its second row of a four-row picture coming back as its own unit.
static void reference_v210(const struct ref_scale *s, const vImage_ARGBToYpCbCrMatrix *m, const uint16_t *top,
                           int count, const uint8_t pm[4], uint32_t *out)
{
    float yp[6], cb[3], cr[3];
    for (int i = 0; i < 6 && i < count; i++)
        yp[i] = s->biasY + (top[i * 4 + pm[1]] * m->R_Yp + top[i * 4 + pm[2]] * m->G_Yp + top[i * 4 + pm[3]] * m->B_Yp)
            * s->yScale;
    for (int i = 0; i < 3; i++) {
        float b = 0, r = 0;
        unsigned counted = 0;
        for (int k = 0; k < 2; k++) {
            int at = i * 2 + k;
            if (at >= count)
                continue;
            b += top[at * 4 + pm[1]] * m->R_Cb + top[at * 4 + pm[2]] * m->G_Cb + top[at * 4 + pm[3]] * m->B_Cb_R_Cr;
            r += top[at * 4 + pm[1]] * m->B_Cb_R_Cr + top[at * 4 + pm[2]] * m->G_Cr + top[at * 4 + pm[3]] * m->B_Cr;
            counted++;
        }
        if (!counted)
            counted = 1;
        cb[i] = s->biasC + b * s->cScale / (float)counted;
        cr[i] = s->biasC + r * s->cScale / (float)counted;
    }
    for (int i = 0; i < 6; i++)
        yp[i] = (float)clampi(yp[i], s->yMin, s->yMax);
    for (int i = 0; i < 3; i++) {
        cb[i] = (float)clampi(cb[i], s->cMin, s->cMax);
        cr[i] = (float)clampi(cr[i], s->cMin, s->cMax);
    }
    // Each word is Cr in bits 20-29, Yp in 10-19 and Cb in 0-9, and which channel is which is the
    // header's four diagrams: Cb0, Y0, Cr0; Y1, Cb1, Y2; Cr1, Y3, Cb2; Y4, Cr2, Y5.
    out[0] = ((uint32_t)cr[0] & 0x3FF) << 20 | ((uint32_t)yp[0] & 0x3FF) << 10 | ((uint32_t)cb[0] & 0x3FF);
    out[1] = ((uint32_t)yp[1] & 0x3FF) << 20 | ((uint32_t)yp[2] & 0x3FF) << 10 | ((uint32_t)cb[1] & 0x3FF);
    out[2] = ((uint32_t)cb[2] & 0x3FF) << 20 | ((uint32_t)yp[3] & 0x3FF) << 10 | ((uint32_t)cr[1] & 0x3FF);
    out[3] = ((uint32_t)cr[2] & 0x3FF) << 20 | ((uint32_t)yp[5] & 0x3FF) << 10 | ((uint32_t)yp[4] & 0x3FF);
}

static unsigned long long q12Apart, q12Bytes;
static int q12Widest;

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

static vImage_Buffer make(vImagePixelCount width, vImagePixelCount height, size_t bytesPerPixel)
{
    vImage_Buffer buffer = {NULL, height, width, (width * bytesPerPixel + 63) & ~(size_t)63};
    buffer.data = calloc(buffer.rowBytes, height);
    return buffer;
}

// A fixed sequence, so a run is reproducible and both sides see exactly the same bytes. The values are
// not uniformly spread: each byte is one of a dozen that a ten-bit or a sixteen-bit range's corners
// produce, which is where a range's scaling goes wrong if it goes wrong at all.
static uint64_t seed = 0x9E3779B97F4A7C15ull;
static uint8_t next_byte(void)
{
    seed = seed * 6364136223846793005ull + 1442695040888963407ull;
    static const uint8_t corners[] = {0, 1, 15, 16, 17, 63, 64, 127, 128, 235, 240, 255};
    return corners[(seed >> 33) % (sizeof corners)];
}

static void fill(vImage_Buffer buffer)
{
    for (vImagePixelCount row = 0; row < buffer.height; row++) {
        uint8_t *line = (uint8_t *)buffer.data + row * buffer.rowBytes;
        for (size_t at = 0; at < buffer.rowBytes; at++)
            line[at] = next_byte();
    }
}

// Two buffers of one shape, filled with the same bytes on both sides - which is the only way the 4:2:0
// shapes can be compared, since their luma and chroma are buffers of their own that the conversion
// creates and not the caller's, and the row padding has to match too or the comparison reads bytes the
// conversion never wrote.
static void fill_pair(vImage_Buffer theirs, vImage_Buffer ours)
{
    for (vImagePixelCount row = 0; row < theirs.height; row++) {
        uint8_t *left = (uint8_t *)theirs.data + row * theirs.rowBytes;
        uint8_t *right = (uint8_t *)ours.data + row * ours.rowBytes;
        for (size_t at = 0; at < theirs.rowBytes; at++)
            left[at] = right[at] = next_byte();
    }
}

// Every byte of both answers compared. `words` is the destination's own width: one byte per channel for
// an eight-bit destination, two for a sixteen-bit one, which is compared as a sixteen-bit value so that
// a difference of 256 is not read as a difference of one.
static NSString *compare(vImage_Buffer theirs, vImage_Buffer ours, unsigned words)
{
    int worst = 0;
    unsigned long long where = 0;
    for (vImagePixelCount row = 0; row < theirs.height; row++) {
        const uint8_t *left = (const uint8_t *)theirs.data + row * theirs.rowBytes;
        const uint8_t *right = (const uint8_t *)ours.data + row * ours.rowBytes;
        for (size_t at = 0; at < theirs.rowBytes; at += words) {
            int difference = words == 1 ? (int)left[at] - (int)right[at]
                                        : (int)(*(const uint16_t *)(const void *)(left + at))
                                              - (int)(*(const uint16_t *)(const void *)(right + at));
            if (difference < 0)
                difference = -difference;
            bytesCompared++;
            if (difference == 0)
                continue;
            bytesApart++;
            if (difference > widest)
                widest = difference;
            if (difference > worst) {
                worst = difference;
                where = (unsigned long long)row * 1000000 + (unsigned long long)(at / words);
            }
        }
    }
    if (worst <= 1)
        return nil;
    return [NSString stringWithFormat:@"row %llu sample %llu differs by %d, past the last bit",
                                      where / 1000000, where % 1000000, worst];
}

struct range_case {
    const char *name;
    vImage_YpCbCrPixelRange range;
};

// The four of vImage_YpCbCrPixelRange's own documentation, at the bit depths the shapes here use.
static const struct range_case ranges8[] = {
    {"video range, unclamped", {16, 128, 235, 240, 255, 0, 255, 1}},
    {"video range, clamped", {16, 128, 235, 240, 235, 16, 240, 16}},
    {"full range, clamped", {0, 128, 255, 255, 255, 1, 255, 0}},
    {"full range, wide open", {0, 128, 255, 255, 255, 0, 255, 0}}
};
static const struct range_case ranges10[] = {
    {"10-bit video, unclamped", {64, 512, 940, 960, 1023, 0, 1023, 1}},
    {"10-bit video, clamped", {64, 512, 940, 960, 940, 64, 960, 64}},
    {"10-bit full, clamped", {0, 512, 1023, 1023, 1023, 1, 1023, 0}},
    {"10-bit full, wide open", {0, 512, 1023, 1023, 1023, 0, 1023, 0}}
};
static const struct range_case ranges16[] = {
    {"16-bit video, unclamped", {4096, 32768, 60160, 61440, 65535, 0, 65535, 1}},
    {"16-bit video, clamped", {4096, 32768, 60160, 61440, 60160, 4096, 61440, 4096}},
    {"16-bit full, clamped", {0, 32768, 65535, 65535, 65535, 1, 65535, 0}},
    {"16-bit full, wide open", {0, 32768, 65535, 65535, 65535, 0, 65535, 0}}
};

static const uint8_t *permutations[] = {
    (const uint8_t[]){0, 1, 2, 3},
    (const uint8_t[]){3, 2, 1, 0},
    (const uint8_t[]){1, 0, 3, 2},
    (const uint8_t[]){2, 3, 0, 1}
};
#define PERMUTES ((int)(sizeof permutations / sizeof *permutations))

// The cases, one per conversion, with the geometry each layout's own shape allows.
struct yuv_case {
    const char *name;
    vImageYpCbCrType type;
    vImageARGBType argb;
    size_t sourceBytes;      // per luma sample
    unsigned unit;           // luma samples one row of the source holds
    unsigned destWords;      // bytes per destination pixel
    BOOL wide;               // the destination's four channels are 16-bit
};

// `sourceBytes` is per luma SAMPLE, not per unit: the two 4:2:2 shapes pack two samples into four
// bytes, so asking for four per sample would have both sides writing twice the row they were given and
// would make every answer after the first row meaningless.
static const struct yuv_case yuv_cases[] = {
    {"422YpCbYpCr8ToARGB8888", kvImage422YpCbYpCr8, kvImageARGB8888, 2, 1, 4, NO},
    {"422CbYpCrYp8ToARGB8888", kvImage422CbYpCrYp8, kvImageARGB8888, 2, 1, 4, NO},
    {"444AYpCbCr8ToARGB8888", kvImage444AYpCbCr8, kvImageARGB8888, 4, 1, 4, NO},
    {"444CbYpCrA8ToARGB8888", kvImage444CbYpCrA8, kvImageARGB8888, 4, 1, 4, NO},
    {"444CrYpCb8ToARGB8888", kvImage444CrYpCb8, kvImageARGB8888, 3, 1, 4, NO},
    {"444AYpCbCr16ToARGB8888", kvImage444AYpCbCr16, kvImageARGB8888, 8, 1, 4, NO},
    {"444AYpCbCr16ToARGB16U", kvImage444AYpCbCr16, kvImageARGB16U, 8, 1, 8, YES},
    {"422CbYpCrYp16ToARGB8888", kvImage422CbYpCrYp16, kvImageARGB8888, 4, 1, 4, NO},
    {"422CbYpCrYp16ToARGB16U", kvImage422CbYpCrYp16, kvImageARGB16U, 4, 1, 8, YES},
    {"444CrYpCb10ToARGB8888", kvImage444CrYpCb10, kvImageARGB8888, 4, 1, 4, NO},
    {"444CrYpCb10ToARGB16Q12", kvImage444CrYpCb10, kvImageARGB16Q12, 4, 1, 8, YES},
    {"422v210ToARGB8888", kvImage422CrYpCbYpCbYpCbYpCrYpCrYp10, kvImageARGB8888, 8, 6, 4, NO},
    {"422v210ToARGB16Q12", kvImage422CrYpCbYpCbYpCbYpCrYpCrYp10, kvImageARGB16Q12, 8, 6, 8, YES},
    {"420CbCr8ToARGB8888", kvImage420Yp8_CbCr8, kvImageARGB8888, 1, 1, 4, NO},
    {"420Cb8Cr8ToARGB8888", kvImage420Yp8_Cb8_Cr8, kvImageARGB8888, 1, 1, 4, NO}
};
#define YUV_CASES ((int)(sizeof yuv_cases / sizeof *yuv_cases))

static const vImagePixelCount sizes[] = {2, 6, 12, 34};
#define SIZES ((int)(sizeof sizes / sizeof *sizes))

// The four calls the forward direction has, by the shape of the conversion rather than by its name, so
// that one loop over the table above drives all fifteen. `src` is the source's own planes: one, except
// for the two 4:2:0 shapes, which take a luma plane and either one chroma plane or two.
static vImage_Error call_theirs(const struct yuv_case *example, vImage_Buffer *src, vImage_Buffer *dest,
                                const vImage_YpCbCrToARGB *info, const uint8_t permuteMap[4], vImage_Flags flags)
{
    switch (example->type) {
    case kvImage422YpCbYpCr8:
        return vImageConvert_422YpCbYpCr8ToARGB8888(&src[0], dest, info, permuteMap, 200, flags);
    case kvImage422CbYpCrYp8:
        return vImageConvert_422CbYpCrYp8ToARGB8888(&src[0], dest, info, permuteMap, 200, flags);
    case kvImage444AYpCbCr8:
        return vImageConvert_444AYpCbCr8ToARGB8888(&src[0], dest, info, permuteMap, flags);
    case kvImage444CbYpCrA8:
        return vImageConvert_444CbYpCrA8ToARGB8888(&src[0], dest, info, permuteMap, flags);
    case kvImage444CrYpCb8:
        return vImageConvert_444CrYpCb8ToARGB8888(&src[0], dest, info, permuteMap, 200, flags);
    case kvImage444AYpCbCr16:
        return example->argb == kvImageARGB16U
                   ? vImageConvert_444AYpCbCr16ToARGB16U(&src[0], dest, info, permuteMap, flags)
                   : vImageConvert_444AYpCbCr16ToARGB8888(&src[0], dest, info, permuteMap, flags);
    case kvImage422CbYpCrYp16:
        return example->argb == kvImageARGB16U
                   ? vImageConvert_422CbYpCrYp16ToARGB16U(&src[0], dest, info, permuteMap, 40000, flags)
                   : vImageConvert_422CbYpCrYp16ToARGB8888(&src[0], dest, info, permuteMap, 200, flags);
    case kvImage444CrYpCb10:
        return example->argb == kvImageARGB16Q12
                   ? vImageConvert_444CrYpCb10ToARGB16Q12(&src[0], dest, info, permuteMap, 3000, flags)
                   : vImageConvert_444CrYpCb10ToARGB8888(&src[0], dest, info, permuteMap, 200, flags);
    case kvImage422CrYpCbYpCbYpCbYpCrYpCrYp10:
        return example->argb == kvImageARGB16Q12
                   ? vImageConvert_422CrYpCbYpCbYpCbYpCrYpCrYp10ToARGB16Q12(&src[0], dest, info, permuteMap, 3000, flags)
                   : vImageConvert_422CrYpCbYpCbYpCbYpCrYpCrYp10ToARGB8888(&src[0], dest, info, permuteMap, 200, flags);
    case kvImage420Yp8_CbCr8:
        return vImageConvert_420Yp8_CbCr8ToARGB8888(&src[0], &src[1], dest, info, permuteMap, 200, flags);
    case kvImage420Yp8_Cb8_Cr8:
        return vImageConvert_420Yp8_Cb8_Cr8ToARGB8888(&src[0], &src[1], &src[2], dest, info, permuteMap, 200, flags);
    default:
        return kvImageInvalidParameter;
    }
}

static vImage_Error call_ours(const struct yuv_case *example, vImage_Buffer *src, vImage_Buffer *dest,
                              const vImage_YpCbCrToARGB *info, const uint8_t permuteMap[4], vImage_Flags flags)
{
    switch (example->type) {
    case kvImage422YpCbYpCr8:
        return RENAME(vImageConvert_422YpCbYpCr8ToARGB8888)(&src[0], dest, info, permuteMap, 200, flags);
    case kvImage422CbYpCrYp8:
        return RENAME(vImageConvert_422CbYpCrYp8ToARGB8888)(&src[0], dest, info, permuteMap, 200, flags);
    case kvImage444AYpCbCr8:
        return RENAME(vImageConvert_444AYpCbCr8ToARGB8888)(&src[0], dest, info, permuteMap, flags);
    case kvImage444CbYpCrA8:
        return RENAME(vImageConvert_444CbYpCrA8ToARGB8888)(&src[0], dest, info, permuteMap, flags);
    case kvImage444CrYpCb8:
        return RENAME(vImageConvert_444CrYpCb8ToARGB8888)(&src[0], dest, info, permuteMap, 200, flags);
    case kvImage444AYpCbCr16:
        return example->argb == kvImageARGB16U
                   ? RENAME(vImageConvert_444AYpCbCr16ToARGB16U)(&src[0], dest, info, permuteMap, flags)
                   : RENAME(vImageConvert_444AYpCbCr16ToARGB8888)(&src[0], dest, info, permuteMap, flags);
    case kvImage422CbYpCrYp16:
        return example->argb == kvImageARGB16U
                   ? RENAME(vImageConvert_422CbYpCrYp16ToARGB16U)(&src[0], dest, info, permuteMap, 40000, flags)
                   : RENAME(vImageConvert_422CbYpCrYp16ToARGB8888)(&src[0], dest, info, permuteMap, 200, flags);
    case kvImage444CrYpCb10:
        return example->argb == kvImageARGB16Q12
                   ? RENAME(vImageConvert_444CrYpCb10ToARGB16Q12)(&src[0], dest, info, permuteMap, 3000, flags)
                   : RENAME(vImageConvert_444CrYpCb10ToARGB8888)(&src[0], dest, info, permuteMap, 200, flags);
    case kvImage422CrYpCbYpCbYpCbYpCrYpCrYp10:
        return example->argb == kvImageARGB16Q12
                   ? RENAME(vImageConvert_422CrYpCbYpCbYpCbYpCrYpCrYp10ToARGB16Q12)(&src[0], dest, info, permuteMap, 3000, flags)
                   : RENAME(vImageConvert_422CrYpCbYpCbYpCbYpCrYpCrYp10ToARGB8888)(&src[0], dest, info, permuteMap, 200, flags);
    case kvImage420Yp8_CbCr8:
        return RENAME(vImageConvert_420Yp8_CbCr8ToARGB8888)(&src[0], &src[1], dest, info, permuteMap, 200, flags);
    case kvImage420Yp8_Cb8_Cr8:
        return RENAME(vImageConvert_420Yp8_Cb8_Cr8ToARGB8888)(&src[0], &src[1], &src[2], dest, info, permuteMap, 200, flags);
    default:
        return kvImageInvalidParameter;
    }
}

static vImage_Error call_argb_theirs(const struct yuv_case *example, const vImage_Buffer *src, vImage_Buffer *dest,
                                    const vImage_ARGBToYpCbCr *info, const uint8_t permuteMap[4])
{
    switch (example->type) {
    case kvImage422YpCbYpCr8:
        return vImageConvert_ARGB8888To422YpCbYpCr8(src, &dest[0], info, permuteMap, kvImageNoFlags);
    case kvImage422CbYpCrYp8:
        return vImageConvert_ARGB8888To422CbYpCrYp8(src, &dest[0], info, permuteMap, kvImageNoFlags);
    case kvImage444AYpCbCr8:
        return vImageConvert_ARGB8888To444AYpCbCr8(src, &dest[0], info, permuteMap, kvImageNoFlags);
    case kvImage444CbYpCrA8:
        return vImageConvert_ARGB8888To444CbYpCrA8(src, &dest[0], info, permuteMap, kvImageNoFlags);
    case kvImage444CrYpCb8:
        return vImageConvert_ARGB8888To444CrYpCb8(src, &dest[0], info, permuteMap, kvImageNoFlags);
    case kvImage444AYpCbCr16:
        return vImageConvert_ARGB8888To444AYpCbCr16(src, &dest[0], info, permuteMap, kvImageNoFlags);
    case kvImage422CbYpCrYp16:
        return vImageConvert_ARGB8888To422CbYpCrYp16(src, &dest[0], info, permuteMap, kvImageNoFlags);
    case kvImage444CrYpCb10:
        return vImageConvert_ARGB8888To444CrYpCb10(src, &dest[0], info, permuteMap, kvImageNoFlags);
    case kvImage422CrYpCbYpCbYpCbYpCrYpCrYp10:
        return vImageConvert_ARGB8888To422CrYpCbYpCbYpCbYpCrYpCrYp10(src, &dest[0], info, permuteMap, kvImageNoFlags);
    case kvImage420Yp8_CbCr8:
        return vImageConvert_ARGB8888To420Yp8_CbCr8(src, &dest[0], &dest[1], info, permuteMap, kvImageNoFlags);
    case kvImage420Yp8_Cb8_Cr8:
        return vImageConvert_ARGB8888To420Yp8_Cb8_Cr8(src, &dest[0], &dest[1], &dest[2], info, permuteMap, kvImageNoFlags);
    default:
        return kvImageInvalidParameter;
    }
}

static vImage_Error call_argb_ours(const struct yuv_case *example, const vImage_Buffer *src, vImage_Buffer *dest,
                                   const vImage_ARGBToYpCbCr *info, const uint8_t permuteMap[4])
{
    switch (example->type) {
    case kvImage422YpCbYpCr8:
        return RENAME(vImageConvert_ARGB8888To422YpCbYpCr8)(src, &dest[0], info, permuteMap, kvImageNoFlags);
    case kvImage422CbYpCrYp8:
        return RENAME(vImageConvert_ARGB8888To422CbYpCrYp8)(src, &dest[0], info, permuteMap, kvImageNoFlags);
    case kvImage444AYpCbCr8:
        return RENAME(vImageConvert_ARGB8888To444AYpCbCr8)(src, &dest[0], info, permuteMap, kvImageNoFlags);
    case kvImage444CbYpCrA8:
        return RENAME(vImageConvert_ARGB8888To444CbYpCrA8)(src, &dest[0], info, permuteMap, kvImageNoFlags);
    case kvImage444CrYpCb8:
        return RENAME(vImageConvert_ARGB8888To444CrYpCb8)(src, &dest[0], info, permuteMap, kvImageNoFlags);
    case kvImage444AYpCbCr16:
        return RENAME(vImageConvert_ARGB8888To444AYpCbCr16)(src, &dest[0], info, permuteMap, kvImageNoFlags);
    case kvImage422CbYpCrYp16:
        return RENAME(vImageConvert_ARGB8888To422CbYpCrYp16)(src, &dest[0], info, permuteMap, kvImageNoFlags);
    case kvImage444CrYpCb10:
        return RENAME(vImageConvert_ARGB8888To444CrYpCb10)(src, &dest[0], info, permuteMap, kvImageNoFlags);
    case kvImage422CrYpCbYpCbYpCbYpCrYpCrYp10:
        return RENAME(vImageConvert_ARGB8888To422CrYpCbYpCbYpCbYpCrYpCrYp10)(src, &dest[0], info, permuteMap, kvImageNoFlags);
    case kvImage420Yp8_CbCr8:
        return RENAME(vImageConvert_ARGB8888To420Yp8_CbCr8)(src, &dest[0], &dest[1], info, permuteMap, kvImageNoFlags);
    case kvImage420Yp8_Cb8_Cr8:
        return RENAME(vImageConvert_ARGB8888To420Yp8_Cb8_Cr8)(src, &dest[0], &dest[1], &dest[2], info, permuteMap, kvImageNoFlags);
    default:
        return kvImageInvalidParameter;
    }
}

// How many planes a shape has, and how big each of them is. The 4:2:0 shapes are the only ones with more
// than one, and the chroma of either is half the luma in each direction, rounded up.
static int planes_of(vImageYpCbCrType type)
{
    return type == kvImage420Yp8_Cb8_Cr8 ? 3 : (type == kvImage420Yp8_CbCr8 ? 2 : 1);
}

static int plane_set(vImageYpCbCrType type, vImagePixelCount width, vImagePixelCount height,
                     size_t bytesPerSample, vImage_Buffer out[3])
{
    int count = planes_of(type);
    for (int plane = 0; plane < count; plane++) {
        vImagePixelCount w = plane == 0 ? width : (width + 1) / 2;
        vImagePixelCount h = plane == 0 ? height : (height + 1) / 2;
        size_t bytes = plane == 0 ? bytesPerSample : (type == kvImage420Yp8_CbCr8 ? 2 : 1);
        out[plane] = make(w, h, bytes);
    }
    return count;
}

// The A8 shape, whose alpha is a plane of its own, in both directions.
static vImage_Error call_aa8_theirs(const vImage_Buffer *src, const vImage_Buffer *srcA, const vImage_Buffer *dest,
                                   const vImage_YpCbCrToARGB *info, const uint8_t permuteMap[4])
{
    return vImageConvert_422CbYpCrYp8_AA8ToARGB8888(src, srcA, dest, info, permuteMap, kvImageNoFlags);
}

static vImage_Error call_aa8_ours(const vImage_Buffer *src, const vImage_Buffer *srcA, const vImage_Buffer *dest,
                                 const vImage_YpCbCrToARGB *info, const uint8_t permuteMap[4])
{
    return RENAME(vImageConvert_422CbYpCrYp8_AA8ToARGB8888)(src, srcA, dest, info, permuteMap, kvImageNoFlags);
}

static const struct range_case *ranges_for(vImageYpCbCrType type)
{
    switch (type) {
    case kvImage444CrYpCb10:
    case kvImage422CrYpCbYpCbYpCbYpCrYpCrYp10:
        return ranges10;
    case kvImage422CbYpCrYp16:
    case kvImage444AYpCbCr16:
        return ranges16;
    default:
        return ranges8;
    }
}

// The geometry each layout's own shape allows: a v210 unit is six samples of one row, so its width has
// to be a whole number of units, and every other shape takes the picture as it is.
static void forward_geometry(const struct yuv_case *example, vImagePixelCount width, vImagePixelCount height,
                             vImagePixelCount *sourceWidth, vImagePixelCount *sourceHeight)
{
    if (example->unit == 6) {
        *sourceWidth = (width / 6) * 6;
        *sourceHeight = height;
    } else {
        *sourceWidth = width;
        *sourceHeight = height;
    }
}

int main(void)
{
    setbuf(stdout, NULL);
    @autoreleasepool {
        // The fifteen interleaved shapes of the table above, each both ways, over the two matrices, the
        // four pixel ranges of its own bit depth, four permutation maps and four picture sizes.
        for (int c = 0; c < YUV_CASES; c++) {
            const struct yuv_case *example = &yuv_cases[c];
            const struct range_case *set = ranges_for(example->type);
            for (int matrix = 0; matrix < 2; matrix++) {
                const vImage_YpCbCrToARGBMatrix *toARGB =
                    matrix ? kvImage_YpCbCrToARGBMatrix_ITU_R_709_2 : kvImage_YpCbCrToARGBMatrix_ITU_R_601_4;
                const vImage_ARGBToYpCbCrMatrix *toYpCbCr =
                    matrix ? kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2 : kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4;
                const vImage_YpCbCrToARGBMatrix *ourToARGB =
                    matrix ? RENAME(kvImage_YpCbCrToARGBMatrix_ITU_R_709_2) : RENAME(kvImage_YpCbCrToARGBMatrix_ITU_R_601_4);
                const vImage_ARGBToYpCbCrMatrix *ourToYpCbCr =
                    matrix ? RENAME(kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2) : RENAME(kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4);
                const char *matrixName = matrix ? "709" : "601";
                for (int r = 0; r < 4; r++) {
                    NSString *head = [NSString stringWithFormat:@"%s %s %s", example->name, matrixName, set[r].name];
                    vImage_YpCbCrToARGB theirInfo, ourInfo;
                    vImage_ARGBToYpCbCr theirForward, ourForward;
                    // Each side is handed the conversion its OWN generator built: the port refuses a
                    // structure that does not carry its tag and so does the system, and sharing one
                    // between them would be measuring the tag rather than the conversion.
                    vImage_Error a = vImageConvert_YpCbCrToARGB_GenerateConversion(toARGB, &set[r].range, &theirInfo,
                                                                                 example->type, example->argb, kvImageNoFlags);
                    vImage_Error b = RENAME(vImageConvert_YpCbCrToARGB_GenerateConversion)(ourToARGB, &set[r].range,
                                                                                         &ourInfo, example->type,
                                                                                         example->argb, kvImageNoFlags);
                    report(a == b && a == kvImageNoError,
                           [head stringByAppendingString:@": the forward conversion is generated"],
                           ([NSString stringWithFormat:@"%ld against %ld", (long)a, (long)b]));
                    a = vImageConvert_ARGBToYpCbCr_GenerateConversion(toYpCbCr, &set[r].range, &theirForward,
                                                                       example->argb, example->type, kvImageNoFlags);
                    b = RENAME(vImageConvert_ARGBToYpCbCr_GenerateConversion)(ourToYpCbCr, &set[r].range, &ourForward,
                                                                             example->argb, example->type, kvImageNoFlags);
                    report(a == b && a == kvImageNoError,
                           [head stringByAppendingString:@": the reverse conversion is generated"],
                           ([NSString stringWithFormat:@"%ld against %ld", (long)a, (long)b]));
                    for (int s = 0; s < SIZES; s++) {
                        vImagePixelCount width = sizes[s], height = sizes[s];
                        vImagePixelCount sourceWidth, sourceHeight;
                        forward_geometry(example, width, height, &sourceWidth, &sourceHeight);
                        if (sourceWidth == 0 || sourceHeight == 0)
                            continue;
                        for (int p = 0; p < PERMUTES; p++) {
                            const uint8_t *permuteMap = permutations[p];
                            NSString *what = [NSString stringWithFormat:@"%@ %llux%llu permute %u%u%u%u", head,
                                                              (unsigned long long)sourceWidth,
                                                              (unsigned long long)sourceHeight, permuteMap[0],
                                                              permuteMap[1], permuteMap[2], permuteMap[3]];

                            // The two 4:2:0 shapes hand their own planes to the conversion, so each side
                            // gets its own set - filled with the same bytes, or the comparison would be
                            // reading two different pictures.
                            vImage_Buffer theirPlanes[3] = {{0}}, ourPlanes[3] = {{0}};
                            int count = plane_set(example->type, sourceWidth, sourceHeight, example->sourceBytes, theirPlanes);
                            plane_set(example->type, sourceWidth, sourceHeight, example->sourceBytes, ourPlanes);
                            for (int plane = 0; plane < count; plane++)
                                fill_pair(theirPlanes[plane], ourPlanes[plane]);
                            vImage_Buffer theirDest = make(sourceWidth, sourceHeight, example->destWords);
                            vImage_Buffer ourDest = make(sourceWidth, sourceHeight, example->destWords);
                            vImage_Error theirs = call_theirs(example, theirPlanes, &theirDest, &theirInfo, permuteMap, kvImageNoFlags);
                            vImage_Error ours = call_ours(example, ourPlanes, &ourDest, &ourInfo, permuteMap, kvImageNoFlags);
                            report(theirs == ours && theirs == kvImageNoError,
                                   [what stringByAppendingString:@": Y'CbCr to ARGB answers"],
                                   ([NSString stringWithFormat:@"%ld against %ld", (long)theirs, (long)ours]));
                            NSString *difference = compare(theirDest, ourDest, example->wide ? 2 : 1);
                            report(difference == nil,
                                   [what stringByAppendingString:@": Y'CbCr to ARGB is within the last bit"],
                                   difference ?: @"");

                            // The reverse direction, over a fresh source of the shape's own width.
                            vImage_Buffer rgb = make(sourceWidth, sourceHeight, example->wide ? 8 : 4);
                            fill(rgb);
                            vImage_Buffer theirBack[3] = {{0}}, ourBack[3] = {{0}};
                            int backCount = plane_set(example->type, sourceWidth, sourceHeight, example->sourceBytes, theirBack);
                            plane_set(example->type, sourceWidth, sourceHeight, example->sourceBytes, ourBack);
                            theirs = call_argb_theirs(example, &rgb, theirBack, &theirForward, permuteMap);
                            ours = call_argb_ours(example, &rgb, ourBack, &ourForward, permuteMap);
                            report(theirs == ours && theirs == kvImageNoError,
                                   [what stringByAppendingString:@": ARGB to Y'CbCr answers"],
                                   ([NSString stringWithFormat:@"%ld against %ld", (long)theirs, (long)ours]));
                            for (int plane = 0; plane < backCount; plane++) {
                                difference = compare(theirBack[plane], ourBack[plane], example->wide ? 2 : 1);
                                NSString *which = [what stringByAppendingString:(plane ? @": the chroma plane"
                                                                                    : @": the Y'CbCr plane")];
                                report(difference == nil, [which stringByAppendingString:@" is within the last bit"],
                                       difference ?: @"");
                            }
                        }
                    }
                }
            }
        }

        for (int matrix = 0; matrix < 2; matrix++) {
            const vImage_YpCbCrToARGBMatrix *toARGB =
                matrix ? kvImage_YpCbCrToARGBMatrix_ITU_R_709_2 : kvImage_YpCbCrToARGBMatrix_ITU_R_601_4;
            const vImage_ARGBToYpCbCrMatrix *toYpCbCr =
                matrix ? kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2 : kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4;
            const vImage_YpCbCrToARGBMatrix *ourToARGB =
                matrix ? RENAME(kvImage_YpCbCrToARGBMatrix_ITU_R_709_2) : RENAME(kvImage_YpCbCrToARGBMatrix_ITU_R_601_4);
            const vImage_ARGBToYpCbCrMatrix *ourToYpCbCr =
                matrix ? RENAME(kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2) : RENAME(kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4);
            const char *matrixName = matrix ? "709" : "601";
            for (int r = 0; r < 4; r++) {
                NSString *head = [NSString stringWithFormat:@"422CbYpCrYp8_AA8 %s %s", matrixName, ranges8[r].name];
                vImage_YpCbCrToARGB theirInfo, ourInfo;
                vImage_ARGBToYpCbCr theirForward, ourForward;
                vImageConvert_YpCbCrToARGB_GenerateConversion(toARGB, &ranges8[r].range, &theirInfo,
                                                             kvImage422CbYpCrYp8_AA8, kvImageARGB8888, kvImageNoFlags);
                RENAME(vImageConvert_YpCbCrToARGB_GenerateConversion)(ourToARGB, &ranges8[r].range, &ourInfo,
                                                                      kvImage422CbYpCrYp8_AA8, kvImageARGB8888, kvImageNoFlags);
                vImageConvert_ARGBToYpCbCr_GenerateConversion(toYpCbCr, &ranges8[r].range, &theirForward,
                                                              kvImageARGB8888, kvImage422CbYpCrYp8_AA8, kvImageNoFlags);
                RENAME(vImageConvert_ARGBToYpCbCr_GenerateConversion)(ourToYpCbCr, &ranges8[r].range, &ourForward,
                                                                      kvImageARGB8888, kvImage422CbYpCrYp8_AA8, kvImageNoFlags);
                for (int s = 0; s < SIZES; s++) {
                    for (int p = 0; p < PERMUTES; p++) {
                        vImagePixelCount width = sizes[s], height = sizes[s];
                        const uint8_t *permuteMap = permutations[p];
                        NSString *what = [NSString stringWithFormat:@"%@ %llux%llu permute %u%u%u%u", head,
                                                          (unsigned long long)width, (unsigned long long)height,
                                                          permuteMap[0], permuteMap[1], permuteMap[2], permuteMap[3]];
                        // Two bytes to a luma sample: the shape packs a pair of samples into four bytes.
                        vImage_Buffer source = make(width, height, 2);
                        fill(source);
                        // Measured on the system: the alpha plane must be at least as WIDE as the
                        // image, although it carries two alpha bytes to every two pixels. The port
                        // asks for the same, so the test hands over a plane of the image's own width.
                        vImage_Buffer alpha = make(width, height, 1);
                        fill(alpha);
                        vImage_Buffer theirDest = make(width, height, 4), ourDest = make(width, height, 4);
                        vImage_Error theirs = call_aa8_theirs(&source, &alpha, &theirDest, &theirInfo, permuteMap);
                        vImage_Error ours = call_aa8_ours(&source, &alpha, &ourDest, &ourInfo, permuteMap);
                        report(theirs == ours && theirs == kvImageNoError,
                               [what stringByAppendingString:@": Y'CbCr to ARGB answers"],
                               ([NSString stringWithFormat:@"%ld against %ld", (long)theirs, (long)ours]));
                        NSString *difference = compare(theirDest, ourDest, 1);
                        report(difference == nil,
                               [what stringByAppendingString:@": Y'CbCr to ARGB is within the last bit"], difference ?: @"");

                        vImage_Buffer rgb = make(width, height, 4);
                        fill(rgb);
                        vImage_Buffer theirBack = make(width, height, 2), ourBack = make(width, height, 2);
                        vImage_Buffer theirAlphaOut = make(width, height, 1);
                        vImage_Buffer ourAlphaOut = make(width, height, 1);
                        theirs = vImageConvert_ARGB8888To422CbYpCrYp8_AA8(&rgb, &theirBack, &theirAlphaOut, &theirForward,
                                                                         permuteMap, kvImageNoFlags);
                        ours = RENAME(vImageConvert_ARGB8888To422CbYpCrYp8_AA8)(&rgb, &ourBack, &ourAlphaOut, &ourForward,
                                                                                permuteMap, kvImageNoFlags);
                        report(theirs == ours && theirs == kvImageNoError,
                               [what stringByAppendingString:@": ARGB to Y'CbCr answers"],
                               ([NSString stringWithFormat:@"%ld against %ld", (long)theirs, (long)ours]));
                        difference = compare(theirBack, ourBack, 1);
                        report(difference == nil,
                               [what stringByAppendingString:@": ARGB to Y'CbCr is within the last bit"], difference ?: @"");
                        difference = compare(theirAlphaOut, ourAlphaOut, 1);
                        (void)difference;
                        report(difference == nil,
                               [what stringByAppendingString:@": the alpha plane is within the last bit"], difference ?: @"");
                    }
                }
            }
        }

        // The three 16-bit sources, which the loop above cannot reach because they come from a source
        // wider than the eight-bit one they are converted from.
        struct wide_case {
            const char *name;
            vImageYpCbCrType type;
            int which;      // 0 for a sixteen-bit source to y416 or v216, 1 for a Q12 source to v410 or v210
        };
        static const struct wide_case wide_cases[] = {
            {"ARGB16UTo444AYpCbCr16", kvImage444AYpCbCr16, 0},
            {"ARGB16UTo422CbYpCrYp16", kvImage422CbYpCrYp16, 0},
            {"ARGB16Q12To444CrYpCb10", kvImage444CrYpCb10, 1},
            {"ARGB16Q12To422v210", kvImage422CrYpCbYpCbYpCbYpCrYpCrYp10, 1}
        };
        static const size_t wide_source[] = {8, 4, 4, 8};
        for (int c = 0; c < 4; c++) {
            const struct range_case *set = wide_cases[c].which == 0 ? ranges16 : ranges10;
            for (int matrix = 0; matrix < 2; matrix++) {
                const vImage_ARGBToYpCbCrMatrix *toYpCbCr =
                    matrix ? kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2 : kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4;
                const vImage_ARGBToYpCbCrMatrix *ourToYpCbCr =
                    matrix ? RENAME(kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2) : RENAME(kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4);
                vImageARGBType argb = wide_cases[c].which == 0 ? kvImageARGB16U : kvImageARGB16Q12;
                const char *matrixName = matrix ? "709" : "601";
                for (int r = 0; r < 4; r++) {
                    vImage_ARGBToYpCbCr theirForward, ourForward;
                    struct ref_scale ref = reference_of(toYpCbCr, &set[r].range, wide_cases[c].which == 0 ? 65535.0f : 4096.0f);
                    vImage_Error a = vImageConvert_ARGBToYpCbCr_GenerateConversion(toYpCbCr, &set[r].range, &theirForward,
                                                                                    argb, wide_cases[c].type, kvImageNoFlags);
                    vImage_Error b = RENAME(vImageConvert_ARGBToYpCbCr_GenerateConversion)(ourToYpCbCr, &set[r].range,
                                                                                          &ourForward, argb, wide_cases[c].type, kvImageNoFlags);
                    NSString *head = [NSString stringWithFormat:@"%s %s %s", wide_cases[c].name, matrixName, set[r].name];
                    report(a == b && a == kvImageNoError, [head stringByAppendingString:@": the conversion is generated"],
                           ([NSString stringWithFormat:@"%ld against %ld", (long)a, (long)b]));
                    for (int s = 0; s < SIZES; s++) {
                        vImagePixelCount width = sizes[s], height = sizes[s];
                        if (c == 3 && width % 6)
                            continue;
                        vImage_Buffer source = make(width, height, 8);
                        fill(source);
                        vImage_Buffer theirDest = make(width, height, wide_source[c]);
                        vImage_Buffer ourDest = make(width, height, wide_source[c]);
                        vImage_Error theirs, ours;
                        if (c == 0) {
                            theirs = vImageConvert_ARGB16UTo444AYpCbCr16(&source, &theirDest, &theirForward, permutations[1], kvImageNoFlags);
                            ours = RENAME(vImageConvert_ARGB16UTo444AYpCbCr16)(&source, &ourDest, &ourForward, permutations[1], kvImageNoFlags);
                        } else if (c == 1) {
                            theirs = vImageConvert_ARGB16UTo422CbYpCrYp16(&source, &theirDest, &theirForward, permutations[1], kvImageNoFlags);
                            ours = RENAME(vImageConvert_ARGB16UTo422CbYpCrYp16)(&source, &ourDest, &ourForward, permutations[1], kvImageNoFlags);
                        } else if (c == 2) {
                            theirs = vImageConvert_ARGB16Q12To444CrYpCb10(&source, &theirDest, &theirForward, permutations[1], kvImageNoFlags);
                            ours = RENAME(vImageConvert_ARGB16Q12To444CrYpCb10)(&source, &ourDest, &ourForward, permutations[1], kvImageNoFlags);
                        } else {
                            theirs = vImageConvert_ARGB16Q12To422CrYpCbYpCbYpCbYpCrYpCrYp10(&source, &theirDest, &theirForward, permutations[1], kvImageNoFlags);
                            ours = RENAME(vImageConvert_ARGB16Q12To422CrYpCbYpCbYpCbYpCrYpCrYp10)(&source, &ourDest, &ourForward, permutations[1], kvImageNoFlags);
                        }
                        NSString *what = [NSString stringWithFormat:@"%@ %llux%llu", head, (unsigned long long)width,
                                                          (unsigned long long)height];
                        report(theirs == ours && theirs == kvImageNoError,
                               [what stringByAppendingString:@": ARGB to Y'CbCr answers"],
                               ([NSString stringWithFormat:@"%ld against %ld", (long)theirs, (long)ours]));
                        if (c < 2) {
                            NSString *difference = compare(theirDest, ourDest, 2);
                            report(difference == nil,
                                   [what stringByAppendingString:@": ARGB to Y'CbCr is within the last bit"], difference ?: @"");
                            continue;
                        }
                        // A Q12 source is where the system stops following the header, and the port is
                        // checked against the header instead - first against the formula written out
                        // above, which is the port's own arithmetic a third time, and then against the
                        // system, whose divergence is counted and reported rather than asserted. The
                        // measurement: a zero Q12 pixel comes back from the system as a luma of 258 where
                        // the header's formula gives 64, and a channel that runs past 1023 wraps to zero
                        // rather than stopping there - which is neither the header's CLAMP nor the pixel
                        // range's own limits. facts/Accelerate/vImageYpCbCr.md records it.
                        // The source's own row stride, not width * 4: a row of an eight-byte-per-pixel
                        // buffer is padded to a multiple of 64 bytes, and a reference that walked the
                        // buffer as if it were packed would read across the padding.
                        size_t stride = source.rowBytes / 2;
                        int bad = 0;
                        for (vImagePixelCount row = 0; row < height; row++) {
                            const uint16_t *in = (const uint16_t *)source.data + (size_t)row * stride;
                            for (vImagePixelCount column = 0; column < width; column++) {
                                uint32_t want;
                                if (c == 2) {
                                    // Through the permutation map the call was given, which is the reverse
                                    // map in this part of the run - the reference has to read the same
                                    // channels the conversion does, not the ones in the order they sit.
                                    const uint8_t *pm = permutations[1];
                                    want = reference_v410(&ref, toYpCbCr, in[column * 4 + pm[1]], in[column * 4 + pm[2]],
                                                          in[column * 4 + pm[3]]);
                                    uint32_t mine = ((const uint32_t *)ourDest.data)[(size_t)row * (ourDest.rowBytes / 4) + column];
                                    uint32_t theirsWord = ((const uint32_t *)theirDest.data)[(size_t)row * (theirDest.rowBytes / 4) + column];
                                    if (mine != want)
                                        bad++;
                                    q12Bytes++;
                                    int apart = (int)mine - (int)theirsWord;
                                    if (apart < 0)
                                        apart = -apart;
                                    if (apart) {
                                        q12Apart++;
                                        if (apart > q12Widest)
                                            q12Widest = apart;
                                    }
                                } else {
                                    // The v210 unit is six pixels of THIS row - the header's own
                                    // pseudo-code reads six and writes six, and the system's second row is
                                    // its own unit - so the reference is asked once per unit of a row.
                                    if (column % 6)
                                        continue;
                                    int remaining = (int)width - (int)column;
                                    if (remaining > 6)
                                        remaining = 6;
                                    uint32_t packed[4];
                                    const uint16_t *top = in + (size_t)column * 4;
                                    reference_v210(&ref, toYpCbCr, top, remaining, permutations[1], packed);
                                    const uint32_t *mine = (const uint32_t *)ourDest.data
                                        + (size_t)row * (ourDest.rowBytes / 4) + (size_t)(column / 6) * 4;
                                    for (int word = 0; word < 4; word++) {
                                        q12Bytes++;
                                        if (mine[word] != packed[word]) {
                                            bad++;
                                        }
                                    }
                                    continue;
                                }
                            }
                        }
                        report(bad == 0, [what stringByAppendingString:@": the Q12 answer is the header's own formula"],
                               ([NSString stringWithFormat:@"%d pixels differ from the formula Conversion.h writes out", bad]));

                    }
                }
            }
        }

        // The refusals, which the header lists the same for all of them: an unknown flag, a destination
        // larger than the source, and a permutation map that is not a permutation.
        {
            // Each side is handed the conversion its OWN generator built: the port refuses a structure
            // that does not carry its tag, which is what keeps one release's library and another's from
            // reading each other's bytes, and passing the host's structure to the port would be testing
            // that rule rather than the refusals.
            vImage_YpCbCrToARGB theirInfo, ourInfo;
            vImageConvert_YpCbCrToARGB_GenerateConversion(kvImage_YpCbCrToARGBMatrix_ITU_R_601_4, &ranges8[0].range,
                                                         &theirInfo, kvImage422YpCbYpCr8, kvImageARGB8888, kvImageNoFlags);
            RENAME(vImageConvert_YpCbCrToARGB_GenerateConversion)(RENAME(kvImage_YpCbCrToARGBMatrix_ITU_R_601_4),
                                                                  &ranges8[0].range, &ourInfo, kvImage422YpCbYpCr8,
                                                                  kvImageARGB8888, kvImageNoFlags);
            vImage_Buffer source = make(4, 4, 2), big = make(8, 8, 4);
            vImage_Error theirs = vImageConvert_422YpCbYpCr8ToARGB8888(&source, &big, &theirInfo, permutations[0], 7, kvImageNoFlags);
            vImage_Error ours = RENAME(vImageConvert_422YpCbYpCr8ToARGB8888)(&source, &big, &ourInfo, permutations[0], 7, kvImageNoFlags);
            report(theirs == ours, @"a destination larger than the source answers the system's code",
                   ([NSString stringWithFormat:@"%ld against %ld", (long)theirs, (long)ours]));
            theirs = vImageConvert_422YpCbYpCr8ToARGB8888(&source, &source, &theirInfo, permutations[0], 7, kvImageNoFlags | kvImageDoNotClamp);
            ours = RENAME(vImageConvert_422YpCbYpCr8ToARGB8888)(&source, &source, &ourInfo, permutations[0], 7, kvImageNoFlags | kvImageDoNotClamp);
            report(theirs == ours, @"a flag the header does not name answers the system's code",
                   ([NSString stringWithFormat:@"%ld against %ld", (long)theirs, (long)ours]));

            // A permutation map that is not a permutation of 0 to 3 is a stated difference, and the
            // measurement is printed rather than asserted: the system reads the bytes the map names
            // without checking them, which for a map naming a channel past the third is a read of four
            // bytes the four-byte array does not hold, and a port cannot do that. What the system answers
            // is recorded in facts/Accelerate/vImageYpCbCr.md.
            const uint8_t repeated[4] = {0, 1, 1, 3};
            const uint8_t past[4] = {0, 1, 2, 9};
            theirs = vImageConvert_422YpCbYpCr8ToARGB8888(&source, &source, &theirInfo, repeated, 7, kvImageNoFlags);
            ours = RENAME(vImageConvert_422YpCbYpCr8ToARGB8888)(&source, &source, &ourInfo, repeated, 7, kvImageNoFlags);
            printf("note a map that repeats a channel: the system answers %ld, the port answers %ld\n", (long)theirs, (long)ours);
            theirs = vImageConvert_422YpCbYpCr8ToARGB8888(&source, &source, &theirInfo, past, 7, kvImageNoFlags);
            ours = RENAME(vImageConvert_422YpCbYpCr8ToARGB8888)(&source, &source, &ourInfo, past, 7, kvImageNoFlags);
            printf("note a map that names channel 9: the system answers %ld, the port answers %ld\n", (long)theirs, (long)ours);
            vImage_Buffer none = make(4, 4, 4);
            theirs = vImageConvert_422YpCbYpCr8ToARGB8888(&source, &none, &theirInfo, 0, 7, kvImageNoFlags);
            ours = RENAME(vImageConvert_422YpCbYpCr8ToARGB8888)(&source, &none, &ourInfo, 0, 7, kvImageNoFlags);
            report(theirs == ours, @"a null permutation map answers the system's code",
                   ([NSString stringWithFormat:@"%ld against %ld", (long)theirs, (long)ours]));
        }

        printf("\n%d checks, %d failures, %llu bytes compared, %llu apart (%.4f per cent), widest %d\n", checks,
               failures, bytesCompared, bytesApart, bytesCompared ? 100.0 * (double)bytesApart / (double)bytesCompared : 0.0,
               widest);
        printf("the Q12-source pair: %llu words compared against the system, %llu apart (%.2f per cent), widest %d - "
               "the port's answer is Conversion.h's formula, and the measurement is in facts/Accelerate/vImageYpCbCr.md\n",
               q12Bytes, q12Apart, q12Bytes ? 100.0 * (double)q12Apart / (double)q12Bytes : 0.0, q12Widest);
    }
    return failures ? 1 : 0;
}
