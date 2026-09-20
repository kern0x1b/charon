# The members of views, controllers and controls that iOS 13 and 14 added

Source: the host's own UIKit under Mac Catalyst (macOS 27.0), run in a process of its own before the port is loaded, and held against
the backport by the `views13` group of `tests/backports/host/uikit2` (68 statements); `tests/backports/device/uirest.m`
for a device. Where the host answers as the Mac does the test says so.

## Views and controllers

- `UIView.transform3D` is the layer's `transform`, and follows `transform` as the host's does.
- `overrideUserInterfaceStyle` of a view and of a view controller is kept and read back, unspecified until set. iOS 6 has one
  appearance, the light one, so the override changes neither the traits nor what is drawn (a dark override is not applied, since
  the controls of the release cannot be drawn dark and a trait that says dark over a light screen would mislead more than help);
  the first dark override says so once in the log.
- `UIViewController.modalInPresentation` is kept, NO until set; a modal of iOS 6 has no swipe to dismiss for it to prevent, and the
  first YES says so. `performsActionsWhilePresentingModally` is YES unless the Info.plist sets
  `UIViewControllerPerformsActionsWhilePresentingModally`.
- `UIView.focusGroupIdentifier` is kept, nil until set; iOS 6 has no focus engine. (`UIViewController.focusGroupIdentifier` is iOS 15's
  and is decided in `registry/UIKit/ios15-16.json`.)
- `+[UIView modifyAnimationsWithRepeatCount:autoreverses:animations:]` runs the block after setting `setAnimationRepeatCount:` and
  `setAnimationRepeatAutoreverses:`. The release has no way to scope them to the animations inside the block, so those of the whole
  enclosing block repeat, and the first call says so once in the log. Only a device can show the animations, so `uirest.m` reads the
  layer's animation after the block.

## Controls

- `UIDatePicker.datePickerStyle` is always the wheels, the one style iOS 6 draws; `preferredDatePickerStyle` is kept, automatic until
  set. (The host answers compact or inline, the Mac's.)
- `UISwitch.style` is sliding and `preferredStyle` is kept, automatic until set. `title` is the checkbox style's of the Mac idiom, which
  raises on the host off that idiom; the port keeps it, the first non-empty title says so once in the log.
- `UIPageControl` keeps the indicator images by page, the preferred image, `allowsContinuousInteraction` (YES until set) and the
  background style; `interactionState` is always none. A page out of range raises `NSInternalInconsistencyException`, "Page (3) must be
  within 0 and 3." for a page control of three pages (the bound is the count). The release draws the dots itself, so the first image
  set says so once in the log.
- `UILabel.lineBreakStrategy` is 65535, the standard, until set and is kept; `UIScrollView.automaticallyAdjustsScrollIndicatorInsets` is
  YES until set and is kept; `UITextView.usesStandardTextScaling` NO; `UISplitViewController.primaryBackgroundStyle` none.
  Each says so once in the log when set to something else, since nothing of the release reads it.
- `UISegmentedControl.selectedSegmentTintColor` is kept; iOS 6 tints the whole control and not the selected segment alone.
- `UIPanGestureRecognizer.allowedScrollTypesMask` is kept, none until set, and says so once when set; no scroll event reaches the
  recogniser.
- `-[UISearchBar setShowsScopeBar:animated:]` sets `showsScopeBar`. `UIScreen.calibratedLatency` is 0.
- `UINavigationItem.backButtonDisplayMode` is kept; generic gives the item's `backButtonTitle` the localised "Back" and minimal the
  empty string, unless the title was set by the application, which the port then leaves alone; default puts back what it set.
- `+[UIVibrancyEffect effectForBlurEffect:style:]` is the effect of the blur, with the style kept and nothing drawn differently.
- `-[UIResponder validateCommand:]` does nothing and does not pass the command to the next responder, as the host does.
- `UIResponder.editingInteractionConfiguration` is the default.
- `UNNotificationResponse.targetScene` is the application's one scene, and `NSUserActivity.targetContentIdentifier` is kept.
- `-[UIImpactFeedbackGenerator impactOccurredWithIntensity:]` plays the impact's buzz with its strength multiplied by the intensity,
  clamped to 0 and 1; 0 plays nothing.
