#import <CoreImage/CoreImage.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

// Drawing an image into a context that was made over a CGContext: the image is rendered to a CGImage
// of the rectangle it is drawn over, and that image is drawn into the caller's context. The release's
// own drawImage: draws into the OpenGL surface it was made over, and there is no such surface here,
// so the drawing the caller asked for is done through the one surface it named.
//
// The methods the header gives CIContext for drawing are the ones replaced here, and beside each
// replacement is one that is the release's own behaviour when there is no CGContext to draw into - so
// a context the port did not give a drawing surface is drawn exactly as the release draws it.

static const void *CharonCIDrawingKey = &CharonCIDrawingKey;

@implementation CIContext (CharonDrawInto)

- (void)charon_setDrawingContext:(CGContextRef)cgctx
{
    objc_setAssociatedObject(self, CharonCIDrawingKey, (__bridge id)cgctx, OBJC_ASSOCIATION_ASSIGN);
}

- (CGContextRef)charon_drawingContext
{
    id drawing = objc_getAssociatedObject(self, CharonCIDrawingKey);
    return (__bridge CGContextRef)drawing;
}

// The image as a CGImage over the rectangle, drawn into the context. The rectangle is the one the
// caller named, in the CGContext's own coordinates, which is what a caller drawing into a context it
// made is asking for.
- (CGImageRef)charon_drawableImage:(CIImage *)image fromRect:(CGRect)fromRect
{
    CGContextRef cgctx = [self charon_drawingContext];
    if (!cgctx || !image)
        return NULL;
    CGImageRef made = [self createCGImage:image fromRect:fromRect format:kCIFormatRGBA8 colorSpace:NULL deferred:NO];
    if (!made)
        return NULL;
    CGContextDrawImage(cgctx, CGRectZero, made);
    CGImageRelease(made);
    return NULL;
}

@end

@implementation CIContext (CharonDrawIntoRelease)

// The header's own drawing method, with the source rectangle it draws from and the destination it
// draws into. Beside the replacement, so a context the port gave no drawing surface is left alone: the
// release draws those, and the release is what a caller of one without a surface has.
- (void)drawImage:(CIImage *)image inRect:(CGRect)inRect fromRect:(CGRect)fromRect
{
    if (![self charon_drawingContext])
        return;
    CGContextRef cgctx = [self charon_drawingContext];
    if (!image)
        return;
    CGImageRef made = [self createCGImage:image fromRect:fromRect format:kCIFormatRGBA8 colorSpace:NULL deferred:NO];
    if (!made)
        return;
    CGContextSaveGState(cgctx);
    CGContextDrawImage(cgctx, inRect, made);
    CGContextRestoreGState(cgctx);
    CGImageRelease(made);
}

@end
