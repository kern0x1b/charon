// One probe, two processes, on rendered bytes. Built once against the framework the host carries and
// once against the port's own CIImageAccumulator under a name of its own, so the two never meet in a
// runtime. Each is run over the same script, renders the same images through the same accumulator and
// writes what came out as canonical text: the extent and the format, and for every case the length and
// a checksum of the RGBA bytes the image renders to, with a few pixels spelled out so a difference can
// be looked at rather than only counted.
//
// Nothing here is tuned to agree. A line that differs is a line where the port and the system answer
// differently, and the tolerance is the one run.sh is given.
#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>

// The accumulator of the port, under the name the port's build gives it. The framework's own
// CIImageAccumulator is in the process as well and is never asked: the two never meet in one object.
#ifdef CHARON_PORT_ACCUMULATOR
#define ACCUMULATOR CharonCIImageAccumulator
#define ACCUMULATOR_NAME "port"
#else
#define ACCUMULATOR CIImageAccumulator
#define ACCUMULATOR_NAME "host"
#endif

// One colour space for the whole probe, made once and kept: a space made and released around every
// render is a thing to get wrong, and nothing here is measured through one.
static CGColorSpaceRef probeSpace(void)
{
    static CGColorSpaceRef space;
    if (!space)
        space = CGColorSpaceCreateDeviceRGB();
    return space;
}

static void put(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void put(NSString *format, ...)
{
    va_list arguments;
    va_start(arguments, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:arguments];
    printf("%s\n", line.UTF8String);
}

static void put_bytes(NSString *key, NSData *data)
{
    const uint8_t *bytes = data.bytes;
    uint32_t sum = 2166136261u;
    for (NSUInteger k = 0; k < data.length; k++) {
        sum ^= bytes[k];
        sum *= 16777619u;
    }
    put(@"%@ %lu %08x", key, (unsigned long)data.length, sum);
}

static void put_box(NSString *key, CGRect rect)
{
    put(@"%@ %.4f %.4f %.4f %.4f", key, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
}

// The rendered RGBA bytes of an image over the whole of its extent, in 8 bits a channel: the one
// rendering both sides do the same way, so what is compared is what the accumulator did with the
// bytes and not how either side renders.
static NSData *render(CIImage *image)
{
    if (!image)
        return nil;
    CGRect extent = image.extent;
    if (CGRectIsInfinite(extent) || CGRectIsEmpty(extent))
        return nil;
    NSUInteger width = (NSUInteger)ceil(extent.size.width), height = (NSUInteger)ceil(extent.size.height);
    NSMutableData *data = [NSMutableData dataWithLength:width * height * 4];
    CIContext *context = [CIContext contextWithOptions:@{kCIContextWorkingColorSpace: [NSNull null],
                                                        kCIContextOutputPremultiplied: @NO}];
    // The colour space is named and the same one every time: a byte format needs one, and the two
    // processes must be handed the same one or the bytes are not comparable.
    [context render:image toBitmap:data.mutableBytes rowBytes:(NSInteger)(width * 4) bounds:extent
              format:kCIFormatRGBA8 colorSpace:probeSpace()];
    return data;
}

// A few pixels spelled out, so a difference in the checksum can be seen rather than only counted.
static void put_pixels(NSString *key, NSData *data)
{
    if (!data || data.length < 16)
        return;
    const uint8_t *bytes = data.bytes;
    for (NSUInteger k = 0; k < 4 && (k + 1) * 4 <= data.length; k++)
        put(@"%@ pixel %lu %u %u %u %u", key, (unsigned long)k, bytes[k * 4], bytes[k * 4 + 1], bytes[k * 4 + 2],
            bytes[k * 4 + 3]);
}

// The image every case starts from: a red field on the left, a green one on the right, so a pixel of
// the accumulator says which half of the image it came from.
static CIImage *field(CGRect extent)
{
    CIImage *left = [[CIImage alloc] initWithColor:[[CIColor alloc] initWithRed:1 green:0 blue:0 alpha:1]];
    CIImage *right = [[CIImage alloc] initWithColor:[[CIColor alloc] initWithRed:0 green:1 blue:0 alpha:1]];
    return [left imageByCompositingOverImage:[right imageByCroppingToRect:extent]];
}

static void report(NSString *key, ACCUMULATOR *accumulator)
{
    put(@"%@ extent %.4f %.4f %.4f %.4f", key, accumulator.extent.origin.x, accumulator.extent.origin.y,
        accumulator.extent.size.width, accumulator.extent.size.height);
    put(@"%@ format %ld", key, (long)accumulator.format);
    CIImage *image = [accumulator image];
    put(@"%@ image %@", key, image ? @"made" : @"none");
    if (image)
        put_box([key stringByAppendingString:@" image extent"], image.extent);
    put_bytes([key stringByAppendingString:@" pixels"], render(image));
    put_pixels([key stringByAppendingString:@" pixels"], render(image));
}

int main(void)
{
    @autoreleasepool {
        put(@"probe %s", ACCUMULATOR_NAME);
        CGRect extent = CGRectMake(0, 0, 8, 4);

        // The two formats an accumulator is asked for most, and the two that disagree on the order of
        // the same bytes, so each is asked in its own turn.
        const CIFormat formats[2] = {kCIFormatRGBA8, kCIFormatBGRA8};
        for (int f = 0; f < 2; f++) {
            CIFormat format = formats[f];
            NSString *key = f == 0 ? @"rgba" : @"bgra";
            ACCUMULATOR *accumulator = [ACCUMULATOR imageAccumulatorWithExtent:extent format:format];
            report(key, accumulator);
            [accumulator setImage:field(extent)];
            report([key stringByAppendingString:@" set"], accumulator);
            [accumulator clear];
            report([key stringByAppendingString:@" cleared"], accumulator);
        }

        // A dirty rect: what is inside it changes and what is outside it does not.
        ACCUMULATOR *dirty = [ACCUMULATOR imageAccumulatorWithExtent:extent format:kCIFormatRGBA8];
        [dirty setImage:field(extent)];
        put_bytes(@"dirty before", render([dirty image]));
        [dirty setImage:[[CIImage alloc] initWithColor:[[CIColor alloc] initWithRed:0 green:0 blue:1 alpha:1]]
                dirtyRect:CGRectMake(0, 0, 4, 4)];
        put_bytes(@"dirty after", render([dirty image]));

        // An extent that is not integral and does not start at the origin: the accumulator's own extent
        // is what the header says it is, and the pixels are the ones inside it.
        CGRect odd = CGRectMake(1.5, -2.25, 5.5, 3.5);
        ACCUMULATOR *shifted = [ACCUMULATOR imageAccumulatorWithExtent:odd format:kCIFormatRGBA8];
        report(@"odd", shifted);
        [shifted setImage:field(odd)];
        report(@"odd set", shifted);

        // An accumulator nothing was ever set into, and one with a colour space.
        ACCUMULATOR *empty = [ACCUMULATOR imageAccumulatorWithExtent:extent format:kCIFormatRGBA8];
        report(@"empty", empty);
        ACCUMULATOR *spaced = [ACCUMULATOR imageAccumulatorWithExtent:extent format:kCIFormatRGBA8
                                                          colorSpace:probeSpace()];
        [spaced setImage:field(extent)];
        report(@"spaced", spaced);
    }
    return 0;
}
