// dynamics-watch.m - the shipped UIDynamicAnimator's watch of its reference view (CharonReferenceViewWatch in
// UIDynamicAnimator.mm) on the release it runs on: what wakes a resting animator, and what KVO says when the
// animator or the view is released first (facts/UIKit/UIDynamicAnimator.md M3). Where uiview-kvo.m measures the release's
// KVO with a probe's own observer, this runs the class the backport ships. A command-line program, no UIApplicationMain:
// build it as a daemon target that requires charon@apple-backports (add_packages and
// set_values("charon.libraries", ...), README's test port) and run it with `xmake emulate -d iPhone4,1 -r 6.1.3 run
// /usr/libexec/<name>`. It exits with the number of failed checks; the KVO line of a leaked observer is on stderr, and
// the run's log is read for it: `was deallocated while key value observers were still registered` must not be there.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface Resumes : NSObject <UIDynamicAnimatorDelegate>
@property (nonatomic) int count;
@end

@implementation Resumes
- (void)dynamicAnimatorWillResume:(UIDynamicAnimator *)animator
{
    self.count++;
}
@end

@interface UIDynamicAnimator (Private)
- (void)_setAlwaysDisableDisplayLink:(BOOL)disable;
@end

static int failures;

static void check(BOOL ok, NSString *what)
{
    NSLog(@"%@ %@", ok ? @"ok  " : @"FAIL", what);
    if (!ok)
        failures++;
}

static UIDynamicAnimator *animator_over(UIView *view, Resumes *resumes)
{
    UIDynamicAnimator *animator = [[UIDynamicAnimator alloc] initWithReferenceView:view];
    animator.delegate = resumes;
    UIView *item = [[UIView alloc] initWithFrame:CGRectMake(100, 100, 40, 40)];
    [view addSubview:item];
    [animator addBehavior:[[UIGravityBehavior alloc] initWithItems:@[item]]];
    return animator;
}

// Whether `change` woke an animator that was at rest: stopped the way an animator at rest is, the switch that keeps it
// from a display link, then released.
static BOOL wakes(UIDynamicAnimator *animator, Resumes *resumes, void (^change)(void))
{
    [animator _setAlwaysDisableDisplayLink:YES];
    [animator _setAlwaysDisableDisplayLink:NO];
    int before = resumes.count;
    change();
    return resumes.count > before;
}

int main(void)
{
    @autoreleasepool {
        NSLog(@"dynamics watch: %@", [[UIDevice currentDevice] systemVersion]);
        {
            UIView *superview = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 600, 800)];
            UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 400)];
            view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [superview addSubview:view];
            Resumes *resumes = [Resumes new];
            UIDynamicAnimator *animator = animator_over(view, resumes);
            check(wakes(animator, resumes, ^{ view.frame = CGRectMake(0, 0, 300, 600); }), @"(a) view.frame wakes");
            check(wakes(animator, resumes, ^{ view.bounds = CGRectMake(0, 0, 320, 600); }), @"(b) view.bounds wakes");
            check(wakes(animator, resumes, ^{ superview.frame = CGRectMake(0, 0, 600, 1000); }), @"(e) autoresizing wakes");
            check(!wakes(animator, resumes, ^{ view.layer.bounds = CGRectMake(0, 0, 300, 700); }), @"(c) layer.bounds does not wake");
            check(!wakes(animator, resumes, ^{ view.center = CGPointMake(200, 300); }), @"(g) center does not wake");
            check(!wakes(animator, resumes, ^{ view.transform = CGAffineTransformMakeScale(2, 2); }), @"(h) transform does not wake");
            NSLog(@"lifetime 1: releasing the animator, then the view");
            animator = nil;
            NSLog(@"lifetime 1: animator released, releasing the view");
        }
        NSLog(@"lifetime 1: view released");
        {
            UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 400)];
            Resumes *resumes = [Resumes new];
            UIDynamicAnimator *animator = animator_over(view, resumes);
            NSLog(@"lifetime 2: releasing the view, the animator still alive (%@)", animator);
            view = nil;
            NSLog(@"lifetime 2: view released, releasing the animator");
            animator = nil;
        }
        NSLog(@"lifetime 2: animator released");
        {
            UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 400)];
            Resumes *first = [Resumes new], *second = [Resumes new];
            UIDynamicAnimator *one = animator_over(view, first);
            UIDynamicAnimator *two = animator_over(view, second);
            NSLog(@"lifetime 3: two animators over one view, releasing the first");
            one = nil;
            check(wakes(two, second, ^{ view.frame = CGRectMake(0, 0, 300, 600); }), @"(a) still wakes the second animator once the first is gone");
            two = nil;
            view.frame = CGRectMake(0, 0, 300, 700);
            NSLog(@"lifetime 3: both released, the view moved, releasing the view");
        }
        NSLog(@"lifetime 3: view released");
        // views built now may take the addresses the dead ones had: a leaked observation would reach them
        for (int index = 0; index < 400; index++) {
            @autoreleasepool {
                UIView *other = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
                other.frame = CGRectMake(1, 2, 30, 40);
                other.bounds = CGRectMake(0, 0, 50, 60);
            }
        }
        NSLog(@"400 new views moved, failures %d", failures);
    }
    return failures;
}
