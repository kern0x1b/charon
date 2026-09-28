#import <CoreImage/CoreImage.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <stdio.h>
#import <math.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

// -imageByUnpremultiplyingAlpha, as a **named C function** with (id, SEL), so the host differential
// can call the port's own code on a host CIImage and dladdr it. A category is shadowed here: the
// macOS framework carries this selector, the 16.4 iOS header says iOS 6.1.3 does not, and the
// measured addresses are the framework's in both processes.
//
// What the host does, measured and not assumed: over a finite extent the extent is unchanged, each
// channel is divided by the alpha, a result over one is clamped to one, the alpha is untouched, and a
// premultiply followed by an unpremultiply is the identity - 487584e5 either way. Over an **infinite**
// extent the image comes back still infinite and is not rendered, so there is nothing to divide and
// the port answers the image itself; that is why this does not take an eager render of one.

CIImage *charon_CIImage_imageByUnpremultiplyingAlpha(id image, SEL _cmd)
{
    CGRect bounds = [(CIImage *)image extent];
    if (CGRectIsNull(bounds) || CGRectIsEmpty(bounds))
        return image;
    if (CGRectIsInfinite(bounds))
        return image;

    CGRect whole = CGRectIntegral(bounds);
    size_t width = (size_t)ceil(whole.size.width), height = (size_t)ceil(whole.size.height);
    if (!width || !height)
        return image;
    NSMutableData *bytes = [NSMutableData dataWithLength:width * height * 4];
    CIContext *context = [CIContext contextWithOptions:@{kCIContextWorkingColorSpace: [NSNull null]}];
    [context render:(CIImage *)image toBitmap:bytes.mutableBytes rowBytes:(NSInteger)(width * 4) bounds:whole
            format:kCIFormatRGBA8 colorSpace:CGColorSpaceCreateDeviceRGB()];

    uint8_t *pixels = bytes.mutableBytes;
    for (size_t k = 0; k < width * height; k++) {
        uint8_t *pixel = pixels + k * 4;
        if (!pixel[3])
            continue;
        // In float, over the colour the alpha really is. Integer arithmetic on the stored channel
        // rounds twice - once into the eight bits it divides and once into the eight it writes - and the
        // host's is 255 153 255 128 where that was 255 149 255 128.
        float alpha = (float)pixel[3] / 255.0f;
        for (int channel = 0; channel < 3; channel++) {
            float value = ((float)pixel[channel] / 255.0f) / alpha;
            pixel[channel] = (uint8_t)lrintf(MIN(1.0f, value) * 255.0f);
        }
    }
    return [CIImage imageWithBitmapData:bytes bytesPerRow:width * 4 size:whole.size format:kCIFormatRGBA8
                            colorSpace:CGColorSpaceCreateDeviceRGB()];
}

@interface CharonCIUnpremultiplyInstaller : NSObject
@end

@implementation CharonCIUnpremultiplyInstaller

+ (void)load
{
    SEL selector = @selector(imageByUnpremultiplyingAlpha);
    IMP implementation = (IMP)charon_CIImage_imageByUnpremultiplyingAlpha;
    Method method = class_getInstanceMethod([CIImage class], selector);
    if (method) {
        method_setImplementation(method, implementation);
        fprintf(stderr, "charon: replaced -[CIImage imageByUnpremultiplyingAlpha]\n");
    } else if (class_addMethod([CIImage class], selector, implementation, "@@:")) {
        fprintf(stderr, "charon: added -[CIImage imageByUnpremultiplyingAlpha], the release does not have it\n");
    } else {
        fprintf(stderr, "charon: could not install -[CIImage imageByUnpremultiplyingAlpha]\n");
    }
}

@end

@implementation CIImage (CharonUnpremultiply)

- (CIImage *)imageByUnpremultiplyingAlpha
{
    return charon_CIImage_imageByUnpremultiplyingAlpha(self, _cmd);
}

@end
