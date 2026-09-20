#import "CharonBlur.h"
#import <QuartzCore/QuartzCore.h>

static NSString *const CharonEffectKey = @"UIVisualEffectViewEffect";
static NSString *const CharonContentViewKey = @"UIVisualEffectViewContentView";

static void charon_free_pixels(void *info, const void *data, size_t size)
{
    free((void *)data);
}

static const NSTimeInterval CharonMinimumInterval = 0.1;
static const NSTimeInterval CharonQuietInterval = 0.5;
static const CGFloat CharonMaximumScale = 0.25;

@implementation UIVisualEffectView {
    UIVisualEffect *_effect;
    UIView *_contentView;
    BOOL _installing;
    CALayer *_backdrop;
    CADisplayLink *_link;
    NSTimeInterval _nextRefresh;
    uint32_t _lastChecksum;
    BOOL _refreshing;
    CGSize _refreshedSize;
}

- (void)charon_startBackdrop
{
    if (_link || !self.window)
        return;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(charon_tick:)];
    _link.frameInterval = 6;
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    _nextRefresh = 0;
}

- (void)charon_stopBackdrop
{
    [_link invalidate];
    _link = nil;
    [_backdrop removeFromSuperlayer];
    _backdrop = nil;
    _lastChecksum = 0;
}

- (BOOL)charon_blurs
{
    return [_effect isKindOfClass:[UIBlurEffect class]] && self.window && !self.hidden && self.alpha > 0.01 && self.bounds.size.width > 0 && self.bounds.size.height > 0;
}

- (void)charon_tick:(CADisplayLink *)link
{
    if (!_effect || ![_effect isKindOfClass:[UIBlurEffect class]]) {
        [_backdrop removeFromSuperlayer];
        _backdrop = nil;
        return;
    }
    if (![self charon_blurs] || [UIApplication sharedApplication].applicationState == UIApplicationStateBackground)
        return;
    NSTimeInterval now = CACurrentMediaTime();
    if (now < _nextRefresh)
        return;
    [self charon_refresh];
}

- (void)charon_refresh
{
    if (_refreshing || ![self charon_blurs])
        return;
    _refreshing = YES;
    NSTimeInterval started = CACurrentMediaTime();
    CharonBlurParameters parameters = charon_blur_parameters([(UIBlurEffect *)_effect charon_style]);
    UIWindow *window = self.window;
    CGRect view = [self convertRect:self.bounds toView:window];
    CGRect capture = CGRectIntersection(CGRectInset(view, -parameters.radius, -parameters.radius), window.bounds);
    if (CGRectIsNull(capture) || capture.size.width < 1 || capture.size.height < 1) {
        _refreshing = NO;
        return;
    }
    CGFloat scale = CharonMaximumScale;
    size_t width = (size_t)ceil(capture.size.width * scale), height = (size_t)ceil(capture.size.height * scale);
    if (width < 2)
        width = 2;
    if (height < 2)
        height = 2;
    size_t rowBytes = width * 4;
    uint8_t *pixels = calloc(rowBytes, height);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, rowBytes, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault);
    CGColorSpaceRelease(space);
    if (!context) {
        free(pixels);
        _refreshing = NO;
        return;
    }
    CGContextTranslateCTM(context, 0, height);
    CGContextScaleCTM(context, width / capture.size.width, -(CGFloat)height / capture.size.height);
    CGContextTranslateCTM(context, -capture.origin.x, -capture.origin.y);
    BOOL wasHidden = self.layer.hidden;
    self.layer.hidden = YES;
    [window.layer renderInContext:context];
    self.layer.hidden = wasHidden;
    CGContextRelease(context);
    uint32_t checksum = 2166136261u;
    for (size_t i = 0; i < rowBytes * height; i += 4)
        checksum = (checksum ^ pixels[i] ^ ((uint32_t)pixels[i + 1] << 8) ^ ((uint32_t)pixels[i + 2] << 16)) * 16777619u;
    CGSize refreshed = self.bounds.size;
    BOOL same = checksum == _lastChecksum && CGSizeEqualToSize(refreshed, _refreshedSize) && _backdrop;
    if (same) {
        free(pixels);
        _nextRefresh = CACurrentMediaTime() + CharonQuietInterval;
        _refreshing = NO;
        return;
    }
    _lastChecksum = checksum;
    _refreshedSize = refreshed;
    charon_blur_pixels(pixels, width, height, rowBytes, parameters.radius * width / capture.size.width, parameters.saturation, parameters.tintRed, parameters.tintGreen, parameters.tintBlue, parameters.tintAlpha);
    CGColorSpaceRef output = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, pixels, rowBytes * height, charon_free_pixels);
    CGImageRef image = CGImageCreate(width, height, 8, 32, rowBytes, output, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault, provider, NULL, true, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(output);
    if (!_backdrop) {
        _backdrop = [CALayer layer];
        _backdrop.magnificationFilter = kCAFilterLinear;
        _backdrop.minificationFilter = kCAFilterLinear;
        _backdrop.contentsGravity = kCAGravityResize;
        [self.layer insertSublayer:_backdrop atIndex:0];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _backdrop.frame = self.bounds;
    CGFloat sx = width / capture.size.width, sy = height / capture.size.height;
    CGRect crop = CGRectMake(floor((view.origin.x - capture.origin.x) * sx), floor((view.origin.y - capture.origin.y) * sy), ceil(view.size.width * sx), ceil(view.size.height * sy));
    CGImageRef cropped = CGImageCreateWithImageInRect(image, CGRectIntersection(crop, CGRectMake(0, 0, width, height)));
    _backdrop.contents = (__bridge id)(cropped ? cropped : image);
    if (cropped)
        CGImageRelease(cropped);
    [CATransaction commit];
    CGImageRelease(image);
    NSTimeInterval cost = CACurrentMediaTime() - started;
    _nextRefresh = CACurrentMediaTime() + MAX(CharonMinimumInterval, cost * 3);
    _refreshing = NO;
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    if (self.window) {
        [self charon_startBackdrop];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self charon_refresh];
        });
    } else {
        [self charon_stopBackdrop];
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    _backdrop.frame = self.bounds;
    _nextRefresh = 0;
}

