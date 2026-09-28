# PersistentIdentifier

The `PersistentIdentifier` struct identifies a persistent model instance across saves and launches. It holds:
- `id`: a `UUID` (generated on creation)
- `entityName`: the name of the entity
- `storeIdentifier`: the identifier of the persistent store (default "default")

It also has an inner `ID` type wrapping a `UUID`.

## Implementation

`PersistentIdentifier` is `Codable`, `Equatable`, `Hashable`, `Comparable`, and `Sendable`.

Two initializers:
- `init(id:entityName:storeIdentifier:)`: creates a new identifier
- `init(_ managedObjectID: NSManagedObjectID)`: wraps an existing `NSManagedObjectID`, extracting entity name and store identifier

The `managedObjectID` computed property would reconstruct an `NSManagedObjectID` (currently returns a new empty one; a real implementation would need the persistent store coordinator).

`identifier(for:primaryKey:)` creates an identifier for a given entity name and primary key value (currently just uses the entity name).

## Verification

Tested by:
1. Creating identifiers and verifying codable round-trip
2. Wrapping `NSManagedObjectID` and extracting entity name/store identifier
3. Comparing identifiers for equality and ordering
4. Using identifiers with `ModelContext.registeredModel(for:)` and `model(for:)`

Host differential test (macOS SwiftData vs this implementation):
- Same identifier creation, same codable round-trip
- Same equality/ordering behavior

## Divergences from macOS SwiftData

- The `managedObjectID` reconstruction is not fully implemented (returns empty `NSManagedObjectID`); a real implementation would need the persistent store coordinator to reconstruct the proper `NSManagedObjectID`
- The `id` is a generated `UUID` rather than derived from the `NSManagedObjectID`'s internal representation; on macOS the identifier is more directly tied to the object ID
- `identifier(for:primaryKey:)` is a stub that doesn't use the primary key value
- `PersistentIdentifier.ID` is a simple UUID wrapper; the macOS version may have additional functionality