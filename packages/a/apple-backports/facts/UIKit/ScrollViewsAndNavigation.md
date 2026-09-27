# The navigation bar on a gesture, and the two scroll views

## The bar hiding on a swipe or a tap (iOS 8)

The release's navigation controller has no such gesture: the bar is there until a push or a pop
changes it. The port adds the two gestures the header names, and the four flags that say which of
them hides the bar.

**Every default here was measured, and three of them were not what I expected:**

- `hidesBarsOnSwipe`, `hidesBarsOnTap`, `hidesBarsWhenKeyboardAppears` and
  `hidesBarsWhenVerticallyCompact` are all **NO** in a navigation stack made by hand. The natural
  assumption is that iOS 8 turned the swipe on by default, and it is not: the host answers `no` for
  all four (`tests/backports/host/uikitscroll`, the `nav.*Default` cases). A port that guessed YES
  would hide the bar on every stack in every application, which is the kind of quiet wrong answer
  this project exists to not give.
- `barHideOnSwipeGestureRecognizer` is **not** the interactive pop. Asking the host for
  `barHideOnSwipeGestureRecognizer` and for `interactivePopGestureRecognizer` gives two different
  recognisers (`nav.swipeIsThePopGesture` records `different`). My first attempt reused the pop
  gesture on the reasoning that one finger at the edge should not drive two things; the host has two
  recognisers and so does this, each deciding for itself.
- The two recognisers are **private classes on the host** — `_UIBarPanGestureRecognizer` and
  `_UIBarTapGestureRecognizer` — which this port may not name. It uses the public
  `UIScreenEdgePanGestureRecognizer` and `UITapGestureRecognizer` and behaves the same. That is the
  one place this family's answers differ from the host's, and it is recorded as the two cases
  `nav.swipeGestureKind.diverges` and `nav.tapGestureKind.diverges`, which assert the port's own
  kinds: they fail if the host ever stops diverging, and they fail if the port ever starts naming a
  private class.

**The trait path is the real one.** `hidesBarsWhenVerticallyCompact` reads
`traitCollection.verticalSizeClass` and is re-applied by wrapping the release's own
`-traitCollectionDidChange:`, keeping the original implementation and calling it — the same way
`UINavigationController+InteractivePop.m` wraps `-viewDidLoad`. My first attempt drove it from
`UIContentSizeCategoryDidChangeNotification`, which is a different event: a vertical size class
change arrives through the trait collection and the layout pass, and that draft was thrown away for
it.

The keyboard is observed with `addObserver:selector:name:object:` and unobserved with the matching
`removeObserver:`, the way `UISheetPresentationController.m` does it, so turning the flag off really
stops the bar moving and the observer does not hold the controller. The first attempt used blocks
that were never removed and captured the controller strongly.

## What this family still owes, measured

The two scroll views and their layouts and this navigation controller are **52 rows** after groups
1–3, of which **~38 are implementable**. Seven are the focus engine and are family 3 by the
coordinator's ruling; five belong to iOS 11 drag and drop; two are the protocol-measurement artefact
the ledger has when it never inspects a protocol. The rest, not yet built and measured for here:

- `UITableView`: `separatorInset` (**default {0, 16, 0, 0}**, not zero), `sectionIndexBackgroundColor`
  (default nil), `separatorEffect` (default nil), `cellLayoutMarginsFollowReadableWidth` (default no);
- `UITableViewCell.separatorInset` (**default {0, 8, 0, 8}**);
- `UICollectionViewLayoutAttributes.bounds` — a real property beside `frame`, and the host answers
  that setting `frame` leaves the bounds' **origin** at zero and changes only its size;
- `UICollectionViewFlowLayout.sectionHeadersPinToVisibleBounds` and `sectionFootersPinToVisibleBounds`,
  both default **no**;
- `UICollectionViewController`: `collectionViewLayout`, `useLayoutToLayoutNavigationTransitions`
  (default no), `installsStandardGestureForInteractiveMovement` (default **yes**);
- the delegate questions `UICollectionViewDelegate` and `UITableViewDelegate` that the port must
  call: `willDisplayCell:forItemAtIndexPath:`, `willDisplaySupplementaryView:forElementKind:atIndexPath:`,
  `targetContentOffsetForProposedContentOffset:`, and the three estimated-height questions;
- `UINavigationControllerDelegate`'s two orientation questions, whose defaults with no delegate are
  neither portrait nor all, as the host answers.

All of these are recorded in `tests/backports/device/uikitscroll-expectations.h` and are measured;
none of them is guessed.
