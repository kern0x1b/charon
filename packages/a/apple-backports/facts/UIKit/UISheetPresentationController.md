# UISheetPresentationController, iOS 15.0 and 16.0

Introduced in iOS 15.0: the presentation controller of a page or form sheet in a compact width - the card that
slides up over the presenter to one of its detents, with a grabber, a drag that moves it between detents or takes it
down, and a presenter that scales back behind it. iOS 16.0 added custom detents, their identifiers, the resolution
context, `UISheetPresentationControllerDetentInactive` and `-invalidateDetents` (`UISheetPresentationController16.m`).

Sources:
- UIKitCore of the held 16.0 cache (arm64e), read statically for the geometry, the detents, the dimming, the drag and
  its end, the stack of sheets and the corners; the 18.0 cache where it confirms or corrects a value. The addresses are
  below and, for each value, beside it in the code.
- The host's own UIKit under Mac Catalyst for what the API answers - defaults, descriptions, equality, the resolution of
  detents for eleven containers, which styles have a sheet: `tests/backports/host/sheet/run.sh` writes 42 records into
  `tests/backports/device/sheet-expectations.h`, which `tests/backports/device/sheet.m` holds the port to on iOS 6. The
  host shows a sheet in a bridged window of its own (581 x 641), so it is no oracle for layout, and its idiom is the pad,
  so it is none for the grabber (60 x 4 there, 36 x 5 on the phone).

## What has an oracle besides the read

- The API (defaults, descriptions, equality, which styles have a sheet) and the resolution of the medium and large
  detents for eleven containers (0.63 of the maximum up to a height of 568, 0.56 above): the host's UIKit, recorded by
  `tests/backports/host/sheet/run.sh`.
- The metrics the port takes as constants - topOffset 10, 8 in a compact height, the maximum depth 2, the transition
  duration 0.4, the spring's response 0.3441442326 and damping 1 and 0.8: the host's `_UISheetPresentationMetrics`
  agrees, `tests/backports/host/sheetmetrics/run.sh`, which reads them from the port's source. Its corner radius is 8,
  of the design after iOS 26; 16.0 answers 10, and the test fails if the host stops differing.
- Nothing else. The host (Mac Catalyst of macOS 27) shows a sheet in a bridged window of its own (581 x 641) in the pad
  idiom, and has no `_UISheetLayoutInfo` class to drive with a phone-sized container (measured: `NSClassFromString`
  answers nil). What rests on the read of the 16.0 cache alone: the margins and the frame, the presenter's scale and
  lift and the stack of sheets, the corner radii and their blending, the dimming fractions, the shadow's opacity, the
  grabber's size and spacing (the host's pad grabber is 60 x 4), the drag's rubber band and projection, the keyboard
  detent and the grabber's tap.

## The API

- `mediumDetent` and `largeDetent` make a new object each call; detents of one type are equal and hash as NSObject does;
  a custom detent equals only itself. Descriptions carry `_type=medium|large|custom` and the identifier.
- Identifiers: `com.apple.UIKit.medium`, `com.apple.UIKit.large`; a custom detent without one gets a fresh UUID string.
- `UISheetPresentationControllerAutomaticDimension` and `UISheetPresentationControllerDetentInactive` are the largest
  CGFloat, as the release's are.
- Defaults: detents `[large]`, no selected identifier, no largest undimmed identifier, no grabber, the automatic corner
  radius, scrolling that expands to a larger detent at the edge, not edge-attached in a compact height, the width not
  following the preferred size, no source view and no delegate.
- `UIViewController.sheetPresentationController` answers the sheet for a page or form sheet (Automatic resolves to the
  page sheet, `UIModalPresentationAutomatic.md`), made when it or `presentationController` is first asked, and the same
  object after; nil for every other style.
- The delegate hears `sheetPresentationControllerDidChangeSelectedDetentIdentifier:` when a drag or a tap on the dimming
  view settles on another detent (not when the program sets the identifier), and the four
  `UIAdaptivePresentationControllerDelegate` dismissal members below.

## Geometry (iPhone portrait, 16.0)

- Margins (C function 0x1890cab64): the safe area plus 2 x topOffset = 20 on top and bottom; 8 in a compact height.
  UIKit gives 20 to a phone with a home button (`-[UIDevice _hasHomeButton]`) and 10 to one without; every device iOS 6
  runs on (iPhone 3GS, 4, 4S, 5, iPod touch 4 and 5, every iPad) has a home button, so the port uses 20 throughout.
- Frame (`_stackAlignmentFrame` 0x189051544): centred, the container's width, from the top margin to the container's
  bottom edge. iPhone 4S with the status bar: top 40, the sheet 320 x 440.
