#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "CharonDragDrop.h"
#import "CharonDragSession.h"

#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
#pragma clang diagnostic ignored "-Wobjc-property-implementation"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

// The drop interaction's own question is declared before the drag asks it, because the drop's
// category appears further down and the drag needs to know the drop will have the session.
@interface UIDropInteraction (CharonDropQuery)
- (BOOL)isEnabled;
@end

// The two interactions a drag is made of: one that lifts and carries, one that receives.
//
// The gestures are the release's own, which is what makes this a drag and not a swipe: a long press
// lifts the item under the touch and a pan carries the preview that lift made, and letting go is the
// drop. Nothing here reaches outside the application, because on this release there is no service to
// reach: the preview is added to the application's own window, travels between the application's own
// windows, and the drop is the one that started in the same process.

@interface UIDragInteraction () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) CharonDragSession *session;
@property (nonatomic, strong) UIImageView *preview;
@property (nonatomic, strong) UILongPressGestureRecognizer *lift;
@property (nonatomic, strong) UIPanGestureRecognizer *carry;
@property (nonatomic, strong) NSMutableSet<UIDropInteraction *> *dropTargets;
@property (nonatomic, strong) CharonDropSession *currentDrop;
@property (nonatomic, assign) CGPoint liftPoint;
@end

@implementation UIDragInteraction {
@private
    __weak id<UIDragInteractionDelegate> _delegate;
    BOOL _enabled;
}

- (instancetype)initWithDelegate:(id<UIDragInteractionDelegate>)delegate
{
    if ((self = [super init])) {
        _delegate = delegate;
        _enabled = [UIDragInteraction isEnabledByDefault];
        [self charon_installGestures];
    }
    return self;
}

- (id<UIDragInteractionDelegate>)delegate
{
    return _delegate;
}

- (void)setDelegate:(id<UIDragInteractionDelegate>)delegate
{
    _delegate = delegate;
}

- (BOOL)isEnabled
{
    return _enabled;
}

- (void)setEnabled:(BOOL)enabled
{
    _enabled = enabled;
    self.lift.enabled = enabled;
    self.carry.enabled = enabled;
}

+ (BOOL)isEnabledByDefault
{
    // A drag is off unless the application asks for it, which is what a release that has no drag
    // service can honestly default to: nothing lifts unless an interaction for it exists.
    return YES;
}

- (UIView *)view
{
    return self.lift.view;
}

- (void)charon_installGestures
{
    if (self.lift)
        return;
    UILongPressGestureRecognizer *lift = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                        action:@selector(charon_lift:)];
    // A drag begins with a press that stays, which is what a long press is; a shorter one is a tap
    // and a longer drag is a carry, so the two gestures cannot be confused for one another.
    lift.minimumPressDuration = 0.5;
    lift.delegate = self;
    UIPanGestureRecognizer *carry = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(charon_carry:)];
    carry.delegate = self;
    self.lift = lift;
    self.carry = carry;
    self.dropTargets = [NSMutableSet set];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other
{
    return self.allowsSimultaneousRecognitionDuringLift;
}

// The lift: what is under the touch becomes the session's items, the delegate is asked, and the
// preview is made from the view under the touch and put in the window so the carry has something to
// move.
- (void)charon_lift:(UILongPressGestureRecognizer *)recognizer
{
    UIView *view = recognizer.view;
    if (!view)
        return;
    switch (recognizer.state) {
    case UIGestureRecognizerStateBegan: {
        CGPoint point = [recognizer locationInView:view];
        self.liftPoint = point;
        UIView *under = [view hitTest:point withEvent:nil];
        if (!under)
            return;
        CharonDragSession *session = [[CharonDragSession alloc] initWithItems:@[] interaction:self];
        session.location = point;
        NSArray<UIDragItem *> *items = nil;
        if ([_delegate respondsToSelector:@selector(dragInteraction:itemsForBeginningSession:)])
            items = [(id<UIDragInteractionDelegate>)_delegate dragInteraction:self itemsForBeginningSession:session];
        else
            items = [self charon_defaultItemsForView:under];
        (void)under;
        if (!items.count)
            return;
        session.items = [items mutableCopy];
        self.session = session;
        if ([_delegate respondsToSelector:@selector(dragInteraction:sessionAllowsMoveOperation:)])
            session.allowsMoveOperation = [(id<UIDragInteractionDelegate>)_delegate dragInteraction:self sessionAllowsMoveOperation:session];
        UITargetedDragPreview *preview = nil;
        if ([_delegate respondsToSelector:@selector(dragInteraction:previewForLiftingItem:session:)])
            preview = [(id<UIDragInteractionDelegate>)_delegate dragInteraction:self previewForLiftingItem:session.items.firstObject session:session];
        if (preview)
            [self charon_showPreview:preview.view at:point inView:view];
        else
            [self charon_showView:under at:point inView:view];
        if ([_delegate respondsToSelector:@selector(dragInteraction:sessionWillBegin:)])
            [(id<UIDragInteractionDelegate>)_delegate dragInteraction:self sessionWillBegin:session];
        break;
    }
    case UIGestureRecognizerStateEnded:
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed:
        [self charon_finishDragCancelled:recognizer.state != UIGestureRecognizerStateEnded];
        break;
    default:
        break;
    }
}

