#import "CharonCustomTransition.h"
#import "CharonTransitionCoordinator.h"
#import <objc/message.h>
#import <objc/runtime.h>

@interface CharonViewState : NSObject
@property (nonatomic, weak) UIView *superview;
@property (nonatomic) NSUInteger index;
@property (nonatomic) CGRect frame;
@property (nonatomic) UIViewAutoresizing autoresizing;
@property (nonatomic) BOOL hidden;
@end

@implementation CharonViewState
@synthesize superview = _superview;
@synthesize index = _index;
@synthesize frame = _frame;
@synthesize autoresizing = _autoresizing;
@synthesize hidden = _hidden;

+ (instancetype)captureView:(UIView *)view
{
    CharonViewState *state = [[CharonViewState alloc] init];
    state.superview = view.superview;
    state.index = view.superview ? [view.superview.subviews indexOfObject:view] : 0;
    state.frame = view.frame;
    state.autoresizing = view.autoresizingMask;
    state.hidden = view.hidden;
    return state;
}

- (void)restoreView:(UIView *)view
{
    UIView *parent = _superview;
    view.hidden = _hidden;
    if (!parent) {
        [view removeFromSuperview];
        return;
    }
    NSUInteger index = MIN(_index, parent.subviews.count);
    if (view.superview == parent && [parent.subviews indexOfObject:view] == index) {
        view.frame = _frame;
        return;
    }
    [view removeFromSuperview];
    [parent insertSubview:view atIndex:index];
    view.frame = _frame;
    view.autoresizingMask = _autoresizing;
}

@end

static const char charon_deferral_key;

typedef NS_ENUM(NSInteger, CharonDeferralMode) {
    CharonDeferralPass,
    CharonDeferralNative,
    CharonDeferralSwallow
};

@interface CharonDeferral : NSObject
@property (nonatomic) CharonDeferralMode mode;
@property (nonatomic, strong) NSMutableArray *pending;
@property (nonatomic) Class original;
@property (nonatomic) NSInteger owners;
@end

@implementation CharonDeferral
@synthesize mode = _mode;
@synthesize pending = _pending;
@synthesize original = _original;
@synthesize owners = _owners;
@end

static Class charon_deferring_class(Class cls)
{
    static NSMutableDictionary *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    NSString *name = [@"CharonDeferring_" stringByAppendingString:NSStringFromClass(cls)];
    @synchronized (cache) {
        Class existing = cache[name];
        if (existing)
            return existing;
        Class created = objc_allocateClassPair(cls, name.UTF8String, 0);
        if (!created)
            return nil;
        for (NSString *selectorName in @[@"viewWillAppear:", @"viewWillDisappear:", @"viewDidAppear:", @"viewDidDisappear:"]) {
            SEL selector = NSSelectorFromString(selectorName);
            BOOL did = [selectorName hasPrefix:@"viewDid"];
            class_addMethod(created, selector, imp_implementationWithBlock(^(UIViewController *self, BOOL animated) {
                CharonDeferral *deferral = objc_getAssociatedObject(self, &charon_deferral_key);
                if (deferral.mode == CharonDeferralSwallow)
                    return;
                if (deferral.mode == CharonDeferralNative && did) {
                    [deferral.pending addObject:@[self, selectorName]];
                    return;
                }
                struct objc_super target = {self, cls};
                ((void (*)(struct objc_super *, SEL, BOOL))objc_msgSendSuper)(&target, selector, animated);
            }), "v@:c");
        }
        class_addMethod(created, @selector(class), imp_implementationWithBlock(^Class(id self) { return cls; }), "#@:");
        objc_registerClassPair(created);
        cache[name] = created;
        return created;
    }
}

static void charon_collect(UIViewController *controller, NSMutableArray *into)
{
    if (!controller || [into containsObject:controller])
        return;
    [into addObject:controller];
    for (UIViewController *child in controller.childViewControllers)
        charon_collect(child, into);
}

