# ModelContext

The `ModelContext` class wraps `NSManagedObjectContext` and provides the SwiftData API for fetching, inserting, deleting, and saving models. It holds:
- `container`: the owning `ModelContainer`
- `autosaveEnabled`: whether to auto-save (default true, not yet connected)
- `undoManager`: optional undo manager
- `author`: optional transaction author
- `context`: the wrapped `NSManagedObjectContext`

Properties:
- `hasChanges`: whether the context has pending changes
- `insertedModelsArray`: inserted models (filtered from `registeredObjects`)
- `deletedModelsArray`: deleted models (from `deletedObjects`)
- `changedModelsArray`: changed models (from `updatedObjects`)
- `editingState`: the current editing state with author
- `willSave`/`didSave`: notification publishers

## Implementation

Methods:
- `fetch(_ descriptor: FetchDescriptor<T>)`: builds `NSFetchRequest` from descriptor, executes fetch, returns typed results
- `fetch(_ request: NSFetchRequest)`: direct fetch with request
- `fetchCount(_ descriptor)`: count-only fetch
- `fetchIdentifiers(_ descriptor)`: fetch managed object IDs, wrapped in `PersistentIdentifier`
- `enumerate(_ descriptor, batchSize, block)`: batched fetch with callback
- `insert(_ model)`: inserts the model's managed object
- `delete(_ model)`: deletes the model's managed object
- `delete(model:where:includeSubclasses:)`: fetch and delete matching models
- `save()`: saves the context
- `rollback()`: rolls back the context
- `processPendingChanges()`: processes pending changes
- `registeredModel(for:)`: returns registered model for identifier
- `model(for:)`: typed version of registeredModel
- `transaction(block:)`: performs block in context's queue

## Verification

Tested by:
1. Creating a container and getting its `mainContext`
2. Inserting a model, saving, and verifying it persists
3. Fetching with `FetchDescriptor` (no predicate, with predicate, with sort)
4. Fetching count and identifiers
5. Deleting a model and verifying it's gone
6. Using `transaction` to group operations
7. Rolling back and verifying changes are discarded
8. Background context operations

Host differential test (macOS SwiftData vs this implementation):
- Same model, same insert/fetch/save/delete sequence
- Results match: object identity, fetch results, change tracking

## Divergences from macOS SwiftData

- `autosaveEnabled` is a property but not connected to `NSPersistentContainer`'s auto-save
- `undoManager` is a property but not automatically created
- `willSave`/`didSave` are `NotificationCenter.Publisher` wrappers; the actual notifications are `NSManagedObjectContext.willSaveNotification`/`didSaveNotification`
- `editingState` is a simple struct with `id` and `author`; the full `EditingState` with pending changes tracking is not implemented
- `fetchHistory`/`deleteHistory` are stubs returning empty/doing nothing (history API not implemented)
- `enumerate` uses `fetchBatchSize` but does not implement `allowEscapingMutations`
- `delete(model:where:includeSubclasses:)` does not use `includeSubclasses` (fetches only the exact type)