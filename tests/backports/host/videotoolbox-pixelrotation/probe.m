// probe.m - the oracle for VideoToolbox's pixel rotation family: what this Mac's own
// VTPixelRotationSession does, per angle and per flip, COMPARED AGAINST AN INDEPENDENT EXPECTATION.
//
// WHY THE EXPECTATION IS COMPUTED HERE AND NOT READ OFF APPLE: a differential that compares the port with
// the host proves the port equals the host, and a harness that compares the host with whatever the host
// did proves nothing. So every cell's expected pixels are derived from the source pattern alone, printed,
// and only then compared with Apple's.
//
// THREE FAULTS THIS FILE EXISTS TO NOT REPEAT, all of which cost a probe earlier in this family:
//   1. THE PROPERTY'S VALUE IS A CFStringRef, NOT A NUMBER. VTPixelRotationProperties.h:32 says
//      "Specifies the amount of rotation in degrees" and then, seven lines later, declares the property as
//      CFStringRef with the valid values kVTRotation_0, kVTRotation_CW90, kVTRotation_180 and
//      kVTRotation_CCW90. A probe that sets an NSNumber has its set REJECTED, the session keeps its
//      default of kVTRotation_0, and every angle then reads as the identity. The status the set returns is
//      printed here, and the value is read back, so a rejection cannot pass unnoticed again.
//   2. ROWS ARE WRITTEN AND READ AT THE BUFFER'S OWN bytesPerRow. CVPixelBufferCreate hands a 2-pixel-wide
//      BGRA image a bytesPerRow of 64, and writing 16 contiguous bytes puts the second image row at offset
//      16 - outside the image.
//   3. THE EXPECTATION IS AS BIG AS THE DESTINATION. A 2x4 source rotated by 90 or 270 gives a 4x2
//      destination, which is EIGHT values; sizing the expectation at four compares the top row and calls
//      the rest agreement.
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

#define SRC_WIDTH  2
#define SRC_HEIGHT 4
#define MAX_PIXELS (SRC_WIDTH * SRC_HEIGHT)

static int b_value(int index) { return 10 * index + 1; }   /* unique per pixel, and never 0xAB */

static void describe(const char *label, CVPixelBufferRef buffer)
{
    if (!buffer) { printf("%-10s (none)\n", label); return; }
    printf("%-10s %zux%zu bytesPerRow=%zu format=%c%c%c%c\n", label,
           CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer),
           CVPixelBufferGetBytesPerRow(buffer),
           (char)(CVPixelBufferGetPixelFormatType(buffer) >> 24 & 0xFF),
           (char)(CVPixelBufferGetPixelFormatType(buffer) >> 16 & 0xFF),
           (char)(CVPixelBufferGetPixelFormatType(buffer) >> 8 & 0xFF),
           (char)(CVPixelBufferGetPixelFormatType(buffer) & 0xFF));
}

// The destination's GEOMETRY, from the rotation alone. Fault 3's sibling: deriving this from a pixel
// COUNT gives 4x2 for 0 and 180 as well as for 90 and 270, because a 2x4 source rotated by nothing still
// has eight pixels. Apple then scale-to-fits instead of rotating, and the result is the interpolated
// 9 12 18 21 that made this look like a broken rotation in the first place. Only 90 and 270 transpose.
static void geometry(CFStringRef rotation, size_t *outWidth, size_t *outHeight)
{
    int quarter = CFEqual(rotation, kVTRotation_CW90) || CFEqual(rotation, kVTRotation_CCW90);
    *outWidth = quarter ? SRC_HEIGHT : SRC_WIDTH;
    *outHeight = quarter ? SRC_WIDTH : SRC_HEIGHT;
}

