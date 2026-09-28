# FetchDescriptor

The `FetchDescriptor<T>` struct describes a fetch request for a persistent model type `T`. It holds:
- `predicate`: optional `Predicate<T>` for filtering
- `sortBy`: array of `SortDescriptor<T>` for ordering
- `propertiesToFetch`: optional array of property names to fetch (partial objects)
- `relationshipKeyPathsForPrefetching`: optional array of relationship key paths to prefetch
- `fetchLimit`: optional maximum number of results
- `fetchOffset`: number of results to skip (default 0)
- `includePendingChanges`: whether to include unsaved changes (default true)

## Implementation

The `fetchRequest` computed property builds an `NSFetchRequest<NSManagedObject>`:
- Entity name is `T.entityName` (from `PersistentModel` conformance)
- Predicate is set from `predicate?.nsPredicate`
- Sort descriptors are mapped from `sortBy` via `nsSortDescriptor`
- `fetchLimit`, `fetchOffset`, `includesPendingChanges` are set directly
- `propertiesToFetch` and `relationshipKeyPathsForPrefetching` are set if provided

`FetchDescriptor` is `Codable`, `Equatable`, `Hashable`, and `Sendable`.

## Nested Types

### SortDescriptor
- `keyPath`: the property key path to sort by
- `order`: `.forward` (ascending) or `.reverse` (descending)
- `nsSortDescriptor`: creates `NSSortDescriptor(key: keyPath, ascending: order == .forward)`

### SortOrder
- `.forward`: ascending
- `.reverse`: descending

### Predicate
Wraps `NSPredicate`. The `#Predicate` macro is from swift-foundation's macro package. This package provides a runtime fallback that returns a trivial predicate.

### FetchResultsCollection
A collection wrapper around `[Element]` providing:
- `startIndex`, `endIndex`
- `subscript(position:)` for random access
- `makeIterator()` for sequence conformance

## Verification

Tested by:
1. Creating descriptors with various combinations of predicate, sort, limit, offset
2. Converting to `NSFetchRequest` and verifying the request properties
3. Using descriptors with `ModelContext.fetch` and verifying results match expectations
4. Testing sort descriptors with forward/reverse order
5. Testing fetch limit and offset
6. Testing `includePendingChanges` behavior

Host differential test (macOS SwiftData vs this implementation):
- Same descriptor, same fetch, same results
- Predicate evaluation matches (using `NSPredicate` on both sides)
- Sort order matches

## Divergences from macOS SwiftData

- `propertiesToFetch` returns partial managed objects (dictionary results) rather than fully-typed models; the SwiftData layer would need to reconstruct models from partial data
- `relationshipKeyPathsForPrefetching` is passed through to Core Data but the prefetched relationships are not materialized into the model graph automatically
- The `#Predicate` macro is not in this package; predicates are built manually with `NSPredicate` or the fallback
- `FetchDescriptor` equality compares the predicate's `predicateFormat` string; two predicates with equivalent logic but different format strings are not equal