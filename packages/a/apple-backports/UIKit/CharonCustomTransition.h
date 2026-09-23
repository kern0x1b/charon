#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, CharonTransitionKind) {
    CharonTransitionPresent,
    CharonTransitionDismiss,
    CharonTransitionPush,
    CharonTransitionPop
};

@interface CharonTransitionContext : NSObject <UIViewControllerContextTransitioning>
- (id<UIViewControllerAnimatedTransitioning>)charon_animator;
@end

BOOL charon_custom_transition(CharonTransitionKind kind, UIViewController *from, UIViewController *to, UIViewController *source, id<UIViewControllerAnimatedTransitioning> animator, id<UIViewControllerInteractiveTransitioning> interactor, UIModalPresentationStyle style, void (^native)(void), void (^undo)(void), void (^completion)(BOOL finished));

@interface UIPresentationController (CharonContainer)
- (void)charon_setContainerView:(UIView *)view;
/* Whether this presentation controller presents its controller itself from that presenting
   controller (a sheet does in a compact width), and the animator it presents and dismisses
   with when the transitioning delegate answers none; NO and nil here. */
- (BOOL)charon_presentsFrom:(UIViewController *)presenting;
- (id<UIViewControllerAnimatedTransitioning>)charon_transitionAnimator;
/* Whether a touch on the container itself, on none of its views, goes through to what is
   under it; NO here, as UIKit's transition view keeps it. */
- (BOOL)charon_containerIgnoresDirectTouches;
@end

UIPresentationController *charon_presentation_controller_of(UIViewController *controller);
void charon_set_presentation_controller(UIViewController *controller, UIPresentationController *presentation);

void charon_presentation_present(UIViewController *presenting, UIViewController *presented, UIPresentationController *presentation, id<UIViewControllerAnimatedTransitioning> animator, void (^native)(void), void (^completion)(BOOL finished));
void charon_presentation_dismiss(UIViewController *presented, UIViewController *presenting, UIPresentationController *presentation, id<UIViewControllerAnimatedTransitioning> animator, void (^native)(void), void (^completion)(BOOL finished));

id<UIViewControllerAnimatedTransitioning> charon_edge_pop_animator(UINavigationController *navigation);
id<UIViewControllerInteractiveTransitioning> charon_edge_pop_interactor(UINavigationController *navigation);

BOOL charon_popover_present(UIViewController *presenting, UIViewController *presented, BOOL animated, void (^completion)(void));
BOOL charon_popover_dismiss(UIViewController *controller, BOOL animated, void (^completion)(void));

BOOL charon_document_menu_present(UIViewController *presenting, UIViewController *presented, BOOL animated, void (^completion)(void));
