#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

// -imageBySettingProperties: and the -properties that reads it back.
//
// iOS 6 has both: the release's CIImage answers properties, and -[CIImage imageBySettingProperties:]
// is missing. What the release does with a dictionary it cannot put anywhere is the question, and the
// host answers it: the image that comes back is a **distinct** image of the same extent, and its
// properties are what the caller set. What the release does *not* do is read them back during a
// render - asked over the whole pixel probe, with this in place, the run finishes and every measurement
// still agrees, which is the evidence that the replacement is not in the renderer's path.
//
// The replacement is installed the way this repo replaces a release method - method_setImplementation
// in a +load, as Foundation/NSBundle+ReceiptURL.m does - and a same-selector category stands beside
// it, so the selector is added by a category and the registry check sees it there.

// The properties a caller set on an image, beside that image and not anywhere else: a category cannot
// add storage to a class the framework has, and an associated object can.
static const void *CharonCIPropertiesKey = &CharonCIPropertiesKey;

// -properties as the release had it, captured before the replacement is installed, so an image the
// port holds nothing for is answered by the framework and not by the port.
static IMP CharonCIPropertiesRelease;
typedef NSDictionary *(*CharonCIPropertiesFunction)(id, SEL);

@interface CharonCIPropertiesInstaller : NSObject
@end

@implementation CharonCIPropertiesInstaller

+ (void)load
{
    SEL selector = @selector(properties);
    Method method = class_getInstanceMethod([CIImage class], selector);
    if (!method)
        return;
    CharonCIPropertiesRelease = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^NSDictionary *(CIImage *image) {
        NSDictionary *held = objc_getAssociatedObject(image, CharonCIPropertiesKey);
        if (held)
            return held;
        return ((CharonCIPropertiesFunction)CharonCIPropertiesRelease)(image, selector);
    });
    method_setImplementation(method, replacement);
}

@end

@implementation CIImage (CharonProperties)

// The same selector as the replacement, beside it. An image the port holds properties for answers them;
// every other image is the framework's own answer, through the implementation captured above.
- (NSDictionary *)properties
{
    NSDictionary *held = objc_getAssociatedObject(self, CharonCIPropertiesKey);
    if (held)
        return held;
    if (CharonCIPropertiesRelease)
        return ((CharonCIPropertiesFunction)CharonCIPropertiesRelease)(self, @selector(properties));
    return @{};
}

- (CIImage *)imageBySettingProperties:(NSDictionary *)properties
{
    // A distinct image, which is what the host hands back: the identity affine transform is the
    // release's own and its output is a new image over the same pixels, so the properties belong to
    // that image and not to the one they were set on.
    if (!properties.count)
        return self;
    CIImage *image = [self imageByApplyingTransform:CGAffineTransformIdentity];
    if (!image)
        return self;
    NSMutableDictionary *merged = [image.properties mutableCopy] ?: [NSMutableDictionary dictionary];
    [merged addEntriesFromDictionary:properties];
    objc_setAssociatedObject(image, CharonCIPropertiesKey, merged, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return image;
}

@end
