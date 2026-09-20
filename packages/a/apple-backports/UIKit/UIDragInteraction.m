#import <UIKit/UIKit.h>

@implementation UIDragInteraction {
    __weak id<UIDragInteractionDelegate> _delegate;
    __weak UIView *_view;
    BOOL _didSetEnabled;
    BOOL _enabled;
    BOOL _allowsSimultaneousRecognitionDuringLift;
}

+ (BOOL)isEnabledByDefault
{
    return NO;
}

- (instancetype)initWithDelegate:(id<UIDragInteractionDelegate>)delegate
{
    self = [super init];
    if (self)
        _delegate = delegate;
    return self;
}

- (id<UIDragInteractionDelegate>)delegate
{
    return _delegate;
}

- (UIView *)view
{
    return _view;
}

- (void)willMoveToView:(UIView *)view
{
}

- (void)didMoveToView:(UIView *)view
{
    _view = view;
}

- (BOOL)isEnabled
{
    return _didSetEnabled ? _enabled : [[self class] isEnabledByDefault];
}

- (void)setEnabled:(BOOL)enabled
{
    _didSetEnabled = YES;
    _enabled = enabled;
}

- (BOOL)allowsSimultaneousRecognitionDuringLift
{
    return _allowsSimultaneousRecognitionDuringLift;
}

- (void)setAllowsSimultaneousRecognitionDuringLift:(BOOL)allows
{
    _allowsSimultaneousRecognitionDuringLift = allows;
}

@end
