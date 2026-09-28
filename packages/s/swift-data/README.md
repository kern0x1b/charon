# SwiftData for the port's armv7 releases

One Swift module, built for armv7 by `packages/s/swift-data/xmake.lua` against the
`charon@swift-runtime` a port carries:

| Module | Holds |
| --- | --- |
| `SwiftData` | `Schema`, `ModelConfiguration`, `ModelContainer`, `ModelContext`, `FetchDescriptor`, `PersistentIdentifier`, `Predicate`, `SortDescriptor`, and the model/attribute/relationship/index/uniqueness types |

**What is not here yet**, and is absent rather than stubbed:
- `DefaultStore`, `DefaultSnapshot`, `DefaultHistoryTransaction`, `DefaultHistoryToken`, `DefaultHistoryInsert`, `DefaultHistoryDelete` — the custom store implementation layer
- `HistoryDescriptor`, `HistoryTransaction`, `HistoryToken`, `HistoryChange`, `HistoryTombstone`, `HistoryProviding`, `HistoryInsert`, `HistoryDelete`, `HistoryUpdate` — the history API
- `DataStore`, `DataStoreConfiguration`, `DataStoreSnapshot`, `DataStoreError`, `DataStoreBatching` — the store abstraction layer
- `Schema.Index`, `Schema.Index.Types`, `Schema.Unique`, `Schema.Unique.CodingKeys` — advanced indexing
- `VersionedSchema`, `SchemaMigrationPlan`, `MigrationStage` — migration API
- `ModelExecutor`, `SerialModelExecutor`, `DefaultSerialModelExecutor`, `ModelActor` — concurrency/execution
- The SwiftUI integration (`Query`, `modelContext`, `modelContainer`, `AppStorage`, `SceneStorage`, `Model`, `DocumentGroup`) — requires SwiftUI

**What is implemented over the device's Core Data:**
- `Schema` and its nested types (`Entity`, `Attribute`, `Relationship`, `CompositeAttribute`, `Index`, `Unique`, `PropertyMetadata`) — the schema is serializable and can be reconstructed into an `NSManagedObjectModel`
- `ModelConfiguration` — maps to `NSPersistentStoreDescription` with in-memory or SQLite stores
- `ModelContainer` — wraps `NSPersistentContainer`, loads stores synchronously, provides `mainContext`
- `ModelContext` — wraps `NSManagedObjectContext`, implements `fetch`, `insert`, `delete`, `save`, `transaction`, `fetchCount`, `fetchIdentifiers`, `enumerate`
- `FetchDescriptor` — builds `NSFetchRequest` with predicate, sort descriptors, batch size, prefetching
- `Predicate` — wraps `NSPredicate`, the `#Predicate` macro is from swift-foundation
- `SortDescriptor` — wraps `NSSortDescriptor`
- `PersistentIdentifier` — wraps `NSManagedObjectID`, codable and comparable
- `PersistentModel` protocol — conformance added by the `@Model` macro (not in this package)
- `SwiftDataError` — the error enum with all documented cases

The storage layer is the device's own Core Data. `NSPersistentContainer` and `NSPersistentStoreDescription` exist on iOS 6.0; this package adds the SwiftData API as a layer on top. No matrix code, no second implementation of what the release already has.

**Host differential:** the same model, container, insert, fetch with a descriptor, save and delete, compared in two processes against macOS SwiftData.