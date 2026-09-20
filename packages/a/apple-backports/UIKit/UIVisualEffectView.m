#import <UIKit/UIKit.h>

static NSString *const CharonEffectKey = @"UIVisualEffectViewEffect";
static NSString *const CharonContentViewKey = @"UIVisualEffectViewContentView";

@implementation UIVisualEffectView {
    UIVisualEffect *_effect;
    UIView *_contentView;
    BOOL _installing;
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
