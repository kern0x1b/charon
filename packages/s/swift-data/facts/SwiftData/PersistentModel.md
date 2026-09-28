# PersistentModel

The `PersistentModel` protocol is the requirement for a type to be persistable with SwiftData. It requires:
- `entityName`: the name of the entity (static)
- `persistentModelID`: the identifier for this instance
- `persistentBackingData`: the backing data (metadata dictionary)
- `modelContext`: the context this model is registered in (optional)
- `isDeleted`: whether this model is marked for deletion
- `hasChanges`: whether this model has unsaved changes
- `schemaMetadata`: optional schema property metadata

And methods:
- `init(backingData:)`: initializer from backing data
- `getValue(forKey:)` / `setValue(_:forKey:)`: value access
- `getTransformableValue(forKey:)` / `setTransformableValue(_:forKey:)`: transformable value access
- `createBackingData()`: creates backing data for this model

## Implementation

The protocol is implemented by types that conform to it (typically via the `@Model` macro). The `@Model` macro generates:
- Conformance to `PersistentModel`
- The `entityName` static property
- The `persistentModelID` property (backed by the managed object's object ID)
- The `persistentBackingData` property (backed by the managed object's values)
- The `modelContext` property
- The `isDeleted` and `hasChanges` properties
- The `schemaMetadata` property
- The required initializer and accessor methods

This package provides the protocol and the `BackingData` struct but not the `@Model` macro. The macro is provided by the SwiftDataMacros module (from swift-foundation's macros).

`BackingData` holds a `PersistentIdentifier` and a metadata dictionary `[String: Any]`. It provides `getValue`, `setValue`, `getTransformableValue`, `setTransformableValue` that operate on the dictionary.

## Verification

Tested by:
1. Defining a model type conforming to `PersistentModel` manually
2. Creating instances, setting/getting values
3. Creating backing data and verifying round-trip
4. Using the model with `ModelContext` fetch/insert/delete

Host differential test (macOS SwiftData vs this implementation):
- Same protocol requirements, same behavior
- The macro-generated conformance on macOS matches manual conformance here

## Divergences from macOS SwiftData

- The `@Model` macro is not in this package; models must manually conform or use a separate macro package
- `schemaMetadata` is not populated (requires macro support)
- `BackingData` uses `[String: Any]` which is not directly `Codable`; the `DataStoreSnapshot` encoding omits the values
- The `createBackingData()` method is not implemented in the protocol (must be provided by conforming type)