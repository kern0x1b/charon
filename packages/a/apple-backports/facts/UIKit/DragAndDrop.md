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

## The sessions, the proposals and the two interactions

**The gestures are the release's own**, which is what makes this a drag and not a swipe: a
`UILongPressGestureRecognizer` at half a second lifts what is under the touch and a
`UIPanGestureRecognizer` carries the picture that lift made, and letting go is the drop. The preview
is a still picture of a view — rendered from its layer, as the tree's own movement preview does — and
it is added to the application's own window and travels between the application's own windows.

There is **no drag that leaves the application** and none is faked: a session answers
`isRestrictedToDraggingApplication` YES, which is the answer a device of this era gives, and the
delegate is asked about it so the application sees the answer rather than having it assumed. A move is
allowed, because a move inside the application needs no service.

A drop is found by asking: the drag carries the list of drop interactions the application made, and
the one whose view is under the finger is asked `canHandleSession:`, then told `sessionDidEnter:` and
`sessionDidUpdate:` as the finger moves, and on letting go told `performDrop:`, `concludeDrop:` and
`sessionDidEnd:`. The drag's own delegate is told what the drag ended with, and a drag that was
called off ends as cancelled.

**The data is the item provider's.** `loadObjectsOfClass:completion:` loads through the provider that
carries it; nothing here copies a payload.

**A lift with no delegate says nothing is being dragged.** A view cannot go into an item provider on
this release — a provider writes objects that can be read back, and a view is not one — and guessing
a payload would move the wrong data, so the lift ends there rather than dragging something invented.

`UITargetedDragPreview` is given **no** way to make one: the header declares no initialiser, because
the system hands the preview to the delegate it asks. The port therefore constructs none, and adds
nothing to the `UITargetedPreview` the tree already carries beyond the retargeting the header does
declare. Three more entries another band held `absent` for the same soft reason as the previews have
moved to `implemented`.

## Not yet built in this family

The table and collection drag and drop delegates and coordinators (`UICollectionViewDragDelegate`,
`UICollectionViewDropDelegate`, `UITableViewDragDelegate`, `UITableViewDropDelegate`, the two drop
coordinators, the drop items, proposals with an intent and the placeholders). Two things in the tree
need correcting as part of it and are recorded here so they are not lost: `-[UICollectionView
hasActiveDrag]` and `-[UICollectionView hasActiveDrop]` answer a constant `NO` today, which is a
silent fake, and become real answers once there is a session to report.
