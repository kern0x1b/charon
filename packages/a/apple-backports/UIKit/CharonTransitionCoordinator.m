#import "CharonTransitionCoordinator.h"
#import <objc/runtime.h>

NSTimeInterval charon_default_duration(BOOL modal)
{
    return modal ? 0.4 : 0.35;
}

@implementation CharonTransitionCoordinator {
    __weak UIViewController *_from;
    __weak UIViewController *_to;
    UIView *_container;
    BOOL _animated;
    NSTimeInterval _duration;
    UIModalPresentationStyle _style;
    NSMutableArray *_completions;
    BOOL _finished;
}

- (instancetype)initWithFrom:(UIViewController *)from to:(UIViewController *)to container:(UIView *)container animated:(BOOL)animated duration:(NSTimeInterval)duration style:(UIModalPresentationStyle)style
{
    if ((self = [super init])) {
        _from = from;
        _to = to;
        _container = container;
        _animated = animated;
        _duration = duration;
        _style = style;
        _completions = [NSMutableArray array];
    }
    return self;
}

- (void)begin
{
}

- (void)finish
{
    if (_finished)
        return;
    _finished = YES;
    NSArray *completions = [_completions copy];
    [_completions removeAllObjects];
    for (void (^completion)(id<UIViewControllerTransitionCoordinatorContext>) in completions)
        completion(self);
}

- (BOOL)animateAlongsideTransition:(void (^)(id<UIViewControllerTransitionCoordinatorContext>))animation completion:(void (^)(id<UIViewControllerTransitionCoordinatorContext>))completion
{
    return [self animateAlongsideTransitionInView:nil animation:animation completion:completion];
}

- (BOOL)animateAlongsideTransitionInView:(UIView *)view animation:(void (^)(id<UIViewControllerTransitionCoordinatorContext>))animation completion:(void (^)(id<UIViewControllerTransitionCoordinatorContext>))completion
{
    if (_finished) {
        if (animation)
            animation(self);
        if (completion)
            completion(self);
        return NO;
    }
    if (completion)
        [_completions addObject:[completion copy]];
    if (!animation)
        return YES;
    if (_animated)
        [UIView animateWithDuration:_duration delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction animations:^{ animation(self); } completion:nil];
    else
        animation(self);
    return YES;
}

- (void)notifyWhenInteractionEndsUsingBlock:(void (^)(id<UIViewControllerTransitionCoordinatorContext>))handler
{
}

- (void)notifyWhenInteractionChangesUsingBlock:(void (^)(id<UIViewControllerTransitionCoordinatorContext>))handler
{
}

- (BOOL)isAnimated { return _animated; }
- (UIModalPresentationStyle)presentationStyle { return _style; }
- (BOOL)initiallyInteractive { return NO; }
- (BOOL)isInteractive { return NO; }
- (BOOL)isCancelled { return NO; }
- (NSTimeInterval)transitionDuration { return _animated ? _duration : 0; }
- (CGFloat)percentComplete { return _finished ? 1 : 0; }
- (CGFloat)completionVelocity { return 1; }
- (UIViewAnimationCurve)completionCurve { return UIViewAnimationCurveEaseInOut; }
- (UIView *)containerView { return _container; }
- (CGAffineTransform)targetTransform { return CGAffineTransformIdentity; }

- (__kindof UIViewController *)viewControllerForKey:(UITransitionContextViewControllerKey)key
{
    if ([key isEqualToString:UITransitionContextFromViewControllerKey])
        return _from;
    if ([key isEqualToString:UITransitionContextToViewControllerKey])
        return _to;
    return nil;
}

- (__kindof UIView *)viewForKey:(UITransitionContextViewKey)key
{
    if ([key isEqualToString:UITransitionContextFromViewKey])
        return _from.isViewLoaded ? _from.view : nil;
    if ([key isEqualToString:UITransitionContextToViewKey])
        return _to.isViewLoaded ? _to.view : nil;
    return nil;
}

@end