// The carry: the preview follows the finger, and the drop interaction under it is asked what it
// makes of the session as it moves, which is how a proposal reaches the delegate while the drag is
// still in the air.
- (void)charon_carry:(UIPanGestureRecognizer *)recognizer
{
    CharonDragSession *session = self.session;
    if (!session)
        return;
    UIView *view = recognizer.view;
    CGPoint point = [recognizer locationInView:view];
    session.location = point;
    switch (recognizer.state) {
    case UIGestureRecognizerStateBegan:
    case UIGestureRecognizerStateChanged:
        [self charon_movePreviewTo:point inView:view];
        [self charon_updateDropUnder:point inView:view];
        if ([_delegate respondsToSelector:@selector(dragInteraction:sessionDidMove:)])
            [(id<UIDragInteractionDelegate>)_delegate dragInteraction:self sessionDidMove:session];
        break;
    case UIGestureRecognizerStateEnded:
        [self charon_finishDragCancelled:NO];
        break;
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed:
        [self charon_finishDragCancelled:YES];
        break;
    default:
        break;
    }
}

// What is being dragged when the application has not said. A view cannot be put in an item provider
// on this release — the provider writes objects that can be read back, and a view is not one — and
// guessing a payload for it would move the wrong data, so a drag with no delegate says nothing is
// being dragged and the lift ends there. The delegate is the only thing that knows.
- (NSArray<UIDragItem *> *)charon_defaultItemsForView:(UIView *)view
{
    (void)view;
    return @[];
}

// A delegate's targeted preview names the view it shows, and a lift with no preview shows the view
// under the touch: either way what is carried is a still picture of a view, added to the
// application's own window.
- (void)charon_showPreview:(UIView *)preview at:(CGPoint)point inView:(UIView *)view
{
    [self charon_showView:preview at:point inView:view];
}

- (void)charon_showView:(UIView *)shown at:(CGPoint)point inView:(UIView *)view
{
    UIWindow *window = view.window;
    if (!window || !shown)
        return;
    UIImage *picture = [self charon_pictureForView:shown];
    if (!picture)
        return;
    UIImageView *image = [[UIImageView alloc] initWithImage:picture];
    image.frame = CGRectMake(point.x - picture.size.width / 2, point.y - picture.size.height / 2,
                             picture.size.width, picture.size.height);
    image.layer.zPosition = 10000;
    [window addSubview:image];
    self.preview = image;
}

