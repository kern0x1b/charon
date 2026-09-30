// Settle a `CIFormat` constant by using it: build a CIImage from a buffer written for *that*
// format's storage type, render it back through a CIContext, and compare the pixels.
//
// One buffer cannot serve all three: RGBA16 is 16-bit unsigned integer per channel, RGBAh is half
// float, RGBAf is 32-bit float, so the bytes of one are not the bytes of another. Each candidate
// therefore gets its own buffer, built by the same conversion CoreImage performs, and its own
// expectation for what must come back.
//
// The format is passed as the dlsym'd integer, never as the compile-time constant, so this tests
// the number the host holds and not the header.
//
// Usage: ci-roundtrip <out.tsv>
#import <CoreImage/CoreImage.h>
#import <dlfcn.h>
#import <math.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

#define WIDTH 4
#define HEIGHT 2

// What must come back, in 8 bits per channel, and in the order CIImage stores it.
// Every alpha is 255: an RGBA8 render is premultiplied, and a buffer with alpha 0 comes back with
// its colour multiplied away, which made every candidate score the same and the test blind.
static const unsigned char expected[HEIGHT][WIDTH][4] = {
    {{255, 128,  64, 255}, {255,   0,   0, 255}, {128, 255,   0, 255}, {  0,   0,   0, 255}},
    {{191,  64, 255, 255}, {255, 255, 255, 255}, { 64, 128, 191, 255}, {255,   0, 128, 255}},
};

typedef uint16_t (*encode_fn)(unsigned char value);

static uint16_t as_uint16(unsigned char value) {
    // 8-bit value -> 16-bit unsigned integer channel: the full-scale value is 65535.
    return (uint16_t)((value * 65535u + 127u) / 255u);
}

static uint16_t as_half(unsigned char value) {
    // 8-bit value -> IEEE binary16, by way of the float the same channel would hold.
    float number = (float)value / 255.0f;
    uint32_t bits;
    memcpy(&bits, &number, sizeof(bits));
    uint16_t sign = (uint16_t)((bits >> 16) & 0x8000);
    int32_t exponent = (int32_t)((bits >> 23) & 0xFF) - 127 + 15;
    uint32_t mantissa = bits & 0x7FFFFF;
    if (exponent <= 0) return sign;
    if (exponent >= 31) return (uint16_t)(sign | 0x7C00);
    return (uint16_t)(sign | (uint16_t)(exponent << 10) | (uint16_t)(mantissa >> 13));
}

static uint16_t as_float_low(unsigned char value) {
    // 32-bit float, the low half of the word; the high half is written separately.
    float number = (float)value / 255.0f;
    uint32_t bits;
    memcpy(&bits, &number, sizeof(bits));
    return (uint16_t)(bits & 0xFFFF);
}

static uint16_t as_float_high(unsigned char value) {
    float number = (float)value / 255.0f;
    uint32_t bits;
    memcpy(&bits, &number, sizeof(bits));
    return (uint16_t)(bits >> 16);
}

static void build_buffer(const char *storage, unsigned char *into) {
    for (int y = 0; y < HEIGHT; ++y) {
        for (int x = 0; x < WIDTH; ++x) {
            for (int c = 0; c < 4; ++c) {
                unsigned char value = expected[y][x][c];
                if (strcmp(storage, "uint16") == 0) {
                    memcpy(into + ((y * WIDTH + x) * 4 + c) * 2, &(uint16_t){as_uint16(value)}, 2);
                } else if (strcmp(storage, "half") == 0) {
                    memcpy(into + ((y * WIDTH + x) * 4 + c) * 2, &(uint16_t){as_half(value)}, 2);
                } else {
                    uint16_t low = as_float_low(value), high = as_float_high(value);
                    memcpy(into + ((y * WIDTH + x) * 4 + c) * 4, &low, 2);
                    memcpy(into + ((y * WIDTH + x) * 4 + c) * 4 + 2, &high, 2);
                }
            }
        }
    }
}

static size_t bytes_per_row(const char *storage) {
    return strcmp(storage, "float32") == 0 ? WIDTH * 16 : WIDTH * 8;
}

