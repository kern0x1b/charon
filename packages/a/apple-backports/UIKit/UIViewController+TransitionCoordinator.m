#import "CharonTransitionCoordinator.h"
#import "CharonCustomTransition.h"
#import <objc/runtime.h>

static const char charon_coordinator_key;
static const char charon_transitioning_delegate_key;

@implementation UIViewController (CharonTransitionCoordinator)

- (id<UIViewControllerTransitioningDelegate>)transitioningDelegate
{
    return objc_getAssociatedObject(self, &charon_transitioning_delegate_key);
}

- (void)setTransitioningDelegate:(id<UIViewControllerTransitioningDelegate>)delegate
{
    objc_setAssociatedObject(self, &charon_transitioning_delegate_key, delegate, OBJC_ASSOCIATION_ASSIGN);
}

- (id<UIViewControllerTransitionCoordinator>)transitionCoordinator
{
    return objc_getAssociatedObject(self, &charon_coordinator_key);
}

@end

static void charon_attach(UIViewController *controller, CharonTransitionCoordinator *coordinator)
{
    if (controller)
        objc_setAssociatedObject(controller, &charon_coordinator_key, coordinator, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void charon_detach(UIViewController *controller, CharonTransitionCoordinator *coordinator)
{
    if (controller && objc_getAssociatedObject(controller, &charon_coordinator_key) == coordinator)
        objc_setAssociatedObject(controller, &charon_coordinator_key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static CharonTransitionCoordinator *charon_begin(UIViewController *from, UIViewController *to, BOOL animated, BOOL modal, UIModalPresentationStyle style)
{
    CharonTransitionCoordinator *coordinator = [[CharonTransitionCoordinator alloc] initWithFrom:from to:to container:nil animated:animated duration:charon_default_duration(modal) style:style];
    charon_attach(from, coordinator);
    charon_attach(to, coordinator);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [coordinator finish];
        charon_detach(from, coordinator);
        charon_detach(to, coordinator);
    });
    return coordinator;
}

static void charon_end_after(CharonTransitionCoordinator *coordinator, UIViewController *from, UIViewController *to, BOOL animated, BOOL modal)
{
    void (^finish)(void) = ^{
        [coordinator finish];
        charon_detach(from, coordinator);
        charon_detach(to, coordinator);
    };
    if (animated)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(charon_default_duration(modal) * NSEC_PER_SEC)), dispatch_get_main_queue(), finish);
    else
        dispatch_async(dispatch_get_main_queue(), finish);
}

static UIViewController *charon_presenting_root(UIViewController *controller)
{
    UIViewController *root = controller;
    while (root.parentViewController && !root.definesPresentationContext)
        root = root.parentViewController;
    return root;
}

static id<UIViewControllerAnimatedTransitioning> charon_present_animator(UIViewController *presented, UIViewController *presenting, UIViewController *source)
{
    id<UIViewControllerTransitioningDelegate> delegate = presented.transitioningDelegate;
    if (![delegate respondsToSelector:@selector(animationControllerForPresentedController:presentingController:sourceController:)])
        return nil;
    return [delegate animationControllerForPresentedController:presented presentingController:presenting sourceController:source];
}

static UIPresentationController *charon_presentation_for(UIViewController *presented, UIViewController *presenting, UIViewController *source)
{
    UIModalPresentationStyle style = presented.modalPresentationStyle;
    id<UIViewControllerTransitioningDelegate> delegate = presented.transitioningDelegate;
    if (!(style >= 4 && style <= 6) || ![delegate respondsToSelector:@selector(presentationControllerForPresentedViewController:presentingViewController:sourceViewController:)])
        return nil;
    return [delegate presentationControllerForPresentedViewController:presented presentingViewController:presenting sourceViewController:source];
}

static id<UIViewControllerAnimatedTransitioning> charon_dismiss_animator(UIViewController *presented)
{
    id<UIViewControllerTransitioningDelegate> delegate = presented.transitioningDelegate;
    if (![delegate respondsToSelector:@selector(animationControllerForDismissedController:)])
        return nil;
    return [delegate animationControllerForDismissedController:presented];
}

static id<UIViewControllerInteractiveTransitioning> charon_interactor_for(id<UIViewControllerTransitioningDelegate> delegate, id<UIViewControllerAnimatedTransitioning> animator, BOOL presenting)
{
    SEL selector = presenting ? @selector(interactionControllerForPresentation:) : @selector(interactionControllerForDismissal:);
    if (![delegate respondsToSelector:selector])
        return nil;
    return presenting ? [delegate interactionControllerForPresentation:animator] : [delegate interactionControllerForDismissal:animator];
}

