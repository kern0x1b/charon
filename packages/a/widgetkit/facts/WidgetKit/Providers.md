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
