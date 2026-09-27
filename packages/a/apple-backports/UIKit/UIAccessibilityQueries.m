#import <UIKit/UIKit.h>
#import <CoreGraphics/CGPath.h>

// The five C functions UIKit exports that ask the running system about assistive technology and
// guided access. Each names a state of the system that iOS 6.1.3 keeps where an application cannot
// read it, so each answers as a device in the state that has none of it, and says so. What was
// measured about the release, and what the host answers, is in
// facts/UIKit/AccessibilityQueries.md.

// The path as the assistive technology sees it: the same chain as
// UIAccessibilityConvertFrameToScreenCoordinates in UIKit+Constants7c.m, which converts a rect
// through the view's own window and then through the window's screen space, done for a path by
// composing the two transforms. The transform from one view to another is read off three converted
// points rather than assumed to be a scale and a shift, so a rotated or flipped view in the
// hierarchy is converted as it really is.
static CGAffineTransform CharonTransform(UIView *from, UIView *to)
{
    CGPoint origin = [from convertPoint:CGPointZero toView:to];
    CGPoint alongX = [from convertPoint:CGPointMake(1, 0) toView:to];
    CGPoint alongY = [from convertPoint:CGPointMake(0, 1) toView:to];
    return CGAffineTransformMake(alongX.x - origin.x, alongX.y - origin.y,
                                 alongY.x - origin.x, alongY.y - origin.y,
                                 origin.x, origin.y);
}

static CGAffineTransform CharonWindowToScreen(UIWindow *window)
{
    // The window's own space into the screen's, which is what -convertRect:toWindow:nil means.
    CGPoint origin = [window convertPoint:CGPointZero toView:nil];
    CGPoint alongX = [window convertPoint:CGPointMake(1, 0) toView:nil];
    CGPoint alongY = [window convertPoint:CGPointMake(0, 1) toView:nil];
    return CGAffineTransformMake(alongX.x - origin.x, alongX.y - origin.y,
                                 alongY.x - origin.x, alongY.y - origin.y,
                                 origin.x, origin.y);
}

UIBezierPath *UIAccessibilityConvertPathToScreenCoordinates(UIBezierPath *path, UIView *view)
{
    if (!path || !view)
        return nil;
    UIWindow *window = view.window;
    if (!window)
        return path;
    CGAffineTransform toScreen = CGAffineTransformConcat(CharonWindowToScreen(window), CharonTransform(view, window));
    // iOS has no -bezierPathByApplyingTransform:, so the transform is applied to the path's CGPath
    // with CGPathCreateMutableCopyByTransformingPath and the result is read back into a UIBezierPath,
    // which is the only way to transform one here.
    CGMutablePathRef moved = CGPathCreateMutableCopyByTransformingPath(path.CGPath, &toScreen);
    if (!moved)
        return path;
    UIBezierPath *result = [UIBezierPath bezierPathWithCGPath:moved];
    CGPathRelease(moved);
    return result;
}

BOOL UIAccessibilityIsAssistiveTouchRunning(void)
{
    // Whether AssistiveTouch is on. Measured on the release's own cache: the only AssistiveTouch
    // names iOS 6.1.3 carries are AssistiveTouchCustomGestureCreation and AssistiveTouchPID,
    // neither of which is a state, and it exposes no notification the state changes through, so
    // there is nothing on this release to read and the answer is the one a device with AssistiveTouch
    // off gives. An application that needs to know can watch the running state itself.
    return NO;
}

UIAccessibilityHearingDeviceEar UIAccessibilityHearingDevicePairedEar(void)
{
    // The ear a paired hearing device sits in. This device has no paired hearing device, so there is
    // no ear, which is the answer the release documents for no device.
    return UIAccessibilityHearingDeviceEarNone;
}

void UIAccessibilityRequestGuidedAccessSession(BOOL enable, void (^handler)(BOOL success))
{
    // A guided access session is a state the system puts the whole device into, and only the
    // system's own guided access starts one; an application asking is answered as an application
    // that did not get one. The handler is called, so a caller waiting on one is not left waiting.
    if (handler)
        handler(NO);
}

UIGuidedAccessRestrictionState UIGuidedAccessRestrictionStateForIdentifier(NSString *identifier)
{
    // Whether one named restriction allows what it guards. The release keeps its restrictions where
    // an application cannot read them and exposes no query for one, so the answer is that the
    // restriction allows, which is the header's own initial state for every restriction and what a
    // device outside guided access answers.
    (void)identifier;
    return UIGuidedAccessRestrictionStateAllow;
}
