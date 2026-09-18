# UIStackView, how its distributions are constrained

Source: the host's own UIKit, whose constraints are read from `stack.constraints` after a layout pass, and
UIKit of iOS 9.3.5, armv7, read with `xmake firmware extract`. The two do not agree, and the sections below
say which is which: the release we are held to is the newer one, and the backport matches it on all 12000
frames the differential run of `tests/backports/host/layout/run.sh` compares.

## What iOS 9.3.5 did: the priorities of a dimension constraint

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

## What iOS 9.3.5 did: the constraints around them

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

## What the release we are held to does, which is not that

The constraints a stack holds can be read from the stack itself, without a disassembler:
`stack.constraints` after a layout pass names them. On the host's own UIKit, a proportional stack of four
items, one of them without a length of its own, carries

    UISV-fill-proportionally  item1 == stack  multiplier 0.0988  priority 999
    UISV-fill-proportionally  item2 == stack  multiplier 0.5926  priority 998
    UISV-fill-proportionally  item3 == stack  multiplier 0.1975  priority 997
    UISV-fill-proportionally  item4 == 0                         priority 1000

and an equal one carries `item == firstItem` at required for each item after the first. There is no
reference item, no canvas fit, and the priorities count down from 999 by the item's index - which is the
backport's own recipe, to the constraint. The differential run agrees: all 12000 frames match.

So UIKit changed this between iOS 9 and now, and what the disassembly of 9.3.5 says above is that release's
answer, not today's. The rule is that the newest implementation is the source of truth, so the backport
keeps what the newest does, and the frames iOS 6 still gets differently are the old solver's doing, not a
recipe we read wrongly. Carrying the 9.3.5 recipe across was measured three ways and made both the host and
the emulated iOS 6 worse.

The backport ties each item to the stack with the multiplier of its share and asks at 999 - i.
On the host's solver the two agree on every frame the differential compares; on iOS 6 they do not, and
the frames of a proportional stack are the known difference. Carrying Apple's parts across one at a time is worse than
either: the priorities alone, on the backport's own topology, take the emulated iOS 6 from 7 failed frames
to 10; the reference item and the priorities together, with and without the canvas fit at 49, with the
reference taken as the first item or as the one before, and with or without the zero constraint on an item
of no length, all fail the same 72 frames of the host run. They fail because that is a release older than
the one we are held to, as the next section shows.

The length a proportional item is measured by is settled:
`-[UIView _proportionalFillLengthForOrderedArrangement:relevantParentAxis:]` (0x2545ea85) takes the
intrinsic content size along the axis, and falls back to `systemLayoutSizeFittingSize:` when that is
`UIViewNoIntrinsicMetric` or the view asks for a second constraints pass - which is what the backport's own
measure already does.

## The spacing after one arranged subview (iOS 11)

Source: Foundation and UIKit of iOS 11.0 arm64, read by the session that carries iOS 11 and 12, and the
host's own UIKit measured beside it; the numbers below are the system's answers, which the differential run
of `tests/backports/host/stackspacing/run.sh` holds the backport to.

`-setCustomSpacing:afterView:` and `-customSpacingAfterView:` are a table on the arrangement, keyed by the
preceding view itself - by the identity of the pointer, not by `isEqual:` - holding a number. A view that is
not an arranged subview is ignored by the setter and answers the default from the getter. Leaving
`arrangedSubviews` clears a view's spacing; being moved within them keeps it.

A gap takes the spacing of the **preceding visible** view, so hiding a view hands the gap to the one before
it. The value replaces the stack's `spacing` for that gap and is never added to it:
`UIStackViewSpacingUseDefault`, which is `FLT_MAX`, means the table says nothing and the stack's own
`spacing` decides; a `spacing` that is itself the default means zero. Both constants are `static const` in
the SDK's header, so nothing of them is carried - a caller compiles the value in - and the backport only has
to read them as UIKit does.

`UIStackViewSpacingUseSystem`, which is `FLT_MIN`, is not a number at all: UIKit builds a constraint between
the two views' anchors with `constraintEqualToSystemSpacingAfterAnchor:multiplier:` (or `...BelowAnchor:`,
or the baseline anchors of a baseline relative arrangement), where the backport uses the system spacing
anchors of iOS 11 it already carries. The multiplier is one, or a half where one of the two is not laid out
as if visible, which is where the half of a hidden neighbour's gap comes from; a plain number is halved the
same way. A number is rounded to the screen's scale before it becomes a constant, as UIKit rounds it.
