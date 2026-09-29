# The shape checks, and the one that does not yet hold the port's own labels

Two checks live in `packages/a/appintents/tests/`, both reading the framework's interface from the
machine's `charon@iphoneos-sdk` 26.2 install and **run directly** — no build, no slot:

| tool | rows it holds | state |
| --- | --- | --- |
| `builder-contract.py` | the two result-builder families' seven rows | **green (7 rows, 0 failures) but one-sided, and the review is right** |
| `foreground-continuation-contract.py` | the three `ForegroundContinuableIntent` shapes | green (3 of 3 declared, 0 shape failures), one-sided in the same way |

## What the review found, reproduced here

`builder-contract.py` printed the **framework's** declaration as its evidence and compared the
*interface* against the ledger's selector. It never read the port's declaration's labels, so both of
the review's mutations of the port's own declaration —

    public static func buildBlock(_ item: Item) ...      ->  _ item2: Item
    public static func buildBlock(_ item: Item) ...      ->  item: Item

— left it at `7 rows, 0 failures, EXIT=0`.

## Why the obvious fix is a false comparison, measured

Making the checker compare the *port's* labels against the *row's* spelling fails on four of the seven
rows, and the failure is a category error rather than a bug in the port: a ledger row spells an
unnamed first parameter `_` (`buildArray(_:)`, `buildExpression(_:)`) while this module's declaration
names it (`_ items:`, `_ expression:`) — the framework's own declaration names it too
(`_ components:`, `_ expression:`). Comparing a *row* against a *declaration* therefore reports four
false failures; comparing a *declaration against a declaration* would false-fail on every renamed
parameter, which is not a defect at all.

**What catches both mutations is a call site in the framework's own spelling**, because a rename or a
dropped underscore changes how a caller writes the call:

    Item.Builder.buildArray(components)   // `item:` and `item2:` both stop this compiling

So the fix is in the probes, not in the checker: `probe-intembuilder.swift` and
`probe-itembuilder.swift` must bind each member to a closure that **calls** it with the framework's
parameter name, and the checker's job is to typecheck those probes against a module built from this
tree. That is a device compile and a typecheck, not a `python3` run — which is the same one-line
classification `NextFamily.md` already gives these seven rows, and the reason the *shape* check and
the *call* check are two different tools.

## What is not done, and is not being claimed

The two checks stay one-sided in this commit. The version in the tree is the one that was reviewed —
green on what it reads, silent on the port's labels — and it is recorded here as **not holding the
port's declarations** rather than described as a check that does. The pieces that would fix it, in
order:

1. `probe-intembuilder.swift` / `probe-itembuilder.swift`: call each member with the framework's own
   parameter name, so a renamed or un-underscored label fails to typecheck.
2. One device compile of the module (a slow slot, guarded), then those two typechecks.
3. `classify-rows.py`'s invocation with real paths is still owed and is not in this commit; the tool's
   header says what it reads, and the invocation is the next piece.
