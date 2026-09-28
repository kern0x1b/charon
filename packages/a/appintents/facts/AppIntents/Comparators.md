# The comparison operators: nine equalities that answered `true` for every pair

Twenty-nine `==` in this module were written `{ return true }`, and twenty-six `hash(into hasher:)`
were written `{}`. Both are the fabricated answer the API push's rules forbid, and both are wrong in
a way a port acts on: a query compares **the operator a rule wrote** with **the one it runs**, so
`ComparableComparisonOperator.lessThan == .greaterThan` returning `true` means a rule written
`lessThan` runs as `greaterThan` and matches. A hash that tells no two values apart puts every value
of a type in one bucket, so a dictionary keyed by a shortcut tile colour or a phrase token has one
key however many values it holds.

**Nine of the twenty-nine are fixed** — the types whose cases are a plain list, each now carrying an
`ordinal` and both members made of it, which is the shape this port already used for
`Tips.InvalidationReason`:

| type | cases | file |
| --- | --- | --- |
| `HasValueComparisonOperator` | 2 | `Queries.swift` |
| `EquatableComparisonOperator` | 2 | `Queries.swift` |
| `OneOfComparisonOperator` | 1 | `Queries.swift` |
| `ComparableComparisonOperator` | 4 | `Queries.swift` |
| `StringComparisonOperator` | 4 | `Queries.swift` |
| `EntityQueryComparatorMode` | 2 | `Queries.swift` |
| `AppShortcutPhraseToken` | 1 | `Shortcuts.swift` |
| `ShortcutTileColor` | 16 | `Shortcuts.swift` |
| `SetFocusFilterIntentError` | 2 | `SystemIntents.swift` |

**Measured two ways.** The call sites are in `.agent-work/host/probe-comparators.swift`: twelve
questions — does an operator equal itself, does it equal its neighbour, does a tile colour equal
itself and its next — which **typecheck against Apple's AppIntents** on the host (0 errors, and
`apple-comparators.txt` has Apple's twelve answers) **and against this module** for
`armv7-apple-ios6.1.3` (0 errors). The port's *answers* cannot be measured on this machine: the
module does not build for the host (53 errors, the same wall as ActivityKit's and WidgetKit's
differentials) and there is no iOS runtime here, so the behaviour half of this family needs an
emulator run and the declaration half is what the typecheck settles.

**Twenty are still written `{ return true }`** — one in `Items.swift` (`IntentFileError`), one in
`Queries.swift`, three in `URLRepresentations.swift`, six in `Values+Foundation.swift` and nine in
`Values.swift` — and twenty-six `hash(into:)` are still `{}`. Those types are the resolvers and the
value wrappers, whose cases carry a payload (`DoubleFromStringResolver` and the rest take the value
they resolve), so the discriminator is the payload and not a case index: they need the same `ordinal`
computed from the value, which is the next step and not one this commit makes. They are listed here
so that nobody reads "nine fixed" as "all fixed".
