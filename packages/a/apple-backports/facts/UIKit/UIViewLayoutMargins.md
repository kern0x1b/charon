# The layout margins of a view, iOS 8

Source: the host's own UIKit, measured against a superview whose margins overlap the subview, and the
differential run of `tests/backports/host/layout/run.sh`.

`layoutMargins` is eight points on each side to begin with, and it stores whatever it is given, negative
values and fractions included.

`preservesSuperviewLayoutMargins` is NO to begin with. Where it is YES the view's margins become the
larger of its own and the part of the superview's margin area that reaches into it, edge by edge. On a
300 by 300 superview with margins of 40, 50, 60 and 70, a subview at (20, 20) sized 100 by 100 answers a
top margin of 20 and a left margin of 30 - the superview's margin minus the distance to it - while its
bottom and right stay at eight, because the superview's margins on those sides do not reach it. Moved to
the corner the same subview answers 40 and 50. Setting the margins explicitly does not undo it: with
1, 2, 3, 4 set on that subview the answer is 40, 50, 3, 4, since each edge takes the larger of the two.

`-layoutMarginsDidChange` is sent to the view when the margins it answers change: once when they are set
to a new value, not at all when they are set to the value they already have, and once when
`preservesSuperviewLayoutMargins` changes what they come to.
