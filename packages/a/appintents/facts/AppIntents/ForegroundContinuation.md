# `ForegroundContinuableIntent` — the two rows, and why they are not written yet

The next family piece after the two builder families, by the order in `NextFamily.md`. The corpus
ledger carries two rows, and this module has an **empty** `extension ForegroundContinuableIntent`
(`Remaining.swift:230`), so both are undeclared — and the check says so rather than the facts
asserting it: `packages/a/appintents/tests/foreground-continuation-contract.py`, run directly.

**What the framework declares**, quoted from the machine's `charon@iphoneos-sdk` 26.2 install:

| row | the framework's declaration |
| --- | --- |
| `requestToContinueInForeground(_:continuation:)` | `public func requestToContinueInForeground<ResultValue>(_ dialog: AppIntents.IntentDialog? = nil, continuation: @MainActor () async throws -> Result) -> Result` |
| `needsToContinueInForegroundError(_:continuation:)` | `public func needsToContinueInForegroundError(_ dialog: AppIntents.IntentDialog? = nil, continuation: (@MainActor () async throws -> Void)? = nil) -> AppIntentError` |

**What makes these two different from every family this band has done, and why they are not written in
this commit.** Every earlier declaration was a shape the interface fully determined — a stored
property, a `static var` of a named type, a `@resultBuilder` member. These two have a **generic
parameter and a return type the interface fixes to the *caller's* `Result`**:

* `requestToContinueInForeground` is generic in a `ResultValue` and returns it: it runs the
  continuation and hands back the value the caller asked for. The port would have to carry that
  generic parameter, and to decide what it does *with* the answer — which is a system's job (does the
  run carry on, does it come back to the foreground), and there is no system here. The port's
  `CharonForeground.Continuation` is a value with `mayContinue`, which is the port's own answer to
  "may it carry on", and wiring it to a generic `ResultValue` is a design decision, not a copy of a
  signature.
* `needsToContinueInForegroundError` has a **second overload** in the same interface taking
  `alwaysConfirm: Bool` and returning `AppIntentError`; the ledger's row is the `continuation:` one. A
  declaration that only had the overload the ledger names would be a subset, and a subset chosen by
  which row happens to be in the ledger is a metric, not a shape.

So this piece is the **check and the two quoted declarations**, which is what lets the next one write
the code against the interface rather than against my memory of it. The check runs, exits 0, and
prints `0 of 2 rows declared` — which is the fact.