- Detents: large = the full height less the bottom safe inset (`maximumDetentValue` 0x1895e9958); medium = that times
  0.56 when the container is taller than 568 points, 0.63 otherwise, and inactive in a compact height (block 0x189d322b4,
  table 0x18a07a460; the 18.0 cache agrees). 4S: large 440, medium 277.2 (y 202.8).
- The presenter scales back while a sheet above it rises from its next detent to its full height (`_transform`
  0x1895e88b0): scale s = 1 - 2m/width with the content margin m = 16 at width 320 (0x188f67350: 16 up to 393, 20 above),
  lifted to stand topOffset (10) above the sheet's top. 4S, one sheet at large: the root at 16 30 288 414 behind it; at
  medium it is not scaled. A second sheet stacks the same way: the first at 16 30 288 396, the root at 16 40 288 414.
  These layout values are worked out from the read; `tests/backports/device/sheet.m` on an iPad 2 (6.1.3, the
  application phone-sized) gave every one of them, 2026-09-24, which shows the port computes what the read says, not
  that the read is the release.
- Corners (`_cornerRadii` 0x188f930e8): 10 on top; the bottom of a full-width sheet at depth 0 matches the display's
  corner, and a card behind a child blends towards the child's radius. The root card's corners run 0 to 10 as its child
  rises from medium to large.
- Grabber: 36 x 5, corner radius 2.5, `tertiaryLabelColor`, its top 5 points into the sheet (`_grabberSpacing` 5 in
  `initWithMetrics:` 0x1895e8da0; the 18.0 cache agrees). It fades as a child sheet above reaches its dimming detent.
- Dimming (`_percentDimmedFromOffset` 0x188f93878, `_percentDimmed` 0x188f936bc): the smallest detent dims unless
  `largestUndimmedDetentIdentifier` names one; over a parent that stacks, the dimming is confined to the parent's card at
  0.6 of the fraction, plus 0.2 of a grandchild's. Colour: black at 0.2 (0.48 dark; `_alertControllerDimmingViewColor`).
  At or below the largest undimmed detent the dimming view takes no touch and touches reach the presenter
  (`UITransitionView`'s ignoreDirectTouchEvents; the port's container answers `charon_containerIgnoresDirectTouches`).
- Keyboard (`-[_UISheetLayoutInfo _activeDetents]` 0x1895ea0e0, `-_handleKeyboardNotification:aboutToHide:`
  0x18938274c): the sheet hears the keyboard's will-show, will-hide and will-change-frame notifications (UIKit's private
  ones; the release posts the public ones with the same frame, duration and curve; a frame change counts only while the
  keyboard is shown). It keeps the keyboard's end frame in the container (CGRectNull once it hides) and whether the
  window's first responder needs the keyboard (UIKit's private `-_requiresKeyboardWhenFirstResponder`; the port asks
  whether it adopts `UIKeyInput`). While a first responder in the sheet needs the keyboard and the keyboard meets the
  sheet's full-height frame, the sheet stands at its first detent: when that is below the large detent a detent with no
  identifier is put first, the first detent raised by the height of the keyboard over the full-height frame and no
  higher than the large detent, and the dimming detent moves down one. The selection stays; the sheet moves in an
  animation of the keyboard's duration with its curve as the options (block 0x189323d7c), and goes back to the selected
  detent when the keyboard hides.
- Grabber tap (`-[UIDropShadowView _grabberPrimaryAction]` 0x189e9113c, `-_dropShadowViewGrabberDidTriggerPrimaryAction:`
  0x189d33e74, `-[_UISheetLayoutInfo _grabberAction]` 0x1895ea700): the grabber is a control that acts on a touch up
  inside (0x1896b7964) and takes touches in 44 x 44 points around itself (touch insets, 0x188e8c3e4). While the keyboard
  holds the sheet the presented view ends editing; otherwise the detent before the current one, the last after the
  first (`-_indexOfActiveDetentForTappingGrabber` 0x1895ea69c: (n + current - 1) mod n), is selected in an animation and
  the delegate hears `sheetPresentationControllerDidChangeSelectedDetentIdentifier:`; with one detent the sheet is
  dismissed if it may be, as by a tap on the dimming view.
- Shadow: black at the dimming alpha, radius 2, zero offset, opacity 0.5 x (1 - dimmed) x presented (0x188f94848). Its shape
  is the card's: UIDropShadowView sets `shadowPathIsBounds` (0x189100748), so the shadow follows its bounds with the
  corners of its layer (`-updateCornerClippingViews` 0x18918964c); the port gives the layer the path it masks the card with.

## The drag (16.0)