static id<UIViewControllerInteractiveTransitioning> charon_navigation_interactor(UINavigationController *navigation, id<UIViewControllerAnimatedTransitioning> animator)
{
    id<UINavigationControllerDelegate> delegate = navigation.delegate;
    if (![delegate respondsToSelector:@selector(navigationController:interactionControllerForAnimationController:)])
        return nil;
    return [delegate navigationController:navigation interactionControllerForAnimationController:animator];
}

static id<UIViewControllerAnimatedTransitioning> charon_navigation_animator(UINavigationController *navigation, UINavigationControllerOperation operation, UIViewController *from, UIViewController *to)
{
    id<UINavigationControllerDelegate> delegate = navigation.delegate;
    if (![delegate respondsToSelector:@selector(navigationController:animationControllerForOperation:fromViewController:toViewController:)])
        return nil;
    return [delegate navigationController:navigation animationControllerForOperation:operation fromViewController:from toViewController:to];
}

static void (^charon_finisher(CharonTransitionCoordinator *coordinator, UIViewController *from, UIViewController *to, void (^completion)(void)))(BOOL)
{
    return ^(BOOL finished) {
        charon_detach(from, coordinator);
        charon_detach(to, coordinator);
        if (completion)
            completion();
    };
}

@interface CharonTransitionCoordinatorInstaller : NSObject
@end

@implementation CharonTransitionCoordinatorInstaller