// What the destination's B channels must be, from the source pattern alone.
//   90  (clockwise):      dest(x,y) = src(y, H-1-x)
//   180:                 dest(x,y) = src(W-1-x, H-1-y)
//   270 (counter-clock): dest(x,y) = src(W-1-y, x)
// The two flips apply AFTER the rotation, which is what VTPixelRotationProperties.h:50 and :61 say, and
// "after" has to mean ON THE DESTINATION AXES. Mirroring the SOURCE coordinates instead agrees with Apple
// for 0 and for 180 - where no axis is swapped - and disagrees for every quarter turn with ONE flip,
// because transposing and then mirroring the source is not the same as mirroring the destination. That is
// what four of the sixteen cells were showing: got 1 21 41 61 11 31 51 71 against want 71 51 31 11 61 41
// 21 1, which is the same eight values in the opposite order. So the flips invert the DESTINATION
// coordinate first, and the rotation then maps that to the source.
static int expected(CFStringRef rotation, int flipH, int flipV, int out[MAX_PIXELS])
{
    size_t outWidth, outHeight;
    geometry(rotation, &outWidth, &outHeight);
    for (size_t y = 0; y < outHeight; y++)
        for (size_t y = 0; y < outHeight; y++) {
        for (size_t x = 0; x < outWidth; x++) {
            // The flips invert the DESTINATION coordinate; the rotation then takes it to the source.
            int px = flipH ? (int)outWidth - 1 - (int)x : (int)x;
            int py = flipV ? (int)outHeight - 1 - (int)y : (int)y;
            int sx, sy;
            if (CFEqual(rotation, kVTRotation_CW90))       { sx = py;                sy = SRC_HEIGHT - 1 - px; }
            else if (CFEqual(rotation, kVTRotation_180))    { sx = SRC_WIDTH - 1 - px; sy = SRC_HEIGHT - 1 - py; }
            else if (CFEqual(rotation, kVTRotation_CCW90))  { sx = SRC_WIDTH - 1 - py; sy = px; }
            else                                            { sx = px;                sy = py; }
            out[y * outWidth + x] = b_value(sy * SRC_WIDTH + sx);
        }
    }
    return (int)(outWidth * outHeight);
}

