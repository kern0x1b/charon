# The collection view layout transition

What iOS 7 gave a collection view that iOS 6.1.3 does not have: a way to move from one layout to
another under a progress the caller drives, instead of only swapping the layout outright.

## Why the port carries it

The release's `UICollectionView` lays out through `invalidateLayoutWithContext:`, which
`UICollectionViewLayout+Invalidation7.m` already supplies, but it has no transition at all: it
never builds a `UICollectionViewTransitionLayout`, never moves a progress, and never asks a layout
the transition questions. So on the release all of the following is unreachable however an
application writes it, which is the whole of this group:

- `-[UICollectionViewLayout targetContentOffsetForProposedContentOffset:]`
- `-[UICollectionViewLayout prepareForTransitionToLayout:]`, `prepareForTransitionFromLayout:`, `finalizeLayoutTransition`
- `-[UICollectionViewLayout indexPathsTo{Delete,Insert}For{SupplementaryView,DecorationView}OfKind:]`
- `-[UICollectionView startInteractiveTransitionToCollectionViewLayout:completion:]`, `finishInteractiveTransition`,
  `cancelInteractiveTransition`, `setCollectionViewLayout:animated:completion:`
- `UICollectionViewTransitionLayout` and its two animated-key messages

## What each answer is, and where it was measured

`tests/backports/host/collectiontransition` records what the host's own UIKit answers for every
case of `tests/backports/device/collectiontransition-cases.m` under Mac Catalyst (macOS 27.0) and
writes them where the device test reads them, so the port is held to the same answers. The cases
run with no collection view and no window, which is what makes them runnable on both sides.

Measured, and matched:

- `targetContentOffsetForProposedContentOffset:` gives back the offset it was given, `{11, 22}` and
  `{0, 0}`. A layout that wants to come to rest elsewhere overrides it.
- The two prepare messages and the finalize message are asked of the base layout and change
  nothing: they are the subclass's to answer, and on the host the base layout's answers leave the
  content size as it was.
- The four element questions name no element on the base layout: each answers an **empty array**,
  not nil, for a section header, a section footer and a decoration kind. A flow layout in a live
  collection view with no supplementary views registered answers empty as well.
- `UICollectionViewTransitionLayout` keeps the two layouts it was given, and its progress starts at 0.
- **The progress is not bounded.** The host holds 2 when 2 is set and -1 when -1 is set, and
  `finalizeLayoutTransition` leaves the progress where the caller left it. The port was written to
  clamp to 0...1 and to reset the progress on finalize; the host answers told it otherwise and it
  was changed to hold the number as given and to leave it alone. This is the one place where the
  differential changed the implementation.

## The driven transition, and what is not verified

`tests/backports/device/collectiontransition.m` drives the real thing: a live collection view in a
window, a transition to a second flow layout with a different item size, the cell's frame at the
start, half way and the end, `finishInteractiveTransition` settling on the layout it went to,
`cancelInteractiveTransition` settling back on the one it came from, and what each completion block
is handed.

**This part has not been run.** It needs hardware, not the host and not the emulator: the cases
that need a window cannot run in a plain Catalyst binary, and a UIKit app started by `xmake
emulate` never reaches `application:didFinishLaunchingWithOptions:` (the `emulate-port` skill), so
the frames the emulator draws are SpringBoard's. Until that test is green on a device the driven
half of this group is **device-unverified**: the hooks above are measured against the host, and the
progress, the settling and the completions are written to the 26.2 header but not yet seen running
on 6.1.3.

The progress is moved from a 60 Hz timer rather than from inside a `UIView` animation block,
because it is the layout that reads it: the release animates no layout property, so a block that
only set the number would leave every cell where it was. `UICollectionView+InteractiveMovement.m`
drives its movement the same way.

## The two completion blocks are not the same block

`UICollectionViewLayoutInteractiveTransitionCompletion` is `void (^)(BOOL completed, BOOL finished)`
in the header of SDK 26.2, so the interactive transition is handed two flags: a cancelled
transition hands a completion that did **not** complete, and both a completed and a cancelled one
hand a finished, because the animation did run to its end either way.
`setCollectionViewLayout:animated:completion:` takes a plain `void (^)(BOOL finished)` instead, and
is wrapped into the two-argument form when it is run as a transition. Getting this backwards
would hand the caller's block a garbage flag, which is why it is written down here.
