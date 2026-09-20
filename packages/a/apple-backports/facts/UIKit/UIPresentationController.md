# UIPresentationController, iOS 8.0

Introduced in iOS 8.0: the object that owns a view controller's presentation - the container
view, the frame of the presented view, the adaptive style - and the class an application
subclasses for a custom presentation (`UIModalPresentationCustom` with a transitioning
delegate that answers a subclass).

Source: the host's own UIKit under Mac Catalyst, in an application with a window, asked for
each answer below and held against the backport by `tests/backports/host/presentation/run.sh`,
sixteen records that the app `tests/backports/device/presentation.m` compares on a device
running 6.1.3.

## The class

- The superclass is NSObject and the class adopts `UIContentContainer`.
- `-initWithPresentedViewController:presentingViewController:` keeps both; a nil presenting
  controller is accepted.
- The presentation style is the presented controller's `modalPresentationStyle`, whatever it
  is - 0 to 5, 7 and -1 all come back as they were set.
- `shouldPresentInFullscreen` is YES and `shouldRemovePresentersView` NO for every style, and
  both adaptive styles are `UIModalPresentationNone` (-1), for every style and every trait
  collection. A subclass overrides them.
- `containerView` is nil until a presentation has begun; `presentedView` is the presented
  controller's view; the frame of the presented view is empty without a container.
- `-sizeForChildContentContainer:withParentContainerSize:` answers the parent size.
- The delegate and `overrideTraitCollection` are plain properties, both nil at first.
- The six transition hooks do nothing, and a subclass that overrides them and calls `super`
  is called in the order it is asked.

## What the port answers, and what iOS 6 does with it

The release presents a view controller itself - a full screen, a page sheet or a form sheet -
and has no presentation controller. Nothing makes a `UIPresentationController`, shows one or
calls its hooks. An application that subclasses it for a custom presentation links and runs,
and the release presents that controller by its `modalPresentationStyle` as it always has:
`UIModalPresentationCustom` is not a style of the release, so the presentation is the full
screen one.

`-[UIViewController presentationController]` answers nil for every controller. UIKit answers
an object of its own for every style except custom and none; on this release there is none to
answer, and a message to nil - the usual `presentationController.delegate = self` - does
nothing.

Not carried: the focus and trait-change protocol methods beyond `traitCollectionDidChange:`,
`preferredContentSize` and the two size-change messages, none of which anything sends.
