// FetchDescriptor.swift
// SwiftData FetchDescriptor implementation over Core Data for iOS 6

@preconcurrency import Foundation
import CoreData

public struct FetchDescriptor<T: PersistentModel>: Equatable, Hashable {
    public let predicate: Predicate<T>?
    public let sortBy: [SortDescriptor<T>]
    public let propertiesToFetch: [String]?
    public let relationshipKeyPathsForPrefetching: [String]?
    public var fetchLimit: Int?
    public var fetchOffset: Int
    public let includePendingChanges: Bool

    public init(
        predicate: Predicate<T>? = nil,
        sortBy: [SortDescriptor<T>] = [],
        propertiesToFetch: [String]? = nil,
        relationshipKeyPathsForPrefetching: [String]? = nil,
        fetchLimit: Int? = nil,
        fetchOffset: Int = 0,
        includePendingChanges: Bool = true
    ) {
        self.predicate = predicate
        self.sortBy = sortBy
        self.propertiesToFetch = propertiesToFetch
        self.relationshipKeyPathsForPrefetching = relationshipKeyPathsForPrefetching
        self.fetchLimit = fetchLimit
        self.fetchOffset = fetchOffset
        self.includePendingChanges = includePendingChanges
    }

    public init(predicate: Predicate<T>?, sortBy: [SortDescriptor<T>]) {
        self.predicate = predicate
        self.sortBy = sortBy
        self.propertiesToFetch = nil
        self.relationshipKeyPathsForPrefetching = nil
        self.fetchLimit = nil
        self.fetchOffset = 0
        self.includePendingChanges = true
    }

    public static func == (lhs: FetchDescriptor<T>, rhs: FetchDescriptor<T>) -> Bool {
        lhs.predicate == rhs.predicate && lhs.sortBy == rhs.sortBy && lhs.fetchLimit == rhs.fetchLimit && lhs.fetchOffset == rhs.fetchOffset && lhs.includePendingChanges == rhs.includePendingChanges
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(predicate)
        hasher.combine(sortBy)
        hasher.combine(fetchLimit)
        hasher.combine(fetchOffset)
        hasher.combine(includePendingChanges)
    }

    internal var fetchRequest: NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: T.entityName)
        if let predicate = predicate {
            request.predicate = predicate.nsPredicate
        }
        request.sortDescriptors = sortBy.map { $0.nsSortDescriptor }
        if let limit = fetchLimit { request.fetchLimit = limit }
        if fetchOffset > 0 { request.fetchOffset = fetchOffset }
        request.includesPendingChanges = includePendingChanges
        if let properties = propertiesToFetch { request.propertiesToFetch = properties }
        if let prefetch = relationshipKeyPathsForPrefetching { request.relationshipKeyPathsForPrefetching = prefetch }
        return request
    }
}

public struct SortDescriptor<Root>: Sendable, Codable, Equatable, Hashable {
    public let keyPath: String
    public let order: SortOrder

    public init(keyPath: String, order: SortOrder = .forward) {
        self.keyPath = keyPath
        self.order = order
    }

    public var nsSortDescriptor: NSSortDescriptor {
        NSSortDescriptor(key: keyPath, ascending: order == .forward)
    }
}

public enum SortOrder: Sendable, Codable, Equatable, Hashable {
    case forward, reverse
}

public struct Predicate<Root>: Equatable, Hashable {
    internal let nsPredicate: NSPredicate

    public init(_ build: () -> NSPredicate) {
        self.nsPredicate = build()
    }

    public static func == (lhs: Predicate<Root>, rhs: Predicate<Root>) -> Bool {
        lhs.nsPredicate.isEqual(rhs.nsPredicate)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(nsPredicate.predicateFormat)
    }
}

public struct FetchResultsCollection<Element: PersistentModel>: Sequence {
    public let models: [Element]
    public var startIndex: Int { models.startIndex }
    public var endIndex: Int { models.endIndex }
    public typealias Index = Int
    public typealias SubSequence = ArraySlice<Element>
    public typealias Iterator = IndexingIterator<[Element]>

    public init(models: [Element]) {
        self.models = models
    }

    public subscript(position: Int) -> Element {
        models[position]
    }

    public func makeIterator() -> Iterator {
        models.makeIterator()
    }
}