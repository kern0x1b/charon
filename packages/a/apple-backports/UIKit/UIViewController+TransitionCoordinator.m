#import "CharonTransitionCoordinator.h"
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

@interface CharonTransitionCoordinatorInstaller : NSObject
@end

@implementation CharonTransitionCoordinatorInstaller

+ (void)load
{
    Class controller = [UIViewController class];
    SEL present = @selector(presentViewController:animated:completion:);
    Method presentMethod = class_getInstanceMethod(controller, present);
    void (*presentOriginal)(id, SEL, UIViewController *, BOOL, void (^)(void)) = (void (*)(id, SEL, UIViewController *, BOOL, void (^)(void)))method_getImplementation(presentMethod);
    class_replaceMethod(controller, present, imp_implementationWithBlock(^(UIViewController *self, UIViewController *presented, BOOL animated, void (^completion)(void)) {
        CharonTransitionCoordinator *coordinator = charon_begin(self, presented, animated, YES, presented.modalPresentationStyle);
        presentOriginal(self, present, presented, animated, ^{
            [coordinator finish];
            charon_detach(self, coordinator);
            charon_detach(presented, coordinator);
            if (completion)
                completion();
        });
    }), method_getTypeEncoding(presentMethod));

    SEL dismiss = @selector(dismissViewControllerAnimated:completion:);
    Method dismissMethod = class_getInstanceMethod(controller, dismiss);
    void (*dismissOriginal)(id, SEL, BOOL, void (^)(void)) = (void (*)(id, SEL, BOOL, void (^)(void)))method_getImplementation(dismissMethod);
    class_replaceMethod(controller, dismiss, imp_implementationWithBlock(^(UIViewController *self, BOOL animated, void (^completion)(void)) {
        UIViewController *presented = self.presentedViewController ?: self;
        UIViewController *presenting = presented.presentingViewController ?: self;
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
    class_replaceMethod(navigation, push, imp_implementationWithBlock(^(UINavigationController *self, UIViewController *pushed, BOOL animated) {
        UIViewController *from = self.topViewController;
        BOOL running = animated && from;
        CharonTransitionCoordinator *coordinator = running ? charon_begin(from, pushed, animated, NO, UIModalPresentationNone) : nil;
        pushOriginal(self, push, pushed, animated);
        if (coordinator)
            charon_end_after(coordinator, from, pushed, animated, NO);
    }), method_getTypeEncoding(pushMethod));

    SEL popTo = @selector(popToViewController:animated:);
    Method popToMethod = class_getInstanceMethod(navigation, popTo);
    NSArray *(*popToOriginal)(id, SEL, UIViewController *, BOOL) = (NSArray *(*)(id, SEL, UIViewController *, BOOL))method_getImplementation(popToMethod);
    class_replaceMethod(navigation, popTo, imp_implementationWithBlock(^NSArray *(UINavigationController *self, UIViewController *target, BOOL animated) {
        UIViewController *from = self.topViewController;
        BOOL running = from && target && from != target && [self.viewControllers containsObject:target];
        CharonTransitionCoordinator *coordinator = running ? charon_begin(from, target, animated, NO, UIModalPresentationNone) : nil;
        NSArray *result = popToOriginal(self, popTo, target, animated);
        if (coordinator)
            charon_end_after(coordinator, from, target, animated, NO);
        return result;
    }), method_getTypeEncoding(popToMethod));

    SEL popRoot = @selector(popToRootViewControllerAnimated:);
    Method popRootMethod = class_getInstanceMethod(navigation, popRoot);
    NSArray *(*popRootOriginal)(id, SEL, BOOL) = (NSArray *(*)(id, SEL, BOOL))method_getImplementation(popRootMethod);
    class_replaceMethod(navigation, popRoot, imp_implementationWithBlock(^NSArray *(UINavigationController *self, BOOL animated) {
        UIViewController *from = self.topViewController;
        UIViewController *root = self.viewControllers.firstObject;
        BOOL running = from && root && from != root;
        CharonTransitionCoordinator *coordinator = running ? charon_begin(from, root, animated, NO, UIModalPresentationNone) : nil;
        NSArray *result = popRootOriginal(self, popRoot, animated);
        if (coordinator)
            charon_end_after(coordinator, from, root, animated, NO);
        return result;
    }), method_getTypeEncoding(popRootMethod));

    SEL pop = @selector(popViewControllerAnimated:);
    Method popMethod = class_getInstanceMethod(navigation, pop);
    UIViewController *(*popOriginal)(id, SEL, BOOL) = (UIViewController *(*)(id, SEL, BOOL))method_getImplementation(popMethod);
    class_replaceMethod(navigation, pop, imp_implementationWithBlock(^UIViewController *(UINavigationController *self, BOOL animated) {
        NSArray *stack = self.viewControllers;
        UIViewController *from = stack.count > 1 ? stack.lastObject : nil;
        UIViewController *to = stack.count > 1 ? stack[stack.count - 2] : nil;
        CharonTransitionCoordinator *coordinator = from ? charon_begin(from, to, animated, NO, UIModalPresentationNone) : nil;
        UIViewController *result = popOriginal(self, pop, animated);
        if (coordinator)
            charon_end_after(coordinator, from, to, animated, NO);
        return result;
    }), method_getTypeEncoding(popMethod));
}

@end