- (void)charon_install
{
    _installing = YES;
    if (!_contentView) {
        _contentView = [[UIView alloc] initWithFrame:self.bounds];
        _contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    if (_contentView.superview != self)
        [super addSubview:_contentView];
    _installing = NO;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithEffect:(UIVisualEffect *)effect
{
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _effect = [effect copy];
        [self charon_install];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
        [self charon_install];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    _installing = YES;
    self = [super initWithCoder:coder];
    if (self) {
        _effect = [coder decodeObjectOfClass:[UIVisualEffect class] forKey:CharonEffectKey];
        _contentView = [coder decodeObjectOfClass:[UIView class] forKey:CharonContentViewKey];
        [self charon_install];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeObject:_effect forKey:CharonEffectKey];
    [coder encodeObject:_contentView forKey:CharonContentViewKey];
}

- (UIVisualEffect *)effect
{
    return _effect;
}

- (void)setEffect:(UIVisualEffect *)effect
{
    _effect = [effect copy];
    _lastChecksum = 0;
    _nextRefresh = 0;
    if (![_effect isKindOfClass:[UIBlurEffect class]]) {
        [_backdrop removeFromSuperlayer];
        _backdrop = nil;
    } else if (self.window) {
        [self charon_startBackdrop];
    }
}

- (UIView *)contentView
{
    return _contentView;
}

- (void)charon_refuse:(UIView *)view
{
    if (_installing)
        return;
    [NSException raise:NSInternalInconsistencyException format:@"%@ has been added as a subview to %@. Do not add subviews directly to the visual effect view itself, instead add them to the -contentView.", view, self];
}

- (void)addSubview:(UIView *)view
{
    [self charon_refuse:view];
    [super addSubview:view];
}

- (void)insertSubview:(UIView *)view atIndex:(NSInteger)index
{
    [self charon_refuse:view];
    [super insertSubview:view atIndex:index];
}

- (void)insertSubview:(UIView *)view aboveSubview:(UIView *)sibling
{
    [self charon_refuse:view];
    [super insertSubview:view aboveSubview:sibling];
}

- (void)insertSubview:(UIView *)view belowSubview:(UIView *)sibling
{
    [self charon_refuse:view];
    [super insertSubview:view belowSubview:sibling];
}

@end
