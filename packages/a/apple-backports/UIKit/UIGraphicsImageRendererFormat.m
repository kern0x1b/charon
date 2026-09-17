#import "CharonGraphicsRenderer.h"

@implementation UIGraphicsImageRendererFormat {
@private
    CGFloat _scale;
    BOOL _opaque;
    BOOL _prefersExtendedRange;
}

+ (instancetype)defaultFormat
{
    UIGraphicsImageRendererFormat *format = [super defaultFormat];
    format.prefersExtendedRange = NO;
    format.opaque = NO;
    format.scale = [UIScreen mainScreen].scale;
    return format;
}

- (instancetype)init
{
    if ((self = [super init]))
        _scale = [UIScreen mainScreen].scale;
    return self;
}

- (CGFloat)scale
{
    return _scale;
}

- (void)setScale:(CGFloat)scale
{
    _scale = scale;
}

- (BOOL)opaque
{
    return _opaque;
}

- (void)setOpaque:(BOOL)opaque
{
    _opaque = opaque;
}

- (BOOL)prefersExtendedRange
{
    return _prefersExtendedRange;
}

- (void)setPrefersExtendedRange:(BOOL)prefersExtendedRange
{
    _prefersExtendedRange = prefersExtendedRange;
}

- (CGFloat)_contextScale
{
    return _scale != 0 ? _scale : [UIScreen mainScreen].scale;
}

- (id)copyWithZone:(NSZone *)zone
{
    UIGraphicsImageRendererFormat *copy = [super copyWithZone:zone];
    copy.opaque = self.opaque;
    copy.scale = self.scale;
    copy.prefersExtendedRange = self.prefersExtendedRange;
    return copy;
}

@end