static CVPixelBufferRef make_source(OSType format)
{
    CVPixelBufferRef buffer = NULL;
    if (CVPixelBufferCreate(kCFAllocatorDefault, SRC_WIDTH, SRC_HEIGHT, format, NULL, &buffer) != kCVReturnSuccess)
        return NULL;
    CVPixelBufferLockBaseAddress(buffer, 0);
    uint8_t *base = (uint8_t *)CVPixelBufferGetBaseAddress(buffer);
    size_t stride = CVPixelBufferGetBytesPerRow(buffer);
    for (int y = 0; y < SRC_HEIGHT; y++)
        for (int x = 0; x < SRC_WIDTH; x++) {
            uint8_t *pixel = base + y * stride + x * 4;
            pixel[0] = (uint8_t)b_value(y * SRC_WIDTH + x); pixel[1] = 0; pixel[2] = 0; pixel[3] = 255;
        }
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    return buffer;
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);   /* a run that aborts must still have printed the cell that did it */
    OSType format = kCVPixelFormatType_32BGRA;
    CVPixelBufferRef source = make_source(format);
    if (!source) { printf("no source buffer\n"); return 1; }

    // THE HAND-COMPUTED CHECK, written out longhand before any code is trusted. Source row-major is
    // 1 11 / 21 31 / 41 51 / 61 71, so 180 must read it upside down: 71 61 / 51 41 / 31 21 / 11 1.
    const int hand180[MAX_PIXELS] = { 71, 61, 51, 41, 31, 21, 11, 1 };
    int computed180[MAX_PIXELS];
    int n = expected(kVTRotation_180, 0, 0, computed180);
    int handAgrees = 1;
    for (int i = 0; i < n; i++) if (hand180[i] != computed180[i]) handAgrees = 0;
    printf("HANDCHECK 180: hand-written %d %d %d %d %d %d %d %d | computed %d %d %d %d %d %d %d %d | %s\n",
           hand180[0], hand180[1], hand180[2], hand180[3], hand180[4], hand180[5], hand180[6], hand180[7],
           computed180[0], computed180[1], computed180[2], computed180[3],
           computed180[4], computed180[5], computed180[6], computed180[7],
           handAgrees ? "AGREE" : "DISAGREE - the expectation is wrong before Apple is asked");
    describe("source", source);

    const struct { CFStringRef rotation; const char *name; int flipH, flipV; } cells[] = {
        {kVTRotation_0, "0", 0, 0}, {kVTRotation_CW90, "CW90", 0, 0},
        {kVTRotation_180, "180", 0, 0}, {kVTRotation_CCW90, "CCW90", 0, 0},
        {kVTRotation_0, "0", 1, 0}, {kVTRotation_0, "0", 0, 1}, {kVTRotation_0, "0", 1, 1},
        {kVTRotation_CW90, "CW90", 1, 0}, {kVTRotation_CW90, "CW90", 0, 1}, {kVTRotation_CW90, "CW90", 1, 1},
        {kVTRotation_180, "180", 1, 0}, {kVTRotation_180, "180", 0, 1}, {kVTRotation_180, "180", 1, 1},
        {kVTRotation_CCW90, "CCW90", 1, 0}, {kVTRotation_CCW90, "CCW90", 0, 1},
        {kVTRotation_CCW90, "CCW90", 1, 1},
    };

    int failures = 0, count = 0, rejected = 0;
    for (unsigned index = 0; index < sizeof(cells) / sizeof(cells[0]); index++) {
        VTPixelRotationSessionRef session = NULL;
        if (VTPixelRotationSessionCreate(kCFAllocatorDefault, &session) != noErr || !session) return 1;

        OSStatus setRotation = VTSessionSetProperty(session, kVTPixelRotationPropertyKey_Rotation,
                                                     cells[index].rotation);
        // Read it BACK, so a rejected set is visible as the session's own value rather than inferred from
        // the pixels. This is the check that would have caught fault 1 immediately.
        CFTypeRef readBack = NULL;
        OSStatus got = VTSessionCopyProperty(session, kVTPixelRotationPropertyKey_Rotation, NULL, &readBack);
        int accepted = (setRotation == noErr && got == noErr && readBack
                        && CFEqual((CFStringRef)readBack, cells[index].rotation));
        if (!accepted) rejected++;

        if (cells[index].flipH)
            VTSessionSetProperty(session, kVTPixelRotationPropertyKey_FlipHorizontalOrientation,
                                 (__bridge CFBooleanRef)@YES);
        if (cells[index].flipV)
            VTSessionSetProperty(session, kVTPixelRotationPropertyKey_FlipVerticalOrientation,
                                 (__bridge CFBooleanRef)@YES);

        int want[MAX_PIXELS], got8[MAX_PIXELS];
        int pixels = expected(cells[index].rotation, cells[index].flipH, cells[index].flipV, want);
        size_t outWidth, outHeight;
        geometry(cells[index].rotation, &outWidth, &outHeight);
        if ((int)(outWidth * outHeight) != pixels) {
            printf("GEOMETRY disagrees with the expectation for %s: %zux%zu vs %d pixels\n",
                   cells[index].name, outWidth, outHeight, pixels);
            return 1;
        }
        CVPixelBufferRef destination = NULL;
        if (CVPixelBufferCreate(kCFAllocatorDefault, outWidth, outHeight, format, NULL, &destination)
            != kCVReturnSuccess || !destination) { printf("no destination for %s\n", cells[index].name); return 1; }
        CVPixelBufferLockBaseAddress(destination, 0);
        memset(CVPixelBufferGetBaseAddress(destination), 0xAB,
               CVPixelBufferGetBytesPerRow(destination) * outHeight);
        CVPixelBufferUnlockBaseAddress(destination, 0);

        OSStatus rotated = VTPixelRotationSessionRotateImage(session, source, destination);
        for (int i = 0; i < MAX_PIXELS; i++) got8[i] = -1;
        if (rotated == noErr) {
            CVPixelBufferLockBaseAddress(destination, 0);
            const uint8_t *base = (const uint8_t *)CVPixelBufferGetBaseAddress(destination);
            size_t stride = CVPixelBufferGetBytesPerRow(destination);
            for (int i = 0; i < pixels; i++) got8[i] = base[(i / (int)outWidth) * stride + (i % (int)outWidth) * 4];
            CVPixelBufferUnlockBaseAddress(destination, 0);
        }
        count++;
        int agree = 1;
        for (int i = 0; i < pixels; i++) if (want[i] != got8[i]) agree = 0;
        if (!agree) failures++;
        printf("%-4s %-6s flipH=%d flipV=%d set=%-6d readBack=%d %zux%zu | got", agree ? "OK" : "DIFF",
               cells[index].name, cells[index].flipH, cells[index].flipV, (int)setRotation, accepted,
               outWidth, outHeight);
        for (int i = 0; i < pixels; i++) printf(" %4d", got8[i]);
        printf("  | want");
        for (int i = 0; i < pixels; i++) printf(" %4d", want[i]);
        printf("\n");
        if (readBack) CFRelease(readBack);
        CVPixelBufferRelease(destination);
        CFRelease(session);
    }

    printf("CELLS %d  DIFFERING %d  SET-REJECTED %d\n", count, failures, rejected);
    CVPixelBufferRelease(source);
    return (failures == 0 && rejected == 0 && handAgrees) ? 0 : 1;
}
