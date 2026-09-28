# ModelContainer

The `ModelContainer` class is the main entry point for SwiftData. It holds:
- `schema`: the schema describing the persistent models
- `configurations`: the array of model configurations
- `mainContext`: the main context for the container (view context of the persistent container)
- `migrationPlan`: optional migration plan

It wraps `NSPersistentContainer` and provides:
- Synchronous store loading via `loadPersistentStores`
- `erase()` to destroy persistent stores
- `deleteAllData()` to delete all objects in all entities
- `newBackgroundContext()` to create a new background context

## Implementation

The initializer:
1. Creates a `Schema` from the model types
2. Creates configurations (defaulting to one "default" configuration if none provided)
3. Creates an `NSPersistentContainer` with the schema's `managedObjectModel`
4. For each configuration, creates an `NSPersistentStoreDescription` and adds it to the container
5. Loads stores synchronously using a semaphore
6. Creates the `mainContext` wrapping the container's view context

## Verification

Tested by:
1. Creating a container with a simple model type
2. Verifying the container loads without error
3. Using `mainContext` to insert, fetch, and save objects
4. Verifying `erase()` removes the store file
5. Verifying `deleteAllData()` removes all objects from all entities
6. Creating a background context and verifying it can fetch/insert independently

Host differential test (macOS SwiftData vs this implementation):
- Same model type, same container creation, same insert/fetch/save/delete sequence
- Results match: objects are persisted, fetched, and deleted identically

## Divergences from macOS SwiftData

- `NSPersistentContainer` on iOS 6 is the same as on macOS; the divergence is only in what the port's SwiftData layer adds on top
- The `migrationPlan` parameter is carried but not yet implemented (no migration logic)
- `configurations` array is used to create multiple store descriptions; on iOS 6 only one store is typically used
- `autosaveEnabled` on `ModelContext` defaults to true but is not yet connected to `NSPersistentContainer`'s auto-save