static NSArray *charon_begin_deferral(NSArray *controllers)
{
    NSMutableArray *begun = [NSMutableArray array];
    for (UIViewController *controller in controllers) {
        Class current = object_getClass(controller);
        if (strncmp(class_getName(current), "CharonDeferring_", 16) == 0) {
            CharonDeferral *shared = objc_getAssociatedObject(controller, &charon_deferral_key);
            if (shared) {
                shared.owners++;
                shared.mode = CharonDeferralNative;
                [begun addObject:@[controller, shared]];
            }
            continue;
        }
        if (strncmp(class_getName(current), "NSKVONotifying", 14) == 0)
            continue;
        Class replacement = charon_deferring_class(current);
        if (!replacement)
            continue;
        CharonDeferral *deferral = [[CharonDeferral alloc] init];
        deferral.mode = CharonDeferralNative;
        deferral.pending = [NSMutableArray array];
        deferral.original = current;
        deferral.owners = 1;
        objc_setAssociatedObject(controller, &charon_deferral_key, deferral, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        object_setClass(controller, replacement);
        [begun addObject:@[controller, deferral]];
    }
    return begun;
}

static void charon_set_mode(NSArray *begun, CharonDeferralMode mode)
{
    for (NSArray *entry in begun)
        [entry[1] setMode:mode];
}

static NSArray *charon_take_pending(NSArray *begun)
{
    NSMutableArray *pending = [NSMutableArray array];
    for (NSArray *entry in begun) {
        CharonDeferral *deferral = entry[1];
        [pending addObjectsFromArray:deferral.pending];
        [deferral.pending removeAllObjects];
    }
    return pending;
}

static void charon_release_deferral(NSArray *begun)
{
    for (NSArray *entry in begun) {
        UIViewController *controller = entry[0];
        CharonDeferral *deferral = entry[1];
        if (--deferral.owners > 0)
            continue;
        deferral.mode = CharonDeferralPass;
        object_setClass(controller, deferral.original);
        objc_setAssociatedObject(controller, &charon_deferral_key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

@implementation CharonTransitionContext {
@public
    UIView *_container;
    UIViewController *_from;
    UIViewController *_to;
    BOOL _animated;
    BOOL _interactive;
    BOOL _cancelled;
    BOOL _completed;
    UIModalPresentationStyle _style;
    CGRect _initialFrom, _finalFrom, _initialTo, _finalTo;
    void (^_finish)(BOOL didComplete);
}

- (UIView *)containerView { return _container; }
- (BOOL)isAnimated { return _animated; }
- (BOOL)isInteractive { return _interactive; }
- (BOOL)transitionWasCancelled { return _cancelled; }
- (UIModalPresentationStyle)presentationStyle { return _style; }
- (CGAffineTransform)targetTransform { return CGAffineTransformIdentity; }

- (void)updateInteractiveTransition:(CGFloat)percentComplete
{
}

- (void)finishInteractiveTransition
{
}

- (void)cancelInteractiveTransition
{
}

- (void)pauseInteractiveTransition
{
}

- (void)completeTransition:(BOOL)didComplete
{
    if (_completed)
        return;
    _completed = YES;
    if (_finish)
        _finish(didComplete && !_cancelled);
}

- (UIViewController *)viewControllerForKey:(UITransitionContextViewControllerKey)key
{
    if ([key isEqualToString:UITransitionContextFromViewControllerKey])
        return _from;
    if ([key isEqualToString:UITransitionContextToViewControllerKey])
        return _to;
    return nil;
}

- (UIView *)viewForKey:(UITransitionContextViewKey)key
{
    if ([key isEqualToString:UITransitionContextFromViewKey])
        return _from.view;
    if ([key isEqualToString:UITransitionContextToViewKey])
        return _to.view;
    return nil;
}

- (CGRect)initialFrameForViewController:(UIViewController *)controller
{
    return controller == _from ? _initialFrom : controller == _to ? _initialTo : CGRectZero;
}

- (CGRect)finalFrameForViewController:(UIViewController *)controller
{
    return controller == _from ? _finalFrom : controller == _to ? _finalTo : CGRectZero;
}

@end

BOOL charon_custom_transition(CharonTransitionKind kind, UIViewController *from, UIViewController *to, UIViewController *source, id<UIViewControllerAnimatedTransitioning> animator, id<UIViewControllerInteractiveTransitioning> interactor, UIModalPresentationStyle style, void (^native)(void), void (^undo)(void), void (^completion)(BOOL finished))
{
    UIView *fromView = from.view;
    UIView *toView = to.view;
    UIWindow *window = fromView.window ?: [UIApplication sharedApplication].keyWindow;
    if (!fromView || !toView || !window || !animator)
        return NO;
    BOOL modal = kind == CharonTransitionPresent || kind == CharonTransitionDismiss;
    BOOL keepsPresenter = kind == CharonTransitionPresent && (style == 4 || style == 5 || style == 6);

    CharonViewState *fromPre = [CharonViewState captureView:fromView];
    UIView *fromParent = fromView.superview;
    CGRect initialFrom = fromParent ? [fromParent convertRect:fromView.frame toView:modal ? window : (fromParent.superview ?: fromParent)] : fromView.frame;
    UIView *navigationHost = modal ? nil : (fromParent.superview ?: fromParent);

    NSMutableArray *controllers = [NSMutableArray array];
    charon_collect(from, controllers);
    charon_collect(to, controllers);
    NSArray *begun = charon_begin_deferral(controllers);
    native();

    void (^run)(void) = ^{
        UIView *host = modal ? window : navigationHost;
        UIView *toParent = toView.superview;
        if (!host || (!modal && !toParent)) {
            charon_set_mode(begun, CharonDeferralPass);
            for (NSArray *entry in charon_take_pending(begun))
                ((void (*)(id, SEL, BOOL))objc_msgSend)(entry[0], NSSelectorFromString(entry[1]), NO);
            charon_release_deferral(begun);
            if (completion)
                completion(YES);
            return;
        }
        charon_set_mode(begun, CharonDeferralSwallow);
        CharonViewState *toPost = [CharonViewState captureView:toView];
        CGRect finalTo = toParent ? [toParent convertRect:toView.frame toView:modal ? window : host] : toView.frame;

        UIView *container = [[UIView alloc] initWithFrame:modal ? window.bounds : host.bounds];
        container.backgroundColor = [UIColor clearColor];
        container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host addSubview:container];

        [fromView removeFromSuperview];
        fromView.frame = initialFrom;
        [container addSubview:fromView];
        [toView removeFromSuperview];
        toView.frame = finalTo;

        CharonTransitionContext *context = [[CharonTransitionContext alloc] init];
        context->_container = container;
        context->_from = from;
        context->_to = to;
        context->_animated = YES;
        context->_style = modal ? (kind == CharonTransitionPresent ? to.modalPresentationStyle : from.modalPresentationStyle) : (UIModalPresentationStyle)-1;
        context->_initialFrom = initialFrom;
        context->_finalFrom = kind == CharonTransitionDismiss ? initialFrom : CGRectZero;
        context->_initialTo = CGRectZero;
        context->_finalTo = finalTo;
        context->_interactive = interactor != nil;

        NSTimeInterval duration = [animator transitionDuration:context];
        id<UIViewControllerTransitionCoordinator> coordinator = to.transitionCoordinator ?: from.transitionCoordinator;
        if ([coordinator isKindOfClass:[CharonTransitionCoordinator class]])
            [(CharonTransitionCoordinator *)coordinator setContainer:container duration:duration];

        context->_finish = ^(BOOL didComplete) {
            if (didComplete) {
                [toView removeFromSuperview];
                [toPost restoreView:toView];
                [fromView removeFromSuperview];
                if (keepsPresenter)
                    [fromPre restoreView:fromView];
            } else {
                [toView removeFromSuperview];
                if (undo)
                    undo();
                [fromView removeFromSuperview];
                [fromPre restoreView:fromView];
            }
            [container removeFromSuperview];
            NSArray *pending = charon_take_pending(begun);
            charon_set_mode(begun, CharonDeferralPass);
            NSMutableArray *appear = [NSMutableArray array], *disappear = [NSMutableArray array];
            for (NSArray *entry in pending)
            {
                NSMutableArray *target = [entry[1] hasSuffix:@"Appear:"] ? appear : disappear;
                [target addObject:entry];
            }
            NSArray *ordered = modal ? [appear arrayByAddingObjectsFromArray:disappear] : [disappear arrayByAddingObjectsFromArray:appear];
            for (NSArray *entry in ordered)
                ((void (*)(id, SEL, BOOL))objc_msgSend)(entry[0], NSSelectorFromString(entry[1]), YES);
            charon_set_mode(begun, CharonDeferralSwallow);
            dispatch_async(dispatch_get_main_queue(), ^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    for (NSArray *entry in begun)
                        if ([entry[1] owners] == 1)
                            [entry[1] setMode:CharonDeferralPass];
                    charon_release_deferral(begun);
                });
            });
            if ([coordinator isKindOfClass:[CharonTransitionCoordinator class]])
                [(CharonTransitionCoordinator *)coordinator finish];
            if (completion)
                completion(didComplete);
            if ([animator respondsToSelector:@selector(animationEnded:)])
                [animator animationEnded:didComplete];
        };

        if (interactor)
            [interactor startInteractiveTransition:context];
        else
            [animator animateTransition:context];
    };
    if (modal)
        run();
    else
        dispatch_async(dispatch_get_main_queue(), run);
    return YES;
}
