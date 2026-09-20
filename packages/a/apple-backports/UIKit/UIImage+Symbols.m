#import "CharonSymbols.h"
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

static char charon_symbol_configuration_key;

static UIImage *charon_no_symbol(void)
{
    charon_menus_say_once(@"symbols", @"UIImage symbol images: iOS 6 has no SF Symbols, so +systemImageNamed: answers nil for every name.");
    return nil;
}

static UIImage *charon_image_with_configuration(UIImage *image, UIImageSymbolConfiguration *configuration)
{
    UIImage *copy = nil;
    if (image.images.count)
        copy = [UIImage animatedImageWithImages:image.images duration:image.duration];
    else if (image.CGImage)
        copy = [UIImage imageWithCGImage:image.CGImage scale:image.scale orientation:image.imageOrientation];
    else if (image.CIImage)
        copy = [UIImage imageWithCIImage:image.CIImage scale:image.scale orientation:image.imageOrientation];
    if (!copy)
        copy = [[UIImage alloc] init];
    UIEdgeInsets capInsets = image.capInsets;
    if (!UIEdgeInsetsEqualToEdgeInsets(capInsets, UIEdgeInsetsZero))
        copy = [copy resizableImageWithCapInsets:capInsets resizingMode:image.resizingMode];
    UIEdgeInsets alignmentInsets = image.alignmentRectInsets;
    if (!UIEdgeInsetsEqualToEdgeInsets(alignmentInsets, UIEdgeInsetsZero))
        copy = [copy imageWithAlignmentRectInsets:alignmentInsets];
    if (image.renderingMode != UIImageRenderingModeAutomatic)
        copy = [copy imageWithRenderingMode:image.renderingMode];
    if (configuration)
        objc_setAssociatedObject(copy, &charon_symbol_configuration_key, configuration, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return copy;
}

@implementation UIImage (CharonSymbols)

+ (UIImage *)systemImageNamed:(NSString *)name
{
    return charon_no_symbol();
}

+ (UIImage *)systemImageNamed:(NSString *)name compatibleWithTraitCollection:(UITraitCollection *)traitCollection
{
    return charon_no_symbol();
}

+ (UIImage *)systemImageNamed:(NSString *)name withConfiguration:(UIImageConfiguration *)configuration
{
    return charon_no_symbol();
}

- (BOOL)isSymbolImage
{
    return NO;
}

- (UIImageSymbolConfiguration *)symbolConfiguration
{
    return objc_getAssociatedObject(self, &charon_symbol_configuration_key);
}

- (UIImage *)imageByApplyingSymbolConfiguration:(UIImageSymbolConfiguration *)configuration
{
    UIImageSymbolConfiguration *current = self.symbolConfiguration;
    if (!configuration)
        return current ? self : charon_image_with_configuration(self, nil);
    if (!current) {
        UITraitCollection *environment = [UIScreen instancesRespondToSelector:@selector(traitCollection)] ? [UIScreen mainScreen].traitCollection : nil;
        current = [[UIImageSymbolConfiguration unspecifiedConfiguration] configurationWithTraitCollection:environment];
    }
    return charon_image_with_configuration(self, [current configurationByApplyingConfiguration:configuration]);
}

@end