@interface CIImage (HostProbe)
// The selector this host has, declared here because the SDK's headers do not carry it. Its
// existence was read off the runtime's own method list, not assumed.
+ (CIImage *)imageWithBitmapData:(NSData *)data
                     bytesPerRow:(size_t)bytesPerRow
                           size:(CGSize)size
                         format:(CIFormat)format
                    colorSpace:(CGColorSpaceRef)colorSpace;
@end

static int roundtrip(int32_t format, const char *storage, int *sampled, int *matched) {
    unsigned char buffer[WIDTH * HEIGHT * 16] = {0};
    build_buffer(storage, buffer);
    NSData *payload = [NSData dataWithBytes:buffer
                                    length:bytes_per_row(storage) * HEIGHT];
    CIImage *image = [CIImage imageWithBitmapData:payload
                                    bytesPerRow:bytes_per_row(storage)
                                          size:CGSizeMake(WIDTH, HEIGHT)
                                        format:(CIFormat)format
                                   colorSpace:NULL];
    if (!image) return -1;
    // A plain context with no working or output colour space, so the render is the decode and
    // nothing else.
    CIContext *context = [CIContext contextWithOptions:nil];
    if (!context) return -1;
    unsigned char out[WIDTH * HEIGHT * 4] = {0};
    [context render:image toBitmap:out rowBytes:WIDTH * 4
             bounds:CGRectMake(0, 0, WIDTH, HEIGHT) format:kCIFormatRGBA8 colorSpace:nil];
    *sampled = *matched = 0;
    for (int y = 0; y < HEIGHT; ++y) {
        for (int x = 0; x < WIDTH; ++x) {
            for (int c = 0; c < 3; ++c) {   // alpha is carried through untouched and not compared
                (*sampled)++;
                if (out[(y * WIDTH + x) * 4 + c] == expected[y][x][c]) (*matched)++;
            }
        }
    }
    return 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: ci-roundtrip <out.tsv>\n"); return 2; }
        void *ci = dlopen("/System/Library/Frameworks/CoreImage.framework/CoreImage", RTLD_LAZY);
        if (!ci) { fprintf(stderr, "no CoreImage on this host\n"); return 1; }
        // Four bytes per constant, measured: each symbol holds its own int32 at offset 0 and the
        // next constant at offset 4.
        struct { const char *name; int32_t code; const char *storage; } candidates[] = {
            {"kCIFormatRGBA16", *(int32_t *)dlsym(ci, "kCIFormatRGBA16"), "uint16"},
            {"kCIFormatRGBAh",  *(int32_t *)dlsym(ci, "kCIFormatRGBAh"),  "half"},
            {"kCIFormatRGBAf",  *(int32_t *)dlsym(ci, "kCIFormatRGBAf"),  "float32"},
        };
        // Codes a header-enumeration parser produces, and one neighbour, here to be shown wrong
        // rather than believed.
        struct { const char *label; int32_t code; const char *storage; } controls[] = {
            {"control: a header parser's 28, as RGBA16", 28, "uint16"},
            {"control: 0x808, as RGBA16", 0x808, "uint16"},
            {"control: a header parser's 28, as RGBAh", 28, "half"},
            {"control: 0x708, as RGBAh", 0x708, "half"},
            {"control: 0x808, as RGBAf", 0x808, "float32"},
            {"control: a header parser's 12, as RGBAf", 12, "float32"},
        };
        FILE *out = fopen(argv[1], "w");
        fprintf(out, "candidate\tvalue\tbuffer\tresult\n");
        for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); ++i) {
            int sampled = 0, matched = 0;
            int ok = roundtrip(candidates[i].code, candidates[i].storage, &sampled, &matched);
            fprintf(out, "%s\t0x%x\t%s\t%s (%d of %d)\n", candidates[i].name,
                    (unsigned)candidates[i].code, candidates[i].storage,
                    ok == 0 ? "round-tripped" : "no image was made", matched, sampled);
        }
        for (size_t i = 0; i < sizeof(controls) / sizeof(controls[0]); ++i) {
            int sampled = 0, matched = 0;
            int ok = roundtrip(controls[i].code, controls[i].storage, &sampled, &matched);
            fprintf(out, "%s\t0x%x\t%s\t%s (%d of %d)\n", controls[i].label,
                    (unsigned)controls[i].code, controls[i].storage,
                    ok == 0 ? "round-tripped" : "no image was made", matched, sampled);
        }
        fclose(out);
    }
    return 0;
}
