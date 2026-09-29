# The two result-builder families — `IntentItem.Builder` and `IntentItemSection.Builder`

Both are the same shape of problem and the same reading, and the ledger carries seven rows between
them (`IntentItem.Builder` 4, `IntentItemSection.Builder` 3).

**The shape defect, fixed.** The framework nests the builder: `IntentItemSection.Builder` is an enum
*inside* `IntentItemSection` (`arm64e-apple-macos.swiftinterface:5003-5007`) and `IntentItem.Builder`
inside `IntentItem` (`:4951-4960`). This module keeps one builder per family and names it in the type
by a `typealias`, the way `IntentItem.Builder` already was (`Items.swift:18`) and
`IntentItemSection.Builder` now is — **a typealias, not a second declaration**, so the same builder
answers to the name the ledger carries.

**The reading, and why a reference rather than a call.** The digester prints a `@resultBuilder` type
with **no members at all** — measured on these two families and on `Tips.GroupBuilder` in the kits —
so a member cannot be found by name in the dump and a *call* would need a value of the type built
first. A reference is enough and needs nothing constructed: each member is bound to a closure type
that names the framework's signature, which is also what disambiguates the two `buildBlock`
overloads.

| row | the reference |
| --- | --- |
| `IntentItem.Builder.buildArray(_:)` | `let array: ([IntentItem<String>]) -> [IntentItem<String>] = …buildArray` |
| `IntentItem.Builder.buildBlock()` | `let empty: () -> [IntentItem<String>] = …buildBlock` |
| `IntentItem.Builder.buildBlock(_:)` | `let one: (IntentItem<String>) -> [IntentItem<String>] = …buildBlock` |
| `IntentItem.Builder.buildExpression(_:)` | `let expression: (IntentItem<String>) -> IntentItem<String> = …buildExpression` |
| `IntentItemSection.Builder` + its two `buildBlock`s | the same, in `probe-itembuilder.swift` |

**What is measured and what is not.** `IntentPerson`'s family is **placed**: its probe typechecks with
0 errors against the module built from this tree, because that module already carried the
declarations. These two families are **written and unmeasured**: both probes typecheck against a
*built* module, and the module in the store predates the `IntentItemSection.Builder` typealias. One
device compile of the module, then two typechecks, places all seven rows — and the load has been over
the cap for this whole turn, so nothing was submitted and nothing of mine holds a slot.