- (UIImage *)charon_pictureForView:(UIView *)view
{
    if (!view || CGRectIsEmpty(view.bounds))
        return nil;
    // The still picture a preview is: the view rendered as it is now, which is what a lift shows.
    UIGraphicsBeginImageContextWithOptions(view.bounds.size, NO, 0);
    [view.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *picture = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return picture;
}

- (void)charon_movePreviewTo:(CGPoint)point inView:(UIView *)view
{
    UIImageView *preview = self.preview;
    UIWindow *window = view.window;
    if (!preview || !window)
        return;
    CGPoint inWindow = [window convertPoint:point fromView:view];
    preview.center = inWindow;
}

// The drop side: the interactions registered for this application are asked, in the order they were
// added, which one will have the session under the point, and the one that says yes is told that the
// session entered and then updated.
- (void)charon_updateDropUnder:(CGPoint)point inView:(UIView *)view
{
    for (UIDropInteraction *drop in self.dropTargets) {
        UIView *dropView = drop.view;
        if (!dropView || !dropView.window || ![drop isEnabled])
            continue;
        if (![dropView pointInside:[dropView convertPoint:point fromView:view] withEvent:nil])
            continue;
        CharonDropSession *session = [[CharonDropSession alloc] initWithDragSession:self.session interaction:drop];
        id<UIDropInteractionDelegate> delegate = drop.delegate;
        if ([delegate respondsToSelector:@selector(dropInteraction:canHandleSession:)])
            if (![(id<UIDropInteractionDelegate>)delegate dropInteraction:drop canHandleSession:session])
                continue;
        if (self.currentDrop.interaction != drop) {
            [self charon_exitCurrentDrop];
            self.currentDrop = session;
            if ([delegate respondsToSelector:@selector(dropInteraction:sessionDidEnter:)])
                [(id<UIDropInteractionDelegate>)delegate dropInteraction:drop sessionDidEnter:session];
        }
        if ([delegate respondsToSelector:@selector(dropInteraction:sessionDidUpdate:)])
            [(id<UIDropInteractionDelegate>)delegate dropInteraction:drop sessionDidUpdate:session];
        return;
    }
    [self charon_exitCurrentDrop];
}

- (void)charon_exitCurrentDrop
{
    CharonDropSession *current = self.currentDrop;
    if (!current)
        return;
    id<UIDropInteractionDelegate> delegate = current.interaction.delegate;
    if ([delegate respondsToSelector:@selector(dropInteraction:sessionDidExit:)])
        [(id<UIDropInteractionDelegate>)delegate dropInteraction:current.interaction sessionDidExit:current];
    self.currentDrop = nil;
}

// The end of a drag: the drop that is under it is told to perform the drop and then to conclude it,
// and the drag's own delegate is told what the drag ended with. A drag that was called off ends with
// a cancelled operation and tells the same delegate.
- (void)charon_finishDragCancelled:(BOOL)cancelled
{
    CharonDragSession *session = self.session;
    if (!session)
        return;
    UIDropOperation operation = UIDropOperationCancel;
    CharonDropSession *drop = self.currentDrop;
    if (drop && !cancelled) {
        id<UIDropInteractionDelegate> delegate = drop.interaction.delegate;
        if ([delegate respondsToSelector:@selector(dropInteraction:performDrop:)])
            [(id<UIDropInteractionDelegate>)delegate dropInteraction:drop.interaction performDrop:drop];
        if ([delegate respondsToSelector:@selector(dropInteraction:concludeDrop:)])
            [(id<UIDropInteractionDelegate>)delegate dropInteraction:drop.interaction concludeDrop:drop];
        if ([delegate respondsToSelector:@selector(dropInteraction:sessionDidEnd:)])
            [(id<UIDropInteractionDelegate>)delegate dropInteraction:drop.interaction sessionDidEnd:drop];
        operation = UIDropOperationMove;
    }
    if ([_delegate respondsToSelector:@selector(dragInteraction:session:willEndWithOperation:)])
        [(id<UIDragInteractionDelegate>)_delegate dragInteraction:self session:session willEndWithOperation:operation];
    [self.preview removeFromSuperview];
    self.preview = nil;
    self.currentDrop = nil;
    self.session = nil;
    if ([_delegate respondsToSelector:@selector(dragInteraction:session:didEndWithOperation:)])
        [(id<UIDragInteractionDelegate>)_delegate dragInteraction:self session:session didEndWithOperation:operation];
}

@end

@interface UIDropInteraction () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UILongPressGestureRecognizer *accept;
@end

@implementation UIDropInteraction {
@private
    __weak id<UIDropInteractionDelegate> _delegate;
    BOOL _allowsSimultaneousDropSessions;
}

- (instancetype)initWithDelegate:(id<UIDropInteractionDelegate>)delegate
{
    if ((self = [super init])) {
        _delegate = delegate;
        // A drop target is registered with every drag the application has, so a drag knows where it
        // can be let go. This is the application's own list, in the application's own process.
        for (UIWindow *window in [UIApplication sharedApplication].windows)
            for (UIView *view in window.subviews)
                for (UIDragInteraction *drag in view.interactions)
                    if ([drag isKindOfClass:[UIDragInteraction class]])
                        [drag.dropTargets addObject:self];
    }
    return self;
}

- (id<UIDropInteractionDelegate>)delegate
{
    return _delegate;
}

- (void)setDelegate:(id<UIDropInteractionDelegate>)delegate
{
    _delegate = delegate;
}

- (BOOL)allowsSimultaneousDropSessions
{
    return _allowsSimultaneousDropSessions;
}

- (void)setAllowsSimultaneousDropSessions:(BOOL)allows
{
    _allowsSimultaneousDropSessions = allows;
}

- (UIView *)view
{
    return self.accept ? self.accept.view : nil;
}

- (BOOL)isEnabled
{
    return self.accept != nil;
}

- (void)setEnabled:(BOOL)enabled
{
    if (enabled && !self.accept) {
        UILongPressGestureRecognizer *accept = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                             action:@selector(charon_accept:)];
        accept.minimumPressDuration = 0.5;
        accept.delegate = self;
        self.accept = accept;
    }
    self.accept.enabled = enabled;
}

- (void)charon_accept:(UILongPressGestureRecognizer *)recognizer
{
    // A drop arrives as a drag that is already under this view; the drag interaction does the work
    // and asks this one, so there is nothing to do with the press itself beyond letting the drag
    // know this view will have it.
}

@end
