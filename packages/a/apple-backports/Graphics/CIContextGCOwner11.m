#import <CoreImage/CoreImage.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

// A CIContext the port makes carries what it was made with, and a CIContext the caller made over a
// CGContext draws into that CGContext. Neither can be a category adding storage to a class the
// framework has, so both are associated objects on the context itself: one for the drawing surface,
// one for the options. The release has no +contextWithCGContext: in either spelling - it has
// +contextWithOptions: and +contextWithEAGLContext:options: and nothing to extend - so the context
// here is one of the release's own, and the drawing surface is what it draws into when asked.

// What a context is made with, kept beside the context. The keys are the address of these objects, so
// two contexts never share one another's options.
static const void *CharonCIContextOptionsKey = &CharonCIContextOptionsKey;
static const void *CharonCIContextDrawingKey = &CharonCIContextDrawingKey;

@implementation CIContext (CharonGCOwner)

+ (instancetype)contextWithCGContext:(CGContextRef)cgctx options:(NSDictionary *)options
{
    // A real context of the release's own, made the release's way, with the drawing surface beside it.
    CIContext *context = options.count ? [self contextWithOptions:options] : [self context];
    objc_setAssociatedObject(context, CharonCIContextDrawingKey, (__bridge id)cgctx, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(context, CharonCIContextOptionsKey, options ?: @{}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return context;
}

// The options a context was made with, and over it: the two properties that say what a context works
// in. A context made with no option at all works in whatever the release works in, which is no working
// space and a format of eight bits a channel.
- (CGColorSpaceRef)workingColorSpace
{
    NSDictionary *options = objc_getAssociatedObject(self, CharonCIContextOptionsKey);
    id space = options[kCIContextWorkingColorSpace];
    return [space isKindOfClass:[NSNull class]] ? NULL : (__bridge CGColorSpaceRef)space;
}

- (CIFormat)workingFormat
{
    NSDictionary *options = objc_getAssociatedObject(self, CharonCIContextOptionsKey);
    id format = options[kCIContextWorkingFormat];
    return [format isKindOfClass:[NSNumber class]] ? (CIFormat)[format unsignedIntValue] : kCIFormatRGBA8;
}

@end
