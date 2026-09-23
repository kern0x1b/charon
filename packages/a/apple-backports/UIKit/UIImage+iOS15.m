#import "CharonImageBaseline.h"

@implementation UIImage (CharonFifteen)

- (UIImage *)imageByPreparingForDisplay
{
    if (self.images.count || !self.CGImage)
        return self;
    size_t width = CGImageGetWidth(self.CGImage);
    size_t height = CGImageGetHeight(self.CGImage);
    if (!width || !height)
        return self;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo info = kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst;
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, space, info);
    CGColorSpaceRelease(space);
    if (!context)
        return self;
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), self.CGImage);
    CGImageRef decoded = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (!decoded)
        return self;
    UIImage *result = [UIImage imageWithCGImage:decoded scale:self.scale orientation:self.imageOrientation];
    CGImageRelease(decoded);
    if (!result)
        return self;
    UIEdgeInsets capInsets = self.capInsets;
    if (!UIEdgeInsetsEqualToEdgeInsets(capInsets, UIEdgeInsetsZero))
        result = [result resizableImageWithCapInsets:capInsets resizingMode:self.resizingMode];
    UIEdgeInsets alignmentInsets = self.alignmentRectInsets;
    if (!UIEdgeInsetsEqualToEdgeInsets(alignmentInsets, UIEdgeInsetsZero))
        result = [result imageWithAlignmentRectInsets:alignmentInsets];
    if (self.renderingMode != UIImageRenderingModeAutomatic)
        result = [result imageWithRenderingMode:self.renderingMode];
    charon_set_image_baseline(result, charon_image_baseline(self));
    return result;
}

@end
