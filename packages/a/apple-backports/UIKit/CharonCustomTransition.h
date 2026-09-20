#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, CharonTransitionKind) {
    CharonTransitionPresent,
    CharonTransitionDismiss,
    CharonTransitionPush,
    CharonTransitionPop
};

@interface CharonTransitionContext : NSObject <UIViewControllerContextTransitioning>
@end

BOOL charon_custom_transition(CharonTransitionKind kind, UIViewController *from, UIViewController *to, UIViewController *source, id<UIViewControllerAnimatedTransitioning> animator, id<UIViewControllerInteractiveTransitioning> interactor, UIModalPresentationStyle style, void (^native)(void), void (^undo)(void), void (^completion)(BOOL finished));
