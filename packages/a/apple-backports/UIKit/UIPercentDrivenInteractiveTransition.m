#import <UIKit/UIKit.h>

@implementation UIPercentDrivenInteractiveTransition {
    id<UIViewControllerContextTransitioning> _context;
    CGFloat _percentComplete;
    CGFloat _completionSpeed;
    UIViewAnimationCurve _completionCurve;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _completionSpeed = 1;
        _completionCurve = (UIViewAnimationCurve)7;
    }
    return self;
}

- (CGFloat)duration
{
    return 0;
}

- (CGFloat)percentComplete
{
    return _percentComplete;
}

- (CGFloat)completionSpeed
{
    return _completionSpeed;
}

- (void)setCompletionSpeed:(CGFloat)speed
{
    _completionSpeed = speed;
}

- (UIViewAnimationCurve)completionCurve
{
    return _completionCurve;
}

- (void)setCompletionCurve:(UIViewAnimationCurve)curve
{
    _completionCurve = curve;
}

- (void)startInteractiveTransition:(id<UIViewControllerContextTransitioning>)transitionContext
{
    _context = transitionContext;
}

- (void)updateInteractiveTransition:(CGFloat)percentComplete
{
    if (!_context)
        return;
    _percentComplete = MAX(0, MIN(1, percentComplete));
    [_context updateInteractiveTransition:_percentComplete];
}

- (void)cancelInteractiveTransition
{
    [_context cancelInteractiveTransition];
}

- (void)finishInteractiveTransition
{
    [_context finishInteractiveTransition];
}

@end
