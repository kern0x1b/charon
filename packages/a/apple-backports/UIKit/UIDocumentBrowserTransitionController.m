#import <Foundation/Foundation.h>
#import <UIKit/UIViewController.h>
#import <UIKit/UIViewControllerAnimatedTransitioning.h>

#import "UIDocumentBrowserTransitionController.h"

// The transition controller's own storage. A 6.1.3-era SDK has no document browser at all, so the
// class is the port's, and its two properties are what the header declares: the progress of the
// document being brought across, which may be nil when nothing is, and the view the transition
// animates to, held weakly as the header says, so a transition that outlives its target does not
// keep it alive.

@implementation UIDocumentBrowserTransitionController
{
@private
    NSProgress *_loadingProgress;
    __weak UIView *_targetView;
}

@synthesize loadingProgress = _loadingProgress;
@synthesize targetView = _targetView;

@end
