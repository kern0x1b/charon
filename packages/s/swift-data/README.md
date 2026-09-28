# charon@swift-data

The SwiftData module for the port's armv7 releases: a Swift module named `SwiftData`, built
against the `charon@swift-runtime` a port carries, so a program writes `import SwiftData`.

The storage is the release's own Core Data - `NSPersistentContainer` and
`NSPersistentStoreDescription` from iOS 6.0, the backports' `NSPersistentHistory*`,
`NSPersistentCloudKitContainer`, `NSBatchDeleteRequest` and `NSFetchIndexDescription` below it -
and this package is the SwiftData API as a layer over it.

What is measured about that substrate, and what the port does and does not have, is in
`facts/SwiftData/Substrate.md`. Two things a caller should read there first: a Swift module
cannot be built for the 4.3 band (the runtime's own `Swift` module has a floor of iOS 6.0, because
every Core Data backport entry has `minimum: 6.0`), and `FetchDescriptor`'s predicate and sort
order are `Foundation.Predicate` and `Foundation.SortDescriptor`, which arrive with
`charon@swift-foundation` and are not on the port yet.

## State of this package

**564 of the corpus's 584 SwiftData rows are carried** and 20 are not, all twenty with a reason in
`registry/SwiftData.json`. What is missing is the six macro names and the actor family, and both
are one thing: nothing expands a macro yet, and nothing runs a model on its own executor.

Built, measured: `swiftc -target armv7-apple-ios6.1.3` over the whole module, the swift-runtime
built with the Core Data backports and swift-foundation's `FoundationEssentials` and
`FoundationInternationalization` on the search path, **0 errors**, 654680 bytes of object, the
target triple read back out of it. The link of that object is not shown, because
`-wmo`'s output is a bitcode wrapper and the two routes that would read it are both unavailable
here (the pinned llvm has no `LLOP.so`, and this driver answers "unable to load output file map"
for a valid one). The package's own `on_install` compiles per source file and would link; it
cannot run yet, because `charon@swift-foundation` is f25214c6's series and not in the shared store.

Also missing, and not part of the 20: `DefaultStore`'s `HistoryProviding` conformance and
`ModelContext.fetchHistory`/`deleteHistory` are written as types but not wired to the store, and
`@Model` needs the plugin above before any of this is reachable from a program.

The differential so far is one case, and it is measured on both sides: `.agent-work/probe/model/
MissingValue.swift` is compiled against Apple's SwiftData on the host and typechecked against this
module for armv7, and the host's answer to a value the schema requires and the row does not hold
is a trap with those words - see `facts/SwiftData/Substrate.md`.
