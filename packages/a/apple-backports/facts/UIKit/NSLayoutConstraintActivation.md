# Activating constraints, iOS 8

Source: the host's own UIKit, under Mac Catalyst, held against the backport by the activation records of
`tests/backports/host/layout/run.sh`, which run the same sequence on both and compare what each answers;
and iOS 6.0 and 6.1.3 on an iPhone 4S, an iPad 2 and in the emulator, through `tests/backports/device/layout.m`.

## Where a constraint is held

Activating a constraint installs it on the nearest view that is an ancestor of both its items, or of its
one item: a constraint on one view alone - a size - is held by that view, and a view without a superview holds
its own. A constraint between a view and one of its descendants is held by the ancestor. `isActive` is
true exactly while some view holds the constraint, so one added by hand with `addConstraint:` is active and
one taken away with `removeConstraint:` is not.

Activating an active constraint installs nothing more, in a list or on its own, and a constraint listed twice
is installed once. Deactivating one that is not active does nothing. A nil array of constraints does nothing
in either direction, and an element that is not a constraint raises for lack of a selector.

A constraint whose items share no ancestor raises `NSGenericException` and stays inactive. Called with a list,
the ones before the bad one stay activated and the ones after it are not reached. The text of the newest
system names the two anchors; the backport's names the two items, since a constraint made with
`constraintWithItem:` has no anchors.

A view that leaves its superview takes with it the constraints its ancestors held for it, and they do not
come back when it returns.

## Layout guides

A guide's constraints are held by the guide's owning view, or above it: a constraint between the guide and a
view by their common ancestor as for two views, and the guide's own size by the owning view.
A guide without an owner takes no constraint at all - activating one does not raise and leaves the constraint
inactive. Removing a guide from its view takes its constraints with it, and adding it back does not bring
them back.

In the backport a guide is a hidden view, and the activation asks that view which guide it is, so a guide's
size lands on its owner rather than on the hidden view.
