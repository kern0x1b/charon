# `IntentItemSection.Builder` — the shape was wrong, and the reading is written

The corpus ledger carries three rows for this family, and the **first** of them was a real shape
difference this series had wrong:

| row | before | now |
| --- | --- | --- |
| `IntentItemSection.Builder` | the module had one builder, `IntentItemSectionBuilder<Item>`, reachable only under that name | `IntentItemSection.Builder` is a `typealias` to it, inside the type (`Items.swift`), the way `IntentItem.Builder` already is at `Items.swift:18` |
| `IntentItemSection.Builder.buildBlock()` | declared, on the top-level builder | declared, and reachable under the framework's name |
| `IntentItemSection.Builder.buildBlock(_:)` | declared, on the top-level builder | declared, and reachable under the framework's name |

The framework nests the builder — `arm64e-apple-macos.swiftinterface:5003-5007` is
`@_functionBuilder public enum Builder` *inside* `IntentItemSection`, with
`buildBlock() -> [IntentItemSection<Result>]` and two variadic `buildBlock`s — and the port's
`IntentItemSection` had no `Builder` at all, so no row of the family could be read. A typealias and
not a second declaration: it is the same builder, under the name the ledger names.

**The reading is written, and it is the same kind as `IntentPerson`'s**
(`.agent-work/host/probe-itembuilder.swift`): the digester prints a `@resultBuilder` type with **no
members at all** — measured on this family and on `Tips.GroupBuilder` in the kits — so each member is
referenced in the framework's spelling, with a closure type that names the signature
(`let variadic: (IntentItemSection<String>…) -> [IntentItemSection<String>] = …buildBlock`), which
disambiguates the overload without constructing a value.

**What is not yet measured, and why.** The probe typechecks against a *built* module, and the module
in the store predates this typealias — it answers `type 'IntentItemSection<String>' has no member
'Builder'`, which is the old build talking. So the three rows are **not placed yet**: placing them
needs one device compile of the module (the AppIntents build under the guard) and then the typecheck
above. That is the next step, and it is a device compile rather than a macro build, so it is not
blocked on the addon release.
