# The two intent providers, and the spellings they do not share with the timeline provider

`AppIntentTimelineProvider` and `IntentTimelineProvider` are `TimelineProvider`s, so they inherit
`placeholder(in:)`, `getSnapshot(in:completion:)`, `getTimeline(in:completion:)` and `relevance()` - the
framework declares those *on the two protocols* as well, under the spellings the configuration's intent
gives them a reason for:

| provider | snapshot | timeline |
| --- | --- | --- |
| `TimelineProvider` | `getSnapshot(in:completion:)` | `getTimeline(in:completion:)` |
| `AppIntentTimelineProvider` | `snapshot(for:in:)` | `timeline(for:in:)` |
| `IntentTimelineProvider` | `getSnapshot(for:in:completion:)` | `getTimeline(for:in:completion:)` |

The two intent providers also ask for recommendations - the intents the system should offer the owner
to configure this widget with - which is `recommendations()`, and the app-intent one names the intent
instance the widget is configured with, which is what the `for:` of those two spellings is.

These are the rows the module's next pass writes; the rest of WidgetKit's surface is declared and
measured (245 of 340 placed, and the 95 that are not are listed in
`.agent-work/runs/kits/WidgetKit-missing.tsv`).

## What landed after the TipKit differential, and what the ledger can see of it

The ten rows the coordinator named are **declared and compile** (`Sources/WidgetKit/Providers.swift`
and `Configuration.swift`):

| row | where |
| --- | --- |
| `AppIntentTimelineProvider.snapshot(for:in:)`, `.timeline(for:in:)` | `Providers.swift`, `async`, the configuration passed in |
| `AppIntentTimelineProvider.placeholder(in:)`, `.recommendations()`, `.relevance()` | same protocol, with the framework's own default implementations in the extension |
| `IntentTimelineProvider.getSnapshot(for:in:completion:)`, `.getTimeline(for:in:completion:)`, `.placeholder(in:)`, `.recommendations()`, `.relevance()` | `Providers.swift`, the completion-handler shape |
| `WidgetPushHandler.pushTokenDidChange(_:widgets:)` | `Configuration.swift` |

Three of these changed the design, not just the count:

- `AppIntentTimelineProvider` no longer inherits `TimelineProvider`. The interface
  (`WidgetKit-ios.swiftinterface:1538`) declares it standalone with its own `Entry`/`Intent` and the
  *async* `snapshot(for:in:)`/`timeline(for:in:)`, so a provider answers one way, not two. It was an
  empty refinement of `TimelineProvider` before, which made a conformer implement the completion
  handlers as well.
- `IntentTimelineProvider` likewise, and its `Intent` is constrained to the AppIntents `AppIntent`
  rather than the interface's `Intents.INIntent`: the Objective-C framework is another band's and is
  not on these releases, and the port's own `IntentConfiguration` already takes that type. The
  divergence is here, not hidden.
- `WidgetPushHandler` was a `final class` with a `pushTokensDidChange(widgets:)` the framework does
  not declare; it is now the framework's protocol with `pushTokenDidChange(_:widgets:)`.

**The ledger cannot count nine of the ten.** `WidgetPushHandler.pushTokenDidChange(_:widgets:)` is
now placed (245 rows placed, one more than before). The nine intent-provider rows stay in
`WidgetKit-missing.tsv` because the digester prints **nothing** for either protocol — not the
protocol row for `AppIntentTimelineProvider`, not its `Context` typealias, not a member — and
`IntentTimelineProvider`'s own protocol row flipped *into* the missing list. The two protocols are the
only ones in this module whose associated types and members name a type from another module
(`AppIntents.WidgetConfigurationIntent`, `AppIntents.AppIntent`), which is the gap this repository's
own notes already record for `AlertConfiguration.title` and
`WidgetInfo.widgetConfigurationIntent(of:)`: a member typed with another module's type is not
reported even with that module on the digester's `-I`. `IntentTimelineProvider` was counted as
placed before only because it was an empty refinement, with no member of its own to drop.
