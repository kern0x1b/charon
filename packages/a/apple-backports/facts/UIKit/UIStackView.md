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

The backport instead ties each item to the stack with the multiplier of its share and asks at 999 - i.
On the host's solver the two agree on every frame the differential compares; on iOS 6 they do not, and
the frames of a proportional stack are the known difference. Carrying Apple's priorities across on their
own is not enough: with the reference item and the low priorities, and without the rest of the
arrangement's canvas connection, the host run fails 72 of its frames. The rest of that arrangement -
`_proportionalFillLengthForOrderedArrangement:relevantParentAxis:`, the canvas connection fitting
constraint and the hiding constraints - is the part still to read.