+ (void)load
{
    Class controller = [UIViewController class];
    SEL present = @selector(presentViewController:animated:completion:);
    Method presentMethod = class_getInstanceMethod(controller, present);
    void (*presentOriginal)(id, SEL, UIViewController *, BOOL, void (^)(void)) = (void (*)(id, SEL, UIViewController *, BOOL, void (^)(void)))method_getImplementation(presentMethod);
    SEL dismiss = @selector(dismissViewControllerAnimated:completion:);
    Method dismissMethod = class_getInstanceMethod(controller, dismiss);
    void (*dismissOriginal)(id, SEL, BOOL, void (^)(void)) = (void (*)(id, SEL, BOOL, void (^)(void)))method_getImplementation(dismissMethod);
    class_replaceMethod(controller, present, imp_implementationWithBlock(^(UIViewController *self, UIViewController *presented, BOOL animated, void (^completion)(void)) {
        UIViewController *presenting = charon_presenting_root(self);
        UIModalPresentationStyle style = presented.modalPresentationStyle;
        UIPresentationController *presentation = charon_presentation_for(presented, presenting, self);
        if (presentation) {
            id<UIViewControllerAnimatedTransitioning> presentationAnimator = animated ? charon_present_animator(presented, presenting, self) : nil;
            CharonTransitionCoordinator *coordinator = charon_begin(presenting, presented, animated, YES, style);
            charon_presentation_present(presenting, presented, presentation, presentationAnimator, ^{
                presented.modalPresentationStyle = UIModalPresentationFullScreen;
                presentOriginal(self, present, presented, NO, nil);
                presented.modalPresentationStyle = style;
            }, charon_finisher(coordinator, presenting, presented, completion));
            return;
        }
        id<UIViewControllerAnimatedTransitioning> animator = animated && (style == UIModalPresentationFullScreen || style >= 4) ? charon_present_animator(presented, presenting, self) : nil;
        if (animator) {
            CharonTransitionCoordinator *coordinator = charon_begin(presenting, presented, YES, YES, style);
            BOOL started = charon_custom_transition(CharonTransitionPresent, presenting, presented, self, animator, charon_interactor_for(presented.transitioningDelegate, animator, YES), style, ^{
                presented.modalPresentationStyle = style >= 4 ? UIModalPresentationFullScreen : style;
                presentOriginal(self, present, presented, NO, nil);
                presented.modalPresentationStyle = style;
            }, ^{
                dismissOriginal(presenting, dismiss, NO, nil);
            }, charon_finisher(coordinator, presenting, presented, completion));
            if (started)
                return;
            charon_detach(presenting, coordinator);
            charon_detach(presented, coordinator);
        }
        CharonTransitionCoordinator *coordinator = charon_begin(self, presented, animated, YES, presented.modalPresentationStyle);
        presentOriginal(self, present, presented, animated, ^{
            [coordinator finish];
            charon_detach(self, coordinator);
            charon_detach(presented, coordinator);
            if (completion)
                completion();
        });
    }), method_getTypeEncoding(presentMethod));

    class_replaceMethod(controller, dismiss, imp_implementationWithBlock(^(UIViewController *self, BOOL animated, void (^completion)(void)) {
        UIViewController *presented = self.presentedViewController ?: self;
        UIViewController *presenting = presented.presentingViewController ?: self;
        UIPresentationController *presentation = presented.presentingViewController ? charon_presentation_controller_of(presented) : nil;
        if (presentation && presentation.containerView) {
            id<UIViewControllerAnimatedTransitioning> presentationAnimator = animated ? charon_dismiss_animator(presented) : nil;
            CharonTransitionCoordinator *coordinator = charon_begin(presented, presenting, animated, YES, presented.modalPresentationStyle);
            charon_presentation_dismiss(presented, presenting, presentation, presentationAnimator, ^{
                dismissOriginal(self, dismiss, NO, nil);
            }, charon_finisher(coordinator, presented, presenting, completion));
            return;
        }
        id<UIViewControllerAnimatedTransitioning> animator = animated && presented.presentingViewController ? charon_dismiss_animator(presented) : nil;
        if (animator) {
            CharonTransitionCoordinator *coordinator = charon_begin(presented, presenting, YES, YES, presented.modalPresentationStyle);
            UIModalPresentationStyle style = presented.modalPresentationStyle;
            BOOL started = charon_custom_transition(CharonTransitionDismiss, presented, presenting, self, animator, charon_interactor_for(presented.transitioningDelegate, animator, NO), style, ^{
                dismissOriginal(self, dismiss, NO, nil);
            }, ^{
                presentOriginal(presenting, present, presented, NO, nil);
            }, charon_finisher(coordinator, presented, presenting, completion));
            if (started)
                return;
            charon_detach(presented, coordinator);
            charon_detach(presenting, coordinator);
        }
        CharonTransitionCoordinator *coordinator = charon_begin(presented, presenting, animated, YES, presented.modalPresentationStyle);
        dismissOriginal(self, dismiss, animated, ^{
            [coordinator finish];
            charon_detach(presented, coordinator);
            charon_detach(presenting, coordinator);
            if (completion)
                completion();
        });
    }), method_getTypeEncoding(dismissMethod));

    Class navigation = [UINavigationController class];
    SEL push = @selector(pushViewController:animated:);
    Method pushMethod = class_getInstanceMethod(navigation, push);
    void (*pushOriginal)(id, SEL, UIViewController *, BOOL) = (void (*)(id, SEL, UIViewController *, BOOL))method_getImplementation(pushMethod);
    SEL pop = @selector(popViewControllerAnimated:);
    Method popMethod = class_getInstanceMethod(navigation, pop);
    UIViewController *(*popOriginal)(id, SEL, BOOL) = (UIViewController *(*)(id, SEL, BOOL))method_getImplementation(popMethod);
    class_replaceMethod(navigation, push, imp_implementationWithBlock(^(UINavigationController *self, UIViewController *pushed, BOOL animated) {
        UIViewController *from = self.topViewController;
        id<UIViewControllerAnimatedTransitioning> animator = animated && from ? charon_navigation_animator(self, UINavigationControllerOperationPush, from, pushed) : nil;
        if (animator) {
            CharonTransitionCoordinator *coordinator = charon_begin(from, pushed, YES, NO, UIModalPresentationNone);
            BOOL started = charon_custom_transition(CharonTransitionPush, from, pushed, self, animator, charon_navigation_interactor(self, animator), UIModalPresentationNone, ^{
                pushOriginal(self, push, pushed, NO);
            }, ^{
                popOriginal(self, pop, NO);
            }, charon_finisher(coordinator, from, pushed, nil));
            if (started)
                return;
            charon_detach(from, coordinator);
            charon_detach(pushed, coordinator);
        }
        BOOL running = animated && from;
        CharonTransitionCoordinator *coordinator = running ? charon_begin(from, pushed, animated, NO, UIModalPresentationNone) : nil;
        pushOriginal(self, push, pushed, animated);
        if (coordinator)
            charon_end_after(coordinator, from, pushed, animated, NO);
    }), method_getTypeEncoding(pushMethod));

    SEL popTo = @selector(popToViewController:animated:);
    Method popToMethod = class_getInstanceMethod(navigation, popTo);
    NSArray *(*popToOriginal)(id, SEL, UIViewController *, BOOL) = (NSArray *(*)(id, SEL, UIViewController *, BOOL))method_getImplementation(popToMethod);
    SEL popRoot = @selector(popToRootViewControllerAnimated:);
    Method popRootMethod = class_getInstanceMethod(navigation, popRoot);
    NSArray *(*popRootOriginal)(id, SEL, BOOL) = (NSArray *(*)(id, SEL, BOOL))method_getImplementation(popRootMethod);
    NSArray *(^popping)(UINavigationController *, UIViewController *, BOOL, NSArray *(^)(BOOL)) = ^NSArray *(UINavigationController *self, UIViewController *target, BOOL animated, NSArray *(^native)(BOOL)) {
        UIViewController *from = self.topViewController;
        BOOL running = from && target && from != target && [self.viewControllers containsObject:target];
        id<UIViewControllerAnimatedTransitioning> animator = animated && running ? charon_navigation_animator(self, UINavigationControllerOperationPop, from, target) : nil;
        if (animator) {
            CharonTransitionCoordinator *coordinator = charon_begin(from, target, YES, NO, UIModalPresentationNone);
            NSArray *stack = self.viewControllers;
            NSUInteger index = [stack indexOfObject:target];
            NSArray *popped = index != NSNotFound ? [stack subarrayWithRange:NSMakeRange(index + 1, stack.count - index - 1)] : @[];
            BOOL started = charon_custom_transition(CharonTransitionPop, from, target, self, animator, charon_navigation_interactor(self, animator), UIModalPresentationNone, ^{
                native(NO);
            }, nil, charon_finisher(coordinator, from, target, nil));
            if (started)
                return popped;
            charon_detach(from, coordinator);
            charon_detach(target, coordinator);
        }
        CharonTransitionCoordinator *coordinator = running ? charon_begin(from, target, animated, NO, UIModalPresentationNone) : nil;
        NSArray *result = native(animated);
        if (coordinator)
            charon_end_after(coordinator, from, target, animated, NO);
        return result;
    };
    class_replaceMethod(navigation, popTo, imp_implementationWithBlock(^NSArray *(UINavigationController *self, UIViewController *target, BOOL animated) {
        return popping(self, target, animated, ^NSArray *(BOOL flag) { return popToOriginal(self, popTo, target, flag); });
    }), method_getTypeEncoding(popToMethod));
    class_replaceMethod(navigation, popRoot, imp_implementationWithBlock(^NSArray *(UINavigationController *self, BOOL animated) {
        return popping(self, self.viewControllers.firstObject, animated, ^NSArray *(BOOL flag) { return popRootOriginal(self, popRoot, flag); });
    }), method_getTypeEncoding(popRootMethod));

    class_replaceMethod(navigation, pop, imp_implementationWithBlock(^UIViewController *(UINavigationController *self, BOOL animated) {
        NSArray *stack = self.viewControllers;
        UIViewController *from = stack.count > 1 ? stack.lastObject : nil;
        UIViewController *to = stack.count > 1 ? stack[stack.count - 2] : nil;
        id<UIViewControllerAnimatedTransitioning> animator = animated && from ? charon_navigation_animator(self, UINavigationControllerOperationPop, from, to) : nil;
        if (animator) {
            CharonTransitionCoordinator *coordinator = charon_begin(from, to, YES, NO, UIModalPresentationNone);
            BOOL started = charon_custom_transition(CharonTransitionPop, from, to, self, animator, charon_navigation_interactor(self, animator), UIModalPresentationNone, ^{
                popOriginal(self, pop, NO);
            }, ^{
                pushOriginal(self, push, from, NO);
            }, charon_finisher(coordinator, from, to, nil));
            if (started)
                return from;
            charon_detach(from, coordinator);
            charon_detach(to, coordinator);
        }
        CharonTransitionCoordinator *coordinator = from ? charon_begin(from, to, animated, NO, UIModalPresentationNone) : nil;
        UIViewController *result = popOriginal(self, pop, animated);
        if (coordinator)
            charon_end_after(coordinator, from, to, animated, NO);
        return result;
    }), method_getTypeEncoding(popMethod));
}

@end
