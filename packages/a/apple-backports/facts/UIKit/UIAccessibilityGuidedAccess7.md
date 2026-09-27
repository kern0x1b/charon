# Accessibility and Guided Access functions, iOS 7

`UIAccessibilityConvertPathToScreenCoordinates()`, `UIAccessibilityRequestGuidedAccessSession()`
and `UIGuidedAccessRestrictionStateForIdentifier()`, the three UIKit functions iOS 7 added
(`UIKit/UIAccessibilityGuidedAccess7.m`). Each of them is measured in the only way its release
allows: iOS 6.1.3's own cache does not export any of them, so there is no release of the port's
architecture to differ against, and the answers are the ones the SDK's own headers state for a
release that has none of the machinery.

## The path in screen coordinates

`UIAccessibilityConvertFrameToScreenCoordinates()` (iOS 7, `UIKit/UIKit+Constants7c.m`) turns a
rectangle in a view's own coordinates into the window's, and answers the rectangle it was given
unchanged when the view has no window. This is the same conversion for a path: every element of the
path is read with `CGPathApply` and each of its points is put through
`-[UIView convertPoint:toView:nil]`, which is the same call the frame version makes, and the result
is a new path built from those points. A view with no window answers with the path it was given, for
the same reason and in the same way as its frame sibling.

`CGPathApply` reports every segment of a path as a cubic, since that is the only curve `CGPath`
stores. A path built from a quad curve therefore comes back as the same curve written as a cubic,
and a straight segment stays a line: the shape is preserved, and only its description changes. A
path with a nil `CGPath` (an empty path) yields an empty path, as the input's shape does.

The 6.1.3 cache is where the absence is measured: neither `UIAccessibilityConvertPathToScreenCoordinates`
nor any other of the three appears in its symbol table.

## The Single App Mode session

`UIAccessibilityRequestGuidedAccessSession(enable, completionHandler)` asks for the application to
be locked into (or released from) Single App Mode. Its own header says what such a request needs
(SDK 26.2, `UIAccessibility.h:613-618`):

> The request to lock this app into Single App mode will only succeed if the device is Supervised,
> and the app's bundle identifier has been whitelisted using Mobile Device Management.

iOS 6.1.3 is not a supervised device and has no Mobile Device Management to whitelist a bundle
identifier with, so the request cannot be granted whatever `enable` is. The handler is therefore
called with `NO`, and it is called from the next turn of the main queue rather than from inside the
call, because the release's own handler is not called from inside the request either: an
application that checks its own state right after asking must not find it already changed. A nil
handler is not called.

## The state of a restriction

`UIGuidedAccessRestrictionStateForIdentifier(identifier)` answers
`UIGuidedAccessRestrictionStateAllow` for every identifier. Two things in the SDK's own header make
that the answer rather than a choice:

* `UIGuidedAccessRestrictionState` is a two-case enumeration, `Allow` and `Deny`, and the header
  states that "the initial state of all Guided Access restrictions is
  `UIGuidedAccessRestrictionStateAllow`" (SDK 26.2, `UIGuidedAccess.h:39`).
* A restriction is only ever *denied* by the system while the application is locked into Guided
  Access, and the identifiers themselves come from
  `-[UIGuidedAccessRestrictionDelegate guidedAccessRestrictionIdentifiers]`, a delegate method iOS 6
  never sends - there is no such delegate in the release and nothing asks one.

So a device that cannot be locked in reports `Allow` for every identifier, and so does an
application that is never asked for any.
