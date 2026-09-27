#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

// The collection view's half of a layout transition: it takes the two layouts, hands the new one
// to the transition layout it puts in place of the old, and drives the progress from where the
// transition started to the end the caller asked for, settling on the layout that end names. The
// release's collection view lays out through the invalidation context but never makes a transition
// layout or moves one, so all of this is the port's own; the answers it gives are the host's own
// UIKit under Mac Catalyst (macOS 27.0), held against this file by
// tests/backports/host/collectiontransition.
static const char CharonTransitionKey;
static const NSTimeInterval CharonTransitionDuration = 0.35;

@interface CharonLayoutTransition : NSObject
@property (nonatomic, strong) UICollectionViewTransitionLayout *layout;
@property (nonatomic, strong) UICollectionViewLayout *from;
@property (nonatomic, strong) UICollectionViewLayout *to;
@property (nonatomic, copy) UICollectionViewLayoutInteractiveTransitionCompletion completion;
@property (nonatomic, strong) UICollectionView *view;
@property (nonatomic) CGFloat start;
@property (nonatomic) CGFloat target;
@property (nonatomic) BOOL finishing;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSDate *began;
// A layout asked for while this transition was still running. The transition is not dropped and
// not raced: the change waits for it to settle, so the timer cannot put the layout it is heading
// for back over the one that was asked for in the meantime.
@property (nonatomic, strong) UICollectionViewLayout *pending;
@end

@implementation CharonLayoutTransition
@synthesize layout = _layout;
@synthesize from = _from;
@synthesize to = _to;
@synthesize completion = _completion;
@synthesize view = _view;
@synthesize start = _start;
@synthesize target = _target;
@synthesize finishing = _finishing;
@synthesize timer = _timer;
@synthesize began = _began;
@synthesize pending = _pending;

// The progress is moved here rather than inside a UIView animation block, because it is the
// layout that reads it: the release animates no layout property, and a block that only set the
// number would leave every cell where it was.
- (void)tick
{
    NSTimeInterval elapsed = -[_began timeIntervalSinceNow];
    CGFloat span = _target - _start;
    CGFloat progress = elapsed >= CharonTransitionDuration ? _target
                       : _start + span * (CGFloat)(elapsed / CharonTransitionDuration);
    _layout.transitionProgress = progress;
    if (elapsed < CharonTransitionDuration)
        return;
    [_timer invalidate];
    _timer = nil;
    UICollectionView *view = _view;
    UICollectionViewLayout *settled = span >= 0 ? _to : _from;
    BOOL finished = span >= 0;
    view.collectionViewLayout = settled;
    UICollectionViewLayout *pending = _pending;
    _pending = nil;
    if (pending)
        view.collectionViewLayout = pending;
    objc_setAssociatedObject(view, &CharonTransitionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // The transition layout passes the message on to both the layout it came from and the one it
    // went to, so the layout that is settled is told through it and not a second time.
    [_layout finalizeLayoutTransition];
    UICollectionViewLayoutInteractiveTransitionCompletion completion = _completion;
    _completion = nil;
    // The completion is handed after the layout is the one the caller asked for, so a block that
    // reads the collection view's layout sees what it was promised.
    if (completion)
        completion(finished, YES);
}
@end

@implementation UICollectionView (CharonInteractiveTransition)

- (CharonLayoutTransition *)charon_layoutTransition
{
    return objc_getAssociatedObject(self, &CharonTransitionKey);
}

- (UICollectionViewTransitionLayout *)startInteractiveTransitionToCollectionViewLayout:(UICollectionViewLayout *)layout
                                                                            completion:(UICollectionViewLayoutInteractiveTransitionCompletion)completion
{
    // One transition at a time, and never to the layout already in place: both are refused, as
    // the host refuses them, rather than left to answer something a second transition would
    // contradict.
    if (!layout || layout == self.collectionViewLayout || [self charon_layoutTransition])
        return nil;
    UICollectionViewLayout *from = self.collectionViewLayout;
    CharonLayoutTransition *transition = [[CharonLayoutTransition alloc] init];
    transition.from = from;
    transition.to = layout;
    transition.view = self;
    transition.completion = completion;
    transition.layout = [[UICollectionViewTransitionLayout alloc] initWithCurrentLayout:from nextLayout:layout];
    transition.start = transition.layout.transitionProgress;
    objc_setAssociatedObject(self, &CharonTransitionKey, transition, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Both layouts are told before either is put in place, so a layout that snapshots its own
    // state for the transition has taken it before the collection view lays out against it.
    [from prepareForTransitionToLayout:layout];
    [layout prepareForTransitionFromLayout:from];
    self.collectionViewLayout = transition.layout;
    return transition.layout;
}

- (void)charon_settleLayoutTransition:(CharonLayoutTransition *)transition target:(CGFloat)target
{
    if (transition.finishing)
        return;
    transition.finishing = YES;
    [transition.timer invalidate];
    transition.start = transition.layout.transitionProgress;
    transition.target = target;
    transition.began = [NSDate date];
    transition.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60
                                                       target:transition
                                                     selector:@selector(tick)
                                                     userInfo:nil
                                                      repeats:YES];
}

- (void)finishInteractiveTransition
{
    CharonLayoutTransition *transition = [self charon_layoutTransition];
    if (!transition)
        return;
    [self charon_settleLayoutTransition:transition target:1.0];
}

- (void)cancelInteractiveTransition
{
    CharonLayoutTransition *transition = [self charon_layoutTransition];
    if (!transition)
        return;
    [self charon_settleLayoutTransition:transition target:0.0];
}

- (void)setCollectionViewLayout:(UICollectionViewLayout *)layout animated:(BOOL)animated completion:(void (^)(BOOL finished))completion
{
    if (!layout) {
        if (completion)
            completion(NO);
        return;
    }
    // Without an animation there is nothing to drive a progress for, so the layout is simply put
    // in place; with one, this is the transition run to its end. This block is handed a finished
    // alone, where the interactive one is handed a completed and a finished, so it is wrapped.
    if (!animated) {
        self.collectionViewLayout = layout;
        if (completion)
            completion(YES);
        return;
    }
    CharonLayoutTransition *running = [self charon_layoutTransition];
    if (running) {
        // A transition is already under way. It is not dropped and the layout is not put in place
        // under it: the change is held until that transition settles, and the block is handed a
        // finished once the collection view really is holding the layout that was asked for.
        UICollectionViewLayout *waiting = layout;
        void (^wrapped)(BOOL) = completion;
        running.pending = waiting;
        if (wrapped) {
            UICollectionViewLayoutInteractiveTransitionCompletion previous = running.completion;
            running.completion = ^(BOOL completed, BOOL finished) {
                if (previous)
                    previous(completed, finished);
                wrapped(YES);
            };
        }
        return;
    }
    UICollectionViewTransitionLayout *transition =
        [self startInteractiveTransitionToCollectionViewLayout:layout
                                                    completion:^(BOOL completed, BOOL finished) {
        if (completion)
            completion(finished);
    }];
    if (!transition) {
        self.collectionViewLayout = layout;
        if (completion)
            completion(YES);
        return;
    }
    [self finishInteractiveTransition];
}

@end
