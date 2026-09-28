# ModelConfiguration

The `ModelConfiguration` struct describes how a model container should persist its data. It holds:
- `name`: the configuration name
- `schema`: the optional schema (if not provided, the container's schema is used)
- `url`: the store URL (nil for in-memory)
- `allowsSave`: whether the store allows writes
- `isStoredInMemoryOnly`: whether the store is in-memory (derived from `url == nil`)
- `cloudKitContainerIdentifier`: nil (CloudKit not available on iOS 6)
- `cloudKitDatabase`: `.none` (CloudKit not available on iOS 6)
- `groupContainer`: `.none` (app groups not available on iOS 6)
- `groupAppContainerIdentifier`: nil

## Implementation

Maps to `NSPersistentStoreDescription`:
- If `url` is set, the store description's URL is set to it
- If `isStoredInMemoryOnly` is true, the store type is set to `NSInMemoryStoreType`
- `shouldAddStoreAsynchronously` is set to false for synchronous loading

The `validate()` method checks that the name is not empty and not longer than 255 characters, throwing `SwiftDataError` if validation fails.

## Nested Types

### GroupContainer
- `.none`: no group container
- `.automatic`: automatic group container (not implemented)
- `.identifier(String)`: explicit group container identifier

### CloudKitDatabase
- `.none`: no CloudKit
- `.automatic`: automatic CloudKit database
- `.private(String)`: private CloudKit database
- `.shared(String)`: shared CloudKit database
- `.public(String)`: public CloudKit database

Both are carried as structures but CloudKit is absent on iOS 6, so they have no effect on the store.

## Verification

Tested by:
1. Creating configurations with various combinations of URL, in-memory, and CloudKit settings
2. Passing configurations to `ModelContainer` and verifying the correct `NSPersistentStoreDescription` is created
3. Checking that in-memory stores use `NSInMemoryStoreType` and file-based stores use `NSSQLiteStoreType`
4. Validating the `validate()` method throws on empty/long names

## Divergences from macOS SwiftData

- CloudKit fields are carried but have no effect (CloudKit requires iOS 10+)
- Group container fields are carried but have no effect (app groups require iOS 8+)
- The `validate()` method throws `SwiftDataError` rather than Apple's internal error types