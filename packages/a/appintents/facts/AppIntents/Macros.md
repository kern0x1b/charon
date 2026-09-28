# The macro rows, and why the expansion cannot be compared on this machine

Nineteen rows name a macro the framework's compiler expands: `AppIntentsMacros` (16 — `AppEntity`,
`AppEnum`, `AppIntent`, `AssistantEntity`, `AssistantEnum`, `AssistantIntent`, `ComputedProperty`
×5, `DeferredProperty` ×2, `UnionValue`) and `TipKitMacros` (2 — `Rule`, `Parameter`).
`Sources/AppIntents/Remaining.swift` and `Sources/TipKit/Predicates.swift` **declare** them with the
framework's own `@attached` attributes; what is missing is the plugin that expands them, and that
plugin is Apple's, on Apple's releases, and is not here.

**Measured: Apple's plugin is not reachable on this machine.** The toolchain the packages build
against (`charon@swift`, 6.4) ships two host plugins and no more:

```
$ ls …/swift/6.4.0/f1d0e4…/lib/swift/host/plugins/
libObservationMacros.dylib
libSwiftMacros.dylib
```

`find` over the Command Line Tools, the shared store and `~/Library/Developer` finds no
`AppIntentsMacros` and no `TipKitMacros` — no `*Macros*` directory anywhere but swift-syntax's own
`SwiftSyntaxMacros.swiftmodule`. The macOS 27 SDK's `AppIntents` interface *names* the plugin
(`arm64e-apple-macos.swiftinterface:55,192,2863,3954` all say
`#externalMacro(module: "AppIntentsMacros", type: …)`), which is why the declarations in
`Remaining.swift` are exactly right and still cannot be expanded here: `#externalMacro` resolves
against a loaded plugin, and there is none to load.

**So the reference is the interface, and the comparison is a hand-checked one.** Every macro's
contract is in that file, and it is complete enough to implement against:

| macro | the interface's attachments |
| --- | --- |
| `ComputedProperty()` | `@attached(peer, names: prefixed(`$`), prefixed(`_`))` `@attached(accessor, names: named(get), named(set))` — so `$foo` and `_foo` peers and a get/set pair |
| `AppEntity<T>(schema:)` | `@attached(memberAttribute)` `@attached(extension, conformances: AppEntity, AssistantSchemaEntity, names: named(__assistantSchemaEntity))` |
| `AssistantIntent<T>(schema:)` | `@attached(memberAttribute)` `@attached(extension, conformances: AssistantSchemaIntent, ShowInAppSearchResultsIntent, names: named(__assistantSchemaIntent))` |
| `AppIntent<T>(schema:)` | `@attached(memberAttribute)` `@attached(extension, conformances: AppIntent, names: named(perform))` |

A plugin written here would be compared against those attachments and against a hand-expanded
example per macro — the *contract*, not Apple's output. **That is weaker than a diff, and the
difference is stated rather than papered over:** Apple's expansion of `#AppEntity(schema:)` is
whatever `AppIntentsMacros.AppEntityMacros` produces, and no copy of it is on this machine to diff
against. The gate for claiming a macro is done is therefore: the expansion this port produces
matches the interface's declared attachments exactly, and the hand-checked expansion of a small
example is in `.agent-work/` beside the plugin.

**The loader is in place.** `415a119e "Let a port expand a macro plugin its dependencies ship"` is
cherry-picked here (`-x`, so both series carry the same commit): `rules/swift/xmake.lua:182` adds each
dependency's `CHARON_SWIFT_PLUGINS` folders as `-plugin-path`, so a package that builds a plugin can
be found by a port that uses it. What remains is the plugin itself, for the host, built with
swift-syntax (Apache-2.0), and the 19 rows move when it exists and not before.
