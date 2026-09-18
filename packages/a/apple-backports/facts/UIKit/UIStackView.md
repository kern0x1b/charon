# UIStackView, how its distributions are constrained

Source: UIKit of iOS 9.3.5, armv7, read with `xmake firmware extract`; the work is in
`_UIOrderedLayoutArrangement`, whose `-_setUpDimensionConstraintForItem:referenceItem:atIndex:`
(0x256c5899) builds the constraint that gives an item its length. The host's own UIStackView answers
the differential run of `tests/backports/host/layout/run.sh`, which the backport matches on all 12000
frames it compares.

## The priorities of a dimension constraint

The priority is not one of the named levels and is not the same for every item: it falls with the item's
index, and it has a floor.

| distribution | priority of the item at index i |
|---|---|
| fill equally, first item or a single item | 1000, required |
| fill equally | max(999 - i, 751) |
| fill proportionally | max(150 - i, 50) |

So a proportional stack asks for its proportions *below* the content hugging of 250 and far below the
compression resistance of 750, while an equal stack asks just under required and never falls below 751.
The identifiers UIKit gives the two are `UISV-fill-proportionally` and `UISV-fill-equally`, which is what
the backport names them as well. The proportional constraint ties an item to the reference item the
method is handed, with a multiplier of their proportional lengths, rather than to the stack.

## The constraints around them

`-[_UILayoutArrangement _updateCanvasConnectionConstraintsIfNecessary]` (0x2561d1ed) makes two kinds.
`UISV-canvas-connection` ties the ends of the arrangement to the canvas, with the relation
`_layoutRelationForCanvasConnectionForAttribute:` gives, which in the base class is equality and which only
the aligned arrangement overrides - so a stack's connections are equalities, as the backport's are.
`UISV-canvas-fit` is the other: the canvas's own length equal to zero, at priority **49**, one below the
floor of the proportional priorities, added for exactly the two distributions
`_configurationRequiresCanvasConnectionFittingConstraint` (0x256c6af1) names, fill equally and fill
proportionally. It is what makes a stack hug its content while the proportions ask from below.

`-_setUpHidingDimensionConstraintForItem:` (0x256c5c65) is the third: the item's length equal to zero,
required, named `UISV-hiding`.

`-_constantForMultilineTextWidthDisambiguationConstraintWithNumberOfVisibleItems:` (0x256c5d29) answers
`-spacing * (n - 1) / n` for n visible items, and zero for none: the nudge that keeps the width of
multiline text from being read two ways.

The backport instead ties each item to the stack with the multiplier of its share and asks at 999 - i.
On the host's solver the two agree on every frame the differential compares; on iOS 6 they do not, and
the frames of a proportional stack are the known difference. Carrying Apple's parts across one at a time is worse than
either: the priorities alone, on the backport's own topology, take the emulated iOS 6 from 7 failed frames
to 10; the reference item and the priorities together, with and without the canvas fit at 49, and with the
reference taken as the first item or as the one before, all fail the same 72 frames of the host run, where
the system keeps a height of one or two points and the backport collapses it to none. What holds those
heights up is the part still to read: the spanning guide the ordered arrangement runs its chain through,
and the gap constraints along it.

The length a proportional item is measured by is settled:
`-[UIView _proportionalFillLengthForOrderedArrangement:relevantParentAxis:]` (0x2545ea85) takes the
intrinsic content size along the axis, and falls back to `systemLayoutSizeFittingSize:` when that is
`UIViewNoIntrinsicMetric` or the view asks for a second constraints pass - which is what the backport's own
measure already does.
