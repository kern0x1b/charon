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

The rewrite of the pilot's draft is in progress and does not compile yet. What is landed here is
measured and true: the substrate, the schema (`Schema`, `Schema.Version`,
`Schema.PropertyMetadata`, `Schema.Entity`, `SchemaProperty`, `Schema.Attribute`,
`Schema.CompositeAttribute`, `Schema.Relationship`, `Schema.Index`, `Schema.Unique`),
`PersistentIdentifier`, `PersistentModel` and its `BackingData` with the Core Data behind it,
`ModelConfiguration`, `VersionedSchema`/`SchemaMigrationPlan`/`MigrationStage`, `FetchDescriptor`
and `FetchResultsCollection`, `ModelContext`, and the two error types.

What is not here yet: `ModelContainer`, the `DataStore` layer and its `DefaultStore`, the history
API, the model executors, and the `SwiftDataMacros` plugin that `@Model` and the rest are
declared as. A `ModelContext` without its container cannot be built, so the module as it stands
does not typecheck; the next step is `ModelContainer` and then the store.
