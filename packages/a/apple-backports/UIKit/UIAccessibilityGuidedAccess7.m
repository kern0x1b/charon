// The accessibility and Guided Access functions of iOS 7 (facts/UIKit/UIAccessibilityGuidedAccess7.md).
//
// One object carries one release: every symbol here is first exported by iOS 7.0, which is the
// first held release that has it, so a band from 7.0 on re-exports the release's own and a band
// below it keeps this one.

#import <UIKit/UIKit.h>

// The path's own elements, each point put through the view's own conversion to the window's
// coordinate system, which is what "screen coordinates" is for a view inside a window. CGPathApply
// reports every segment as a cubic, so a path built from a quad curve comes back as the same curve
// written as a cubic, and a straight segment stays straight.
typedef struct {
    UIBezierPath *converted;
    UIView *view;
} CharonScreenPath;

static void CharonScreenPathElement(void *info, const CGPathElement *element)
{
    CharonScreenPath *context = info;
    // A cubic carries three points and is the widest element, so three converted points cover all.
    CGPoint points[3];
    for (int index = 0; index < 3; index++)
        points[index] = [context->view convertPoint:element->points[index] toView:nil];
    switch (element->type) {
    case kCGPathElementMoveToPoint:
        [context->converted moveToPoint:points[0]];
        break;
    case kCGPathElementAddLineToPoint:
        [context->converted addLineToPoint:points[0]];
        break;
    case kCGPathElementAddQuadCurveToPoint:
        [context->converted addQuadCurveToPoint:points[1] controlPoint:points[0]];
        break;
    case kCGPathElementAddCurveToPoint:
        [context->converted addCurveToPoint:points[2] controlPoint1:points[0] controlPoint2:points[1]];
        break;
    case kCGPathElementCloseSubpath:
        [context->converted closePath];
        break;
    }
}

UIBezierPath *UIAccessibilityConvertPathToScreenCoordinates(UIBezierPath *path, UIView *view)
{
    // No window means no screen to convert to, and the release's own frame conversion
    // (UIKit+Constants7c.m) answers the frame it was given unchanged in that case; this answers
    // with the path it was given, for the same reason and the same way.
    if (!path || !view.window)
        return path;
    CharonScreenPath context = {[UIBezierPath bezierPath], view};
    CGPathApply(path.CGPath, &context, CharonScreenPathElement);
    return context.converted;
}

void UIAccessibilityRequestGuidedAccessSession(BOOL enable, void (^completionHandler)(BOOL didSucceed))
{
    if (!completionHandler)
        return;
    // A request to be locked into Single App Mode "will only succeed if the device is Supervised,
    // and the app's bundle identifier has been whitelisted using Mobile Device Management" (the
    // header of SDK 26.2, UIAccessibility.h:614). iOS 6 is neither supervised nor MDM-managed, and
    // it has no session to ask for, so the request cannot be granted and the handler is told so -
    // on the next turn of the main queue, because the release's own handler is not called from
    // inside the request and a caller that checks its own state must not see it already changed.
    dispatch_async(dispatch_get_main_queue(), ^{
        completionHandler(NO);
    });
}

UIGuidedAccessRestrictionState UIGuidedAccessRestrictionStateForIdentifier(NSString *restrictionIdentifier)
{
    // "The initial state of all Guided Access restrictions is UIGuidedAccessRestrictionStateAllow"
    // (the header of SDK 26.2, UIGuidedAccess.h:39). Nothing here is ever denied, because a
    // restriction is only ever denied by the system while the app is locked into Guided Access, and
    // iOS 6 has no way to be: the delegate that would list the identifiers is a method the release
    // never sends.
    return UIGuidedAccessRestrictionStateAllow;
}
