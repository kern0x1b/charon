#import <CoreImage/CoreImage.h>
#import <CoreVideo/CoreVideo.h>
#import <string.h>
#import <CoreGraphics/CoreGraphics.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

// A CIImageAccumulator is a piece of memory an image can be rendered into and read back out of, at an
// extent and a pixel format the caller names. It is how a filter is applied one tile or one row at a
// time without a context per step: the image comes out as a CIImage over the same bytes, and setting
// an image renders into them - all of them, or just the rectangle that changed.

@implementation CIImageAccumulator {
    NSMutableData *_pixels;
    CGRect _extent;
    CIFormat _format;
    NSInteger _rowBytes;
    // A strong reference, as every other object here: the port is built with ARC, which manages this
    // itself. Retaining it by hand on the way in and releasing it on the way out is releasing it
    // twice, which is what a caller saw.
    CGColorSpaceRef _colorSpace;
    CIContext *_context;
}

@synthesize extent = _extent;
@synthesize format = _format;

// The bytes one pixel of a format takes, and the order its channels are in. The four formats the
// accumulator is asked for most are the ones with a byte order to get right: what is written has to
// read back as the same picture, whichever of the two orders the caller named.
static NSUInteger CharonCIAccumulatorBytesPerPixel(CIFormat format)
{
    // The formats as ifs and not as a switch: the header declares them as exported constants, not as
    // enum cases, so they are values and not case labels.
    if (format == kCIFormatA8 || format == kCIFormatL8 || format == kCIFormatR8)
        return 1;
    if (format == kCIFormatLA8 || format == kCIFormatRG8 || format == kCIFormatARGB8 ||
        format == kCIFormatRGBA8 || format == kCIFormatBGRA8)
        return 4;
    if (format == kCIFormatRGBAf || format == kCIFormatRGBAh)
        return 8;
    return 4;
}

// Whether the red channel is the first of the four, or the third: BGRA and RGBA are the two formats
// an accumulator is asked for most, and they disagree on the same bytes.
static BOOL CharonCIAccumulatorIsBlueFirst(CIFormat format)
{
    return format == kCIFormatBGRA8;
}

- (instancetype)initWithExtent:(CGRect)extent format:(CIFormat)format
{
    return [self initWithExtent:extent format:format colorSpace:nil];
}

- (instancetype)initWithExtent:(CGRect)extent format:(CIFormat)format colorSpace:(CGColorSpaceRef)colorSpace
{
    format = CharonCIAccumulatorStoredFormat();
    if ((self = [super init])) {
        // The extent is the caller's, whole pixels or not: the host answers the extent it was given,
        // and integralising it here is a different answer.
        _extent = extent;
        _format = format;
        _colorSpace = colorSpace;
        _rowBytes = (NSInteger)(_extent.size.width * CharonCIAccumulatorBytesPerPixel(format));
        _pixels = [NSMutableData dataWithLength:(NSUInteger)(_rowBytes * _extent.size.height)];
    }
    return self;
}

- (void)dealloc
{
}

+ (CIImageAccumulator *)imageAccumulatorWithExtent:(CGRect)extent format:(CIFormat)format
{
    return [self imageAccumulatorWithExtent:extent format:format colorSpace:nil];
}

+ (CIImageAccumulator *)imageAccumulatorWithExtent:(CGRect)extent format:(CIFormat)format
                                      colorSpace:(CGColorSpaceRef)colorSpace
{
    return [[CIImageAccumulator alloc] initWithExtent:extent format:format colorSpace:colorSpace];
}

// What an accumulator actually holds, whatever it was asked for: the host answers BGRA for an RGBA8
// request and for a BGRA8 one alike, so the bytes are in that order and the format says so.
static CIFormat CharonCIAccumulatorStoredFormat(void)
{
    return kCIFormatBGRA8;
}

// The image is a view of the accumulator's own bytes, so what was set into them is what comes out,
// and setting it again changes the same bytes the image reads. iOS 6 has no image over bytes, so the
// image is made through a bitmap context over the same memory: the same pixels, the same origin.
- (CIImage *)image
{
    CGRect whole = CGRectIntegral(_extent);
    if (!_rowBytes || whole.size.width <= 0 || whole.size.height <= 0)
        return nil;
    // The image is the whole pixels at the origin, which is what the host answers for an extent that
    // does not start there and is not a whole number of pixels wide.
    _rowBytes = (NSInteger)(whole.size.width * 4);
    CGColorSpaceRef space = _colorSpace ?: CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(_pixels.mutableBytes, (size_t)whole.size.width, (size_t)whole.size.height, 8,
                                                 (size_t)_rowBytes, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CIImage *image = nil;
    if (context) {
        // The image is taken out of the context before the context is let go of: they own the same
        // memory, and reading one after releasing the other reads freed memory.
        CGImageRef made = CGBitmapContextCreateImage(context);
        CGContextRelease(context);
        if (made) {
            image = [CIImage imageWithCGImage:made];
            CGImageRelease(made);
        }
    }
    if (!_colorSpace)
        CGColorSpaceRelease(space);
    return image;
}

// A context that renders into the accumulator, made once: a context is an expensive thing and the
// accumulator is the thing that is asked for over and over.
- (CIContext *)charon_context
{
    if (!_context) {
        NSMutableDictionary *options = [NSMutableDictionary dictionary];
        options[kCIContextWorkingColorSpace] = [NSNull null];
        options[kCIContextOutputPremultiplied] = @NO;
        if (_colorSpace)
            options[kCIContextWorkingColorSpace] = (__bridge id)_colorSpace;
        _context = [CIContext contextWithOptions:options];
    }
    return _context;
}

- (void)setImage:(CIImage *)image
{
    [self setImage:image dirtyRect:_extent];
}

- (void)setImage:(CIImage *)image dirtyRect:(CGRect)dirtyRect
{
    if (!image || !_context)
        return;
    CGRect rect = CGRectIntersection(dirtyRect, _extent);
    if (CGRectIsNull(rect) || CGRectIsEmpty(rect))
        return;
    // The context renders into the bytes of the accumulator, over the rectangle that changed, in the
    // byte order the format names.
    // The bytes are in the order the caller named; the context renders in the order CoreGraphics
    // hands over, so the two agree only where the two orders do.
    [_context render:image toBitmap:_pixels.mutableBytes rowBytes:_rowBytes bounds:rect format:kCIFormatRGBA8
                     colorSpace:_colorSpace];
}

- (void)clear
{
    memset(_pixels.mutableBytes, 0, _pixels.length);
}

@end
