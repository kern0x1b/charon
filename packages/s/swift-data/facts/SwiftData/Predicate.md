# Predicate

The `Predicate<Root>` struct wraps an `NSPredicate` for type-safe predicate construction. It is `Sendable`, `Equatable`, and `Hashable`.

## Implementation

The `Predicate` holds an internal `nsPredicate: NSPredicate` and provides:
- `init(_ build: () -> NSPredicate)`: creates a predicate from a closure
- `==`: compares predicates via `nsPredicate.isEqual`
- `hash(into:)`: hashes the `predicateFormat` string

The `#Predicate` macro (from swift-foundation's macro package) transforms a closure like `#Predicate<Model> { $0.name == "test" }` into a `Predicate<Model>` with the equivalent `NSPredicate`. This package provides a runtime fallback that returns a trivial predicate (always true).

## Verification

Tested by:
1. Creating predicates manually with `NSPredicate`
2. Wrapping in `Predicate` and using in `FetchDescriptor`
3. Executing fetches with predicates and verifying results
4. Comparing predicates for equality

Host differential test (macOS SwiftData vs this implementation):
- Same `NSPredicate` construction, same fetch results
- The `#Predicate` macro on macOS produces the same `NSPredicate` as manual construction here

## Divergences from macOS SwiftData

- The `#Predicate` macro is not in this package; predicates must be built manually with `NSPredicate`
- The fallback `#Predicate` returns a trivial predicate; it does not parse the closure
- `Predicate` equality compares `predicateFormat` strings; semantically equivalent predicates with different formats are not equal
- The `Predicate` struct is a simple wrapper; the macOS version may have additional API (e.g., `evaluate(with:)`)