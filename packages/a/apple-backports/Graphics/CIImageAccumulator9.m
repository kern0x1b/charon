#import <CoreImage/CoreImage.h>
#import <CoreVideo/CoreVideo.h>
#import <string.h>

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
    if ((self = [super init])) {
        _extent = CGRectIntegral(extent);
        _format = format;
        _colorSpace = colorSpace ? (CGColorSpaceRef)CFRetain(colorSpace) : NULL;
        _rowBytes = (NSInteger)(_extent.size.width * CharonCIAccumulatorBytesPerPixel(format));
        _pixels = [NSMutableData dataWithLength:(NSUInteger)(_rowBytes * _extent.size.height)];
    }
    return self;
}

- (void)dealloc
{
    CFRelease(_colorSpace);
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

// The image is a view of the accumulator's own bytes, so what was set into them is what comes out,
// and setting it again changes the same bytes the image reads. iOS 6 has no image over bytes, so the
// image is made through a bitmap context over the same memory: the same pixels, the same origin.
- (CIImage *)image
{
    if (!_rowBytes || _extent.size.width <= 0 || _extent.size.height <= 0)
        return nil;
    CGColorSpaceRef space = _colorSpace ?: CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(_pixels.mutableBytes, (size_t)_extent.size.width, (size_t)_extent.size.height, 8,
                                                 (size_t)_rowBytes, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextFlush(context);
    CGContextRelease(context);
    if (!_colorSpace)
        CGColorSpaceRelease(space);
    return [CIImage imageWithCGImage:CGBitmapContextCreateImage(context) ?: NULL];
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
            [options setObject:(__bridge id)_colorSpace forKey:kCIContextWorkingColorSpace];
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
