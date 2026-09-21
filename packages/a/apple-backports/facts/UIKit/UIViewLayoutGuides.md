# The layout guides of a view, iOS 9

Source: the host's own UIKit, asked directly, and the differential run of
`tests/backports/host/layout/run.sh`, which holds the backport to the system guide by guide.

A guide is a rectangle that takes part in layout without being a view. A new one owns nothing: its
`identifier` is the empty string, not nil, its `layoutFrame` is zero and its `owningView` is nil.

`-addLayoutGuide:` sets the guide's `owningView` and puts it in the view's `layoutGuides`. Adding the same
guide twice leaves one. Adding a guide another view owns **moves** it: it leaves the first view's
`layoutGuides` and the second becomes its owner. `-removeLayoutGuide:` clears the owner and takes it out
of the list, and removing a guide from a view that does not own it does nothing at all.

Two guides are the view's own and are made when they are first asked for, after which the view answers
the same object every time and lists it in `layoutGuides`:

- `layoutMarginsGuide`, identifier `UIViewLayoutMarginsGuide`, the bounds inset by `layoutMargins`. It
  follows the margins as they change: a child pinned to its four anchors moves when the margins are set.
- `readableContentGuide`, identifier `UIViewReadableContentGuide`, which narrows a wide view to a
  readable measure - 672 points, centred - and is the margins guide where the view is narrower.

The backport has no layer of its own to hang a guide on, so each guide is backed by a hidden view that
takes no touches: it is a subview of the owning view, `hidden` is YES, `userInteractionEnabled` is NO,
and hit testing never answers it. `layoutFrame` reports that view's rectangle in the owner's coordinates,
which is what the system reports for a guide. A guide's identifier survives archiving.

The release's own Auto Layout asks the items of a constraint questions that a guide has to answer: `_UIViewConstraintWithItemsIsPotentiallyDangly`
sends `-superview` to each item, and the constraint code asks `_supportsContentDimensionVariables`, tells the item `_rememberDependentConstraint:`
and `_setWantsAutolayout`. A guide answers as the view it stands for: its `-superview` is the owning view (nil for a guide with no owner), it has
no content dimension variables, it keeps the constraints that depend on it weakly, and `_setWantsAutolayout` goes to the owning view. The
constraint classes of the port already put the backing view in place of a guide where they can; this is for the ones that reach the release with
the guide itself, as an application recompiled from another architecture makes them. `device/layoutguide.m` asks the four on the iPhone 4S and
the iPad 2 and solves a constraint on a guide.
