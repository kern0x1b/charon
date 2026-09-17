#import <UIKit/UIKit.h>

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
#import <objc/runtime.h>

static char charon_rendering_mode_key;

@implementation UIImage (CharonRenderingMode)

- (UIImageRenderingMode)renderingMode
{
    NSNumber *stored = objc_getAssociatedObject(self, &charon_rendering_mode_key);
    return stored ? (UIImageRenderingMode)stored.integerValue : UIImageRenderingModeAutomatic;
}

- (UIImage *)imageWithRenderingMode:(UIImageRenderingMode)renderingMode
{
    UIImage *image = nil;
    if (self.images.count)
        image = [UIImage animatedImageWithImages:self.images duration:self.duration];
    else if (self.CGImage)
        image = [UIImage imageWithCGImage:self.CGImage scale:self.scale orientation:self.imageOrientation];
    else if (self.CIImage)
        image = [UIImage imageWithCIImage:self.CIImage scale:self.scale orientation:self.imageOrientation];
    if (!image)
        image = self;
    UIEdgeInsets capInsets = self.capInsets;
    if (image != self && !UIEdgeInsetsEqualToEdgeInsets(capInsets, UIEdgeInsetsZero))
        image = [image resizableImageWithCapInsets:capInsets resizingMode:self.resizingMode];
    UIEdgeInsets alignmentInsets = self.alignmentRectInsets;
    if (image != self && !UIEdgeInsetsEqualToEdgeInsets(alignmentInsets, UIEdgeInsetsZero))
        image = [image imageWithAlignmentRectInsets:alignmentInsets];
    objc_setAssociatedObject(image, &charon_rendering_mode_key, @(renderingMode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return image;
}

@end
