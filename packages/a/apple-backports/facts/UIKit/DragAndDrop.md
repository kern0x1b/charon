# Drag and drop

The coordinator's ruling (2026-09-27): a drag is software. The sessions, the items, the previews, the
proposals and the interaction's gestures all live in the process and are fully implementable on this
release. Where a drag would leave the application, the answer is what Apple documents for an iPhone of
this era: cross-app drag is not offered.

## What the release cannot do, and what that means for one API

A drag on a real device is begun, carried and ended by a system service, and that service is what
lets a drag leave the application. This release has no such service, so:

- **inside the application a drag is real.** A long press lifts, a pan carries a preview across the
  application's own windows, a drop asks the delegate and the item provider's data moves. All of that
  is in this process and none of it needs the missing service.
- **a drag that would leave the application is not offered.** Where a session is asked what it may do,
  or where the drop is asked to accept something from outside, the answer is the one a device of this
  era gives, and it is recorded at each such seam rather than left to look like a working cross-app
  drag.

Four entries another band registered `absent` with the reason "a drag is begun, carried between
applications and ended by a system service this release does not have" are now `implemented`: that
reason is true of the part that leaves the application and false of everything in it, which is the
whole of these value objects. Their entries have moved from `registry/UIKit/ios11.json` to
`registry/UIKit/dragdrop.json`.

## The previews duplicate nothing

`UIDragPreviewParameters` is a subclass of `UIPreviewParameters` and `UIDragPreviewTarget` of
`UIPreviewTarget`, both of which the tree already carries for the peek and pop preview — down to the
precondition `UIPreviewTarget` raises on when its container is not in a window. `UITargetedDragPreview`
is a `UITargetedPreview`, likewise carried, including its own retargeting. So these are the drag's own
names for objects that already exist here, and this family adds nothing to them; the header's
subclassing says exactly that, and the only thing the drag adds is its own types on top.

A `UIDragPreview` is a still picture: it neither moves nor changes the view it was made from, which is
what the header says, so nothing here takes a snapshot eagerly and the view is left alone.

## Not yet built in this family

The sessions and proposals (`UIDragSession`, `UIDropSession`, `UIDropProposal`), the interactions
(`UIDragInteraction`, `UIDropInteraction`), the table and collection drag and drop delegates and
coordinators, and the placeholders. Two things in the tree need correcting as part of it and are
recorded here so they are not lost: `-[UICollectionView hasActiveDrag]` and `-[UICollectionView
hasActiveDrop]` answer a constant `NO` today, which is a silent fake, and become real answers once
there is a session to report.
