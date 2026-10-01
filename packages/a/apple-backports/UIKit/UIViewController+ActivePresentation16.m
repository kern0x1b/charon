#import "CharonCustomTransition.h"
#import <UIKit/UIKit.h>

// -[UIViewController activePresentationController], iOS 16.0.
//
// The header: "Gets the presentation controller managing this view controller. If the original
// presentation controller has adapted, this returns the adaptive presentation controller. If this
// view controller has not yet been presented, this property returns nil."
//
// The port keeps one presentation controller per presented view controller: charon_set_presentation_controller
// stores it when a presentation starts and CharonCustomTransition.h reads it back through
// charon_presentation_controller_of, which is what -presentationController answers. So the question
// this row asks is whether that controller is one that has begun managing its view controller, and
// -presentedViewController says so: it is the controller's own public property, set by the port's
// UIPresentationController when the presentation is made and cleared when it ends.

@implementation UIViewController (CharonActivePresentation16)

- (UIPresentationController *)activePresentationController
{
    UIPresentationController *current = charon_presentation_controller_of(self);
    return current.presentedViewController == self ? current : nil;
}

@end