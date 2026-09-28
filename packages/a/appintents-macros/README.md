# charon@appintents-macros

The macro plugins `charon@appintents` and `charon@tipkit` name: `AppIntentsMacros` and `TipKitMacros`,
as host executables a device compile loads with `-load-plugin-executable`.

The framework expands these with its own compiler plugin, which is on the framework's own releases and
not on these, so a port that writes `@AppEntity(schema:)` has no expansion. This package is the port's
own expansion of them, and it is what the 19 macro rows in `charon@appintents` and the three in
`charon@tipkit` are waiting for.

**Built against `charon@swift-syntax`**, the Apache-2.0 upstream at the tag that matches the fleet's
6.4 toolchain, and not against the toolchain's own copy: that copy exports every macro protocol
(`AccessorMacro`, `PeerMacro`, `MemberAttributeMacro`, `MemberMacro`, `ExtensionMacro`,
`FreestandingMacro`, `Macro`) and **no** `CompilerPlugin` — it sits behind `@_spi(PluginMessage)` in
`SwiftCompilerPluginMessageHandling`, so a `-load-plugin-executable` cannot be written against it. The
measurement is in the commit that found it, and `packages/a/appintents/facts/AppIntents/Macros.md`
records what each macro's contract is, read off the framework's own `@attached` declarations.

**What is written and what is not**, per macro, in `Sources/`:

| macro | roles | state |
| --- | --- | --- |
| `ComputedProperty()` | peer + accessor | written, and both roles **typecheck** against the toolchain's own swift-syntax; the entry point and the expansion test are blocked on the package |
| `DeferredProperty()` | peer + accessor | not started |
| `AppEntity<T>(schema:)`, `AppIntent<T>(schema:)`, `AppEnum<T>(schema:)` | memberAttribute + extension | not started |
| `AssistantEntity/Enum/Intent<T>(schema:)` | memberAttribute + extension | not started |
| `UnionValue()` | expression | not started |

Apple's own plugin is **not** on this machine — the toolchain ships `libObservationMacros` and
`libSwiftMacros` and nothing else — so the reference is the framework's interface declarations plus a
hand-checked expansion, not a diff against Apple's output. `tests/Expansions.swift` says so in its own
header, and says which two of its own errors are its own.
