#import <UIKit/UIKit.h>
#import <UIKit/UIImageConfiguration.h>

// An image asset is a set of images, each registered for a trait collection or a configuration, that the
// asset hands back for whichever variant fits. iOS 6 has no asset catalogue to draw one from, so the asset
// keeps its variants itself: the keys are the trait collections and configurations in the order they were
// registered, and each key is matched with isEqual:. The release never reads an asset on its own, so this
// store is only ever asked by the application that made it.
@implementation UIImageAsset {
    NSMutableArray *_keys;
    NSMutableArray *_images;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _keys = [[NSMutableArray alloc] init];
        _images = [[NSMutableArray alloc] init];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init])) {
        NSArray *keys = [coder decodeObjectForKey:@"UIImageAssetKeys"];
        NSArray *images = [coder decodeObjectForKey:@"UIImageAssetImages"];
        _keys = [keys mutableCopy] ?: [[NSMutableArray alloc] init];
        _images = [images mutableCopy] ?: [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_keys forKey:@"UIImageAssetKeys"];
    [coder encodeObject:_images forKey:@"UIImageAssetImages"];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

// A nil image is not added: measured on the host for a trait collection, where the register call answers nothing.
- (void)charon_registerImage:(UIImage *)image forKey:(id)key
{
    if (!image)
        return;
    NSUInteger index = [_keys indexOfObject:key];
    if (index != NSNotFound) {
        _images[index] = image;
        return;
    }
    [_keys addObject:key];
    [_images addObject:image];
}

- (void)charon_unregisterKey:(id)key
{
    NSUInteger index = [_keys indexOfObject:key];
    if (index == NSNotFound)
        return;
    [_keys removeObjectAtIndex:index];
    [_images removeObjectAtIndex:index];
}

// The variant registered for the key, else the first one registered: measured on the host for an asset that
// holds one variant, where a lookup at any scale or configuration answers that variant. How an asset chooses
// among several variants it cannot match exactly is not measured, so the facts file leaves it open.
- (UIImage *)charon_imageForKey:(id)key
{
    NSUInteger index = [_keys indexOfObject:key];
    if (index != NSNotFound)
        return _images[index];
    return _images.count ? _images[0] : nil;
}

- (UIImage *)imageWithConfiguration:(UIImageConfiguration *)configuration
{
    return [self charon_imageForKey:configuration];
}

// Measured on the host: a nil configuration raises the same exception as a trait collection without a scale.
- (void)registerImage:(UIImage *)image withConfiguration:(UIImageConfiguration *)configuration
{
    if (!configuration)
        [NSException raise:NSInternalInconsistencyException format:@"scale must be > 0"];
    [self charon_registerImage:image forKey:configuration];
}

- (void)unregisterImageWithConfiguration:(UIImageConfiguration *)configuration
{
    [self charon_unregisterKey:configuration];
}

- (UIImage *)imageWithTraitCollection:(UITraitCollection *)traitCollection
{
    return [self charon_imageForKey:traitCollection];
}

// The system refuses a trait collection without a display scale, with this exception and this text (measured
// on the host: registering for nil raises it). A nil collection has no scale, so it is refused the same way.
- (void)registerImage:(UIImage *)image withTraitCollection:(UITraitCollection *)traitCollection
{
    if (traitCollection.displayScale <= 0)
        [NSException raise:NSInternalInconsistencyException format:@"scale must be > 0"];
    [self charon_registerImage:image forKey:traitCollection];
}

- (void)unregisterImageWithTraitCollection:(UITraitCollection *)traitCollection
{
    [self charon_unregisterKey:traitCollection];
}

@end
