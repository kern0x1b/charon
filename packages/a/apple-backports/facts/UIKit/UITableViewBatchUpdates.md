# The batch updates of a table view, iOS 11.0

Introduced in iOS 11.0: one call that groups a table's insertions, deletions,
moves and reloads and tells the caller when the animation is done.

Source: UIKit of the arm64 shared cache of iOS 11.0
(`-[UITableView performBatchUpdates:completion:]` at `0x18a2cc288`, which passes
the two blocks to `-_performBatchUpdates:withContext:completion:` at
`0x18a1b6768`) and the differential test against the host's UIKit
(`tests/backports/host/batchupdates`).

## Behaviour

The update block runs **synchronously**, inside the call, and the completion
runs later, once the table's animation has finished — after the run loop has
turned, never inside the call. The whole group behaves as one update: the table
ends with the rows the group leaves it, and one call brings exactly one
completion.

A `nil` update block and a `nil` completion are both accepted without
complaint, and so is an empty block. A call nested inside another update block
works: the inner block runs where it stands, and the rows of both land
together.

The port wraps iOS 6's own `-beginUpdates` and `-endUpdates`, which have grouped
a table's changes since iOS 2, in a Core Animation transaction whose completion
block carries the caller's completion. That gives the same order the test pins
down: `before`, `inside`, `after the call`, then the completion after the run
loop turns.

## The one thing the port cannot tell

Apple's completion receives whether the animation actually finished, and answers
`NO` when it was cut short — a table outside a window, for instance, reports
`NO` in the host test. A Core Animation transaction does not hand that back, so
the port always reports `YES`. Everything else about the completion — that it
runs, that it runs once, and that it runs after the animation rather than inside
the call — matches.
