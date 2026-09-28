// What to read out of a store: which rows, in what order, how many.
//
// The predicate and the sort order are not here: they are `Foundation.Predicate` and
// `Foundation.SortDescriptor`, which are Foundation's rows (`swiftlang/swift-foundation:
// Sources/FoundationEssentials/Predicate/Predicate.swift`, `owner-registry = swift-foundation` in
// the corpus) and which the port's Foundation has not yet - `Predicate` and `SortDescriptor` are
// declared in neither the runtime's Foundation overlay nor the device's Foundation.framework, and
// `packages/s/swift-foundation` is not in the shared store. `FetchDescriptor.init(predicate:
// sortBy:)`, `.predicate`, `.sortBy`, `DataStoreBatchDeleteRequest.predicate` and
// `HistoryDescriptor.predicate`/`.sortBy` are therefore not in this delivery, and the eight rows
// are registered `missing` with that reason. Everything else a descriptor holds is here, and
// `init()` takes no arguments, so a fetch of every row of an entity works today.

import Foundation

public struct FetchDescriptor<T> where T: PersistentModel {
    /// How many rows to read, and how many to skip before the first. Both are the store's own
    /// limits, applied where the store applies them.
    public var fetchLimit: Int?
    public var fetchOffset: Int?

    /// Whether the rows this context has changed but not saved are in the answer. `true` is what
    /// `NSFetchRequest.includesPendingChanges` means, and the release has had it since iOS 3.0.
    public var includePendingChanges: Bool

    /// The properties to read: a row comes back with these, and the rest fault, which is what
    /// Core Data does with a row whose columns were not fetched.
    public var propertiesToFetch: [PartialKeyPath<T>]

    /// The relationships to bring in with the row.
    public var relationshipKeyPathsForPrefetching: [PartialKeyPath<T>]

    public init() {
        self.fetchLimit = nil
        self.fetchOffset = nil
        self.includePendingChanges = true
        self.propertiesToFetch = []
        self.relationshipKeyPathsForPrefetching = []
    }
}

extension FetchDescriptor: Equatable {
    public static func == (lhs: FetchDescriptor<T>, rhs: FetchDescriptor<T>) -> Bool {
        lhs.fetchLimit == rhs.fetchLimit && lhs.fetchOffset == rhs.fetchOffset
            && lhs.includePendingChanges == rhs.includePendingChanges
            && lhs.propertiesToFetch.map { "\($0)" } == rhs.propertiesToFetch.map { "\($0)" }
            && lhs.relationshipKeyPathsForPrefetching.map { "\($0)" }
                == rhs.relationshipKeyPathsForPrefetching.map { "\($0)" }
    }
}

extension FetchDescriptor: @unchecked Sendable {}

/// A page of a fetch, so that a program can walk a store's rows without holding them all. A
/// `RandomAccessCollection` over one page, which is what it is.
public struct FetchResultsCollection<Element>: RandomAccessCollection {
    public typealias Index = Int
    public typealias Indices = Range<Int>
    public typealias Iterator = IndexingIterator<FetchResultsCollection<Element>>
    public typealias SubSequence = Slice<FetchResultsCollection<Element>>

    public var startIndex: Int { 0 }
    public var endIndex: Int { elements.count }
    public subscript(position: Int) -> Element { elements[position] }

    let elements: [Element]

    init(_ elements: [Element]) {
        self.elements = elements
    }
}
