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

**583 of the corpus's 584 SwiftData rows are carried**, and the one that is not is
`DefaultSerialModelExecutor.asUnownedSerialExecutor()`, which the standard library's
`SerialExecutor` defines and this class inherits; the same call is spelled out where a caller needs
it, in `ModelActor.unownedExecutor`. The six macros are declared with Apple's own `@attached` roles
and compile with no plugin on the machine, because `#externalMacro` is only resolved when a macro
is *used*.

**What is not done is the expansion, not the API.** `SwiftDataMacros` - the host executable
`@Model` and the rest expand through - is not written, and it is waiting on `charon@swift-syntax`
(6ae40d50), which publishes the host compiler and the swift-syntax build a plugin is compiled
against. The rule that builds a plugin from sources is `rules/macro/xmake.lua`, from that series;
this package will name it and nothing more.

Built, measured: `swiftc -target armv7-apple-ios6.1.3` over the whole module, the swift-runtime
built with the Core Data backports and swift-foundation's `FoundationEssentials` and
`FoundationInternationalization` on the search path: **0 errors**, a `Mach-O object arm_v7` of
**856804 bytes, 2733 defined and 412 undefined symbols**. `-wmo -c` on its own writes that object;
the bitcode wrapper an earlier run produced came from asking for the module interface in the same
invocation, and a `-emit-library` link of it "succeeded" into a 16428-byte library with **zero**
defined symbols - which is how the check that now prints the counts came to exist.

The link is **not** finished, and for one reason only. Of the 412 undefined symbols, 118 are the
Swift standard library's and 60 are the Swift runtime's (both in `libswiftCore`, which the
program links), 32 are the port's own `Foundation` overlay, 7 are `Observation`, and 10 are
`FoundationEssentials` + `FoundationInternationalization` - `Predicate`, `SortDescriptor`, `Date`,
`UUID`. Those ten are swift-foundation's, and f25214c6's run output is its typecheck-only
`check.sh` path, so `lib_FoundationEssentials.dylib` does not exist anywhere. Every other import of
this module resolves against the runtime and the Core Data backports.

And the build is against swift-runtime `29dd4454` (recipe digest `875c24e4...`), while this tree
at `4d2e24e7` produces `0ccce571...` - the digest 4d2e24e7 regenerated for the backports' UIKit
7-12 and CarPlay series, which are `backports.lua` changes and so can move the lift. The newest
`backports=true` swift-runtime in the store is from 04:34 today, built against the older digest.
**This build has to be re-measured against the runtime this tree produces, and that is a gate-sized
job, not a band-sized one.**

Also missing, and not part of the 20: `DefaultStore`'s `HistoryProviding` conformance and
`ModelContext.fetchHistory`/`deleteHistory` are written as types but not wired to the store, and
`@Model` needs the plugin above before any of this is reachable from a program.

The differential so far is one case, and it is measured on both sides: `.agent-work/probe/model/
MissingValue.swift` is compiled against Apple's SwiftData on the host and typechecked against this
module for armv7, and the host's answer to a value the schema requires and the row does not hold
is a trap with those words - see `facts/SwiftData/Substrate.md`.
