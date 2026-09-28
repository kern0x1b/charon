# SwiftDataError

The `SwiftDataError` enum represents errors that can occur during SwiftData operations. It is `Error`, `Sendable`, `Equatable`, and `Hashable`.

## Cases

- `unsupportedPredicate`: the predicate type or operation is not supported
- `unsupportedSortDescriptor`: the sort descriptor type or operation is not supported
- `unsupportedKeyPath`: the key path is not supported for the operation
- `unknownSchema`: the schema is not recognized
- `sortingPendingChangesWithIdentifiers`: attempting to sort pending changes with identifiers
- `modelValidationFailure`: model validation failed
- `missingModelContext`: a required model context is missing
- `loadIssueModelContainer`: an issue occurred loading the model container
- `invalidTransactionFetchRequest`: the fetch request in a transaction is invalid
- `includePendingChangesWithBatchSize`: cannot include pending changes with a batch size
- `historyTokenExpired`: the history token has expired
- `duplicateConfiguration`: a configuration with the same name already exists
- `configurationSchemaNotFoundInContainerSchema`: a configuration's schema is not in the container's schema
- `configurationFileNameTooLong`: the configuration name exceeds the maximum length (255)
- `configurationFileNameContainsInvalidCharacters`: the configuration name contains invalid characters
- `backwardMigration`: backward migration is not supported

## Implementation

All cases are implemented with:
- `~=` pattern matching operator
- `hash(into:)`: hashes the case name
- `==`: compares cases by name

The `ModelConfiguration.validate()` method throws:
- `SwiftDataError.configurationFileNameContainsInvalidCharacters` for empty names
- `SwiftDataError.configurationFileNameTooLong` for names > 255 characters

## Verification

Tested by:
1. Throwing each error case and catching
2. Pattern matching with `~=` 
3. Comparing errors for equality
4. Hashing errors in sets/dictionaries
5. Catching errors from `ModelConfiguration.validate()`

Host differential test (macOS SwiftData vs this implementation):
- Same error cases, same pattern matching behavior
- The error domain/code may differ (macOS uses `NSError` with domain `SwiftDataErrorDomain`)

## Divergences from macOS SwiftData

- macOS SwiftData uses `NSError` with `SwiftDataErrorDomain` and integer codes; this implementation uses a Swift enum
- The error cases match the documented SwiftData errors but the underlying representation differs
- The pattern matching operator `~=` is implemented for the enum; on macOS it would be for `NSError` codes