- Rubber band: UIScrollView's curve d (1 - 1 / (x c / d + 1)) with c = 0.55; above the largest detent d = the gap to the
  safe area's top, at most 100 (20 on a 4S), below the smallest a quarter of the full height, at most 200.
- End (block 0x189069f70 of `draggingEndedInSource:`): the release is projected with the deceleration rate 0.99; the
  detent nearest the projection wins; a flick of 1000 points a second or more that lands back on the detent nearest the
  finger moves one detent further its way; below 250 points a second the velocity counts as none. The spring's damping
  is 1, or 0.8 for a flick, with a response of 0.3441 seconds (the host's metrics).
- Dismissal: when the drag passes the smallest detent the sheet asks whether it may dismiss - not while the controller
  presents another, not when it is `modalInPresentation`, else `presentationControllerShouldDismiss:`. If it may, the
  dismissal starts (`presentationControllerWillDismiss:`) and the drag carries it; let go above the smallest detent, it is
  taken back and the controller stays presented. If it may not, the sheet rubber-bands and, once pulled a quarter of that
  extent, tells the delegate `presentationControllerDidAttemptToDismiss:`, once per drag. `presentationControllerDidDismiss:`
  follows a dismissal by drag or tap once the release has taken the controller down.
- A tap on the dimming view (0x189d33ffc) dismisses when the sheet may be dismissed, otherwise moves to the largest
  undimmed detent if one is set; it tells nothing of an attempt.
- A pan that starts in a scroll view moves the sheet only when the scroll view is at its top edge, has no refresh control,
  does not scroll sideways, is not dismissing the keyboard interactively around the first responder, and the pan is not
  a quick repeat (0.4 s) of the last (0x18906b1b8). Which way the drag then goes is the documented rule
  (`prefersScrollingExpandsWhenScrolledToEdge`); that part of the release was not read.
- On an iPad 2 (6.1.3), the application phone-sized and the drags posted by `revtouch` from a probe outside the tree,
  2026-09-24: a slow drag from the large detent let go near the medium one settled at 202.8 with
  `sheetPresentationControllerDidChangeSelectedDetentIdentifier:`; a drag below the medium detent took the sheet down
  with `presentationControllerShouldDismiss:`, `WillDismiss:` and `DidDismiss:` in that order, and the release no longer
  counted the controller as presented; a `modalInPresentation` sheet dragged as far rubber-banded, sent
  `presentationControllerDidAttemptToDismiss:` once and settled at the medium detent. The flick and its spring were not
  measured there.
- The port's presentation calls the release's own dismissal after `dismissalTransitionDidEnd:`, as UIKit tells the
  presentation controller before the controller is gone, and UIKit 6.1.3 ends that dismissal only while the presented
  controller's view is in the window: taken out before, the presenter kept `presentedViewController` and the controller
  stayed `isBeingDismissed` (measured on the iPad 2, with the view put back as the control). The sheet leaves its card
  and that view in the container, which goes after the release's dismissal.

## Where the port differs

- The display's corner radius is 0: the displays of iOS 6 devices have square corners.
- The root presenter: UIKit's root presentation is a full-screen sheet over the whole window; the port uses where the
  release puts the root view, under the status bar (0 20 320 460), which gives the same visible top (30) when it scales
  back. Derived from the read; the iPad 2 gave the root at 16 30 288 414 behind a large sheet.
- The status bar's appearance is not changed while a sheet is up.
- In landscape the container is not rotated, a limitation of the port's presentation (`charon_presentation_run`)
  already.
- The "magic" shadow is not drawn. UIKit draws it under a sheet whose parent does not stack with it (presented from a
  full-screen or a custom presentation, or floating), at `_magicShadowOpacity` (the sheet's dimming fraction there, 0
  whenever the parent stacks, which is every phone sheet over the root or over another sheet): a `_UIRoundedRectShadowView`
  150 points beyond the card, the kit image `_UIPopoverShadow` (a 200 x 200 corner drawn four times into 400 x 400,
  stretched with cap insets 199.5; `-_loadImageIfNecessary` 0x188efd9d0) under `kCAFilterVibrantColorMatrix` with the
  lower-intensity matrix (`-_updateShadowVisualStyling` 0x189229340). `tests/backports/host/sheetshadow/run.sh` measured
  on the host that this filter takes its colour from what lies behind the layer, the matrix of the destination laid over
  it, not from the layer's black: its whole colour is a function of the destination, which iOS 6 cannot composite (no
  such filter, no backdrop layer). Listed in the workspace's `coordination/crutches.md`.
- `presentationController` of a controller with a page or form sheet style answers the sheet; for other styles the port
  answers the controller a transitioning delegate gave, or nil, where UIKit has its own full-screen controller.
