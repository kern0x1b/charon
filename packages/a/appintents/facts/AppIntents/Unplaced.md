# The 291 unplaced AppIntents rows, grouped by type

`swift-api-digester -dump-sdk` of the module built for `armv7-apple-ios6.1.3`, every row the ledger
lists that the dump does not print under the name the ledger gives it, sorted by
`.agent-work/host/classify.py`. **291 unplaced = 274 missing + 17 wrong-kind** of 2323 rows;
2032 placed. The handoff for the ledger band is
`.agent-work/handoffs/2026-09-28-ledger-swift-digester-naming.md`.

| how the digester prints it | rows | whose work it is |
| --- | --- | --- |
| printed, under another name | **106** | the ledger's matcher: a generic initialiser's parameter list (68, all `IntentParameter.init`), `==(a:b:)`→`==(_:_:)`, `init?(coder:)`→`init(coder:)`, `subscript(keyPath:)`→`subscript(_:)` |
| owner not printed at all | 27 | the cross-module gap, with the other modules compiled and on `-I` |
| member not printed | 125 | the port's own work, below |
| bare row, no owner | 16 | Apple's `AppIntentsMacros`: `AppEntity(schema:)`, `AppEnum(schema:)`, `AppIntent(schema:)`, `AssistantEntity/Enum/Intent(schema:)`, `ComputedProperty()` ×5, `DeferredProperty()` ×2, `UnionValue()` |

## `member not printed`, 125 rows, by type

| type | rows | what they are |
| --- | --- | --- |
| `IntentParameter` | 27 | `IntentParameter.<Unit>.==(a:b:)` for 26 unit enums and `ValueState.==(lhs:rhs:)` — 24 of the 26 are the **measurement-typed** ones, whose `Value` is Foundation's `Measurement`; the recipe's own probe measures that at 6.1.3 the runtime has no `Measurement` (`'Measurement' is only available in iOS 10.0 or newer`), so those are the Foundation band's rows. The 5 that are not gated — `DateKind`, `DoubleControlStyle`, `IntControlStyle`, `PlacemarkDisplayStyle`, `ValueState` — are measured by a typecheck call site, `.agent-work/host/probe-appintents-equality.swift`, which passes against Apple's AppIntents (exit 0) **and** against this module (exit 0), so they are placed by the criterion the coordinator set |
| `IntentPerson` | 14 | the same finding on `Handle`, `Handle.Value`, `Handle.Label`, `Name`, `Identifier` (`==`, `init(from:)`, `encode(to:)`), plus `ParameterMode.init?(rawValue:)`. The five `==` are placed by the same typecheck probe; the eight `init(from:)`/`encode(to:)` are what the digester does not print and a call site for them needs an *instance* of each type, which the probe would have to build from the framework's own initialisers — not done |
| `IntentItemSection` | 5 | `Builder`, the result-builder type the digester prints with no members, and the presentation rows |
| `ContainsComparator` | 5 | `init(<T>:mappingTransform:)` for five value types — the generic-list naming gap again |
| `IntentItem`, `IntentFile`, `IntentParameterSummary` | 12 | the item/file/summary families' presentation and provider rows |
| `ParameterSummaryWhenCondition`, `ParameterSummarySwitchCondition` | 6 | the summary conditions' initialisers |
| `String`, `Measurement`, `Calendar`, `AttributedString` | 16 | **Foundation Swift r2's**, gated in `Gated.swift` and not this band's: the types are carried by the Foundation port, not by AppIntents |
| `AppEntity`, `EntityProperty`, `EntityQueryProperty`, `EntityQueryProperties`, `EntityQuerySortingOptions` | 13 | the query/entity metadata rows, the part of this family the macro rows sit inside |
| `DisplayRepresentation` | 2 | the display's own `Image`/`Video` metadata |
| `CSSearchableItem`, `CSSearchableIndex`, `CSSearchableItemAttributeSet` | 8 | the Spotlight rows, the family `modules/apple/spotlight_lift.lua` covers on the Objective-C side |
| `HasPrefixComparator`, `HasSuffixComparator`, `IsBetweenComparator` | 6 | the other three comparators, the same generic-list gap |
| the tail (`IntentModes`, `IntentChoiceOption`, `ForegroundContinuableIntent`, `StringSearchCriteria`, `EntityURLRepresentation`, `AppIntentError.PermissionRequired`) | 21 | one to five rows each |

## The next whole families, in the order they pay

1. **The comparators** — `ContainsComparator`, `HasPrefixComparator`, `HasSuffixComparator`,
   `IsBetweenComparator`, 15 rows, one shape, and the port already has three of the four. What they
   need is not new code but the *right spelling* of a generic initialiser the digester cannot print,
   so they move with the ledger's normalisation 5, not before it.
2. **`IntentPerson`** — 14 rows, and the 8 that are `==`/coding members are finding 6. What is left is
   `ParameterMode.init?(rawValue:)` and the `Handle`/`Name`/`Identifier` initialisers the interface
   names, which the port does not declare.
3. **`IntentItem` / `IntentFile` / `IntentItemSection`** — 21 rows, the items a Shortcut shows.
4. **The query/entity metadata** — 13 rows, and the same shape as the macro rows they sit beside.
5. **`CSSearchable*`** — 8 rows, and the Objective-C side of that family is already lifted.
