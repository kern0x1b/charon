// ModelContext.swift
// SwiftData ModelContext implementation over Core Data for iOS 6

@preconcurrency import Foundation
import CoreData

public final class ModelContext: @unchecked Sendable {
    public internal(set) var container: ModelContainer!
    public var autosaveEnabled: Bool = true
    public var undoManager: UndoManager?
    public var author: TransactionAuthor?
    
    public var hasChanges: Bool { context.hasChanges }
    public var insertedModelsArray: [any PersistentModel] { [] }
    public var deletedModelsArray: [any PersistentModel] { context.deletedObjects.compactMap { $0 as? any PersistentModel } }
    public var changedModelsArray: [any PersistentModel] { context.updatedObjects.compactMap { $0 as? any PersistentModel } }
    public var editingState: EditingState { EditingState(author: author) }
    
    public let context: NSManagedObjectContext
    public var willSave: NSNotification.Name { NSNotification.Name.NSManagedObjectContextWillSave }
    public var didSave: NSNotification.Name { NSNotification.Name.NSManagedObjectContextDidSave }
    
    public struct NotificationKey: RawRepresentable, Sendable, Hashable, Equatable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        
        public static let updatedIdentifiers = NotificationKey(rawValue: "updatedIdentifiers")
        public static let queryGeneration = NotificationKey(rawValue: "queryGeneration")
        public static let invalidatedAllIdentifiers = NotificationKey(rawValue: "invalidatedAllIdentifiers")
        public static let insertedIdentifiers = NotificationKey(rawValue: "insertedIdentifiers")
        public static let deletedIdentifiers = NotificationKey(rawValue: "deletedIdentifiers")
    }
    
    public init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    public func setContainer(_ container: ModelContainer) {
        self.container = container
        if context.persistentStoreCoordinator == nil {
            context.persistentStoreCoordinator = container.persistentStoreCoordinatorForContext
        }
    }

    public func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
        let request = descriptor.fetchRequest
        let results = try context.fetch(request)
        return results.compactMap { $0 as? T }
    }

    public func fetch(_ descriptor: FetchDescriptor<some PersistentModel>) throws -> [any PersistentModel] {
        let request = descriptor.fetchRequest
        let results = try context.fetch(request)
        return results.compactMap { $0 as? any PersistentModel }
    }

    public func fetch(_ request: NSFetchRequest<NSManagedObject>) throws -> [NSManagedObject] {
        return try context.fetch(request)
    }

    public func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>, batchSize: Int) throws -> [T] {
        var descriptor = descriptor
        descriptor.fetchLimit = batchSize
        return try fetch(descriptor)
    }

    public func fetchCount<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> Int {
        let request = descriptor.fetchRequest
        request.resultType = .countResultType
        let results = try context.fetch(request)
        return (results.first as? NSNumber)?.intValue ?? 0
    }

    public func fetchIdentifiers(_ descriptor: FetchDescriptor<some PersistentModel>) throws -> [PersistentIdentifier] {
        let request = descriptor.fetchRequest
        request.resultType = .managedObjectIDResultType
        let objectIDs = try context.fetch(request) as? [NSManagedObjectID] ?? []
        return objectIDs.map { PersistentIdentifier($0) }
    }

    public func fetchIdentifiers(_ descriptor: FetchDescriptor<some PersistentModel>, batchSize: Int) throws -> [PersistentIdentifier] {
        var descriptor = descriptor
        descriptor.fetchLimit = batchSize
        return try fetchIdentifiers(descriptor)
    }

    public func fetchHistory(_ descriptor: HistoryDescriptor) throws -> [HistoryTransaction] {
        return []
    }

    public func deleteHistory(_ descriptor: HistoryDescriptor) throws {
    }

    public func enumerate<T: PersistentModel>(_ descriptor: FetchDescriptor<T>, batchSize: Int = 20, allowEscapingMutations: Bool = false, block: (T) throws -> Void) throws {
        let request = descriptor.fetchRequest
        request.fetchBatchSize = batchSize
        let results = try context.fetch(request)
        for object in results {
            if let model = object as? T {
                try block(model)
            }
        }
    }

    public func insert(_ model: any PersistentModel) {
        if let managedObject = model as? NSManagedObject {
            context.insert(managedObject)
        }
    }

    public func delete(_ model: any PersistentModel) {
        if let managedObject = model as? NSManagedObject {
            context.delete(managedObject)
        }
    }

    public func delete<T: PersistentModel>(model: T.Type, where predicate: Predicate<T>?, includeSubclasses: Bool = true) throws {
        let descriptor = FetchDescriptor<T>(predicate: predicate)
        let models: [T] = try fetch(descriptor)
        for model in models {
            delete(model)
        }
    }

    public func save() throws {
        try context.save()
    }

    public func rollback() {
        context.rollback()
    }

    public func processPendingChanges() {
        context.processPendingChanges()
    }

    public func registeredModel(for identifier: PersistentIdentifier) -> (any PersistentModel)? {
        return context.object(with: identifier.managedObjectID) as? any PersistentModel
    }

    public func model<T: PersistentModel>(for identifier: PersistentIdentifier) -> T? {
        return registeredModel(for: identifier) as? T
    }

    public func transaction(block: () throws -> Void) throws {
        var error: Error?
        context.performAndWait {
            do {
                try block()
            } catch let e {
                error = e
            }
        }
        if let error = error {
            throw error
        }
    }

    public static func == (lhs: ModelContext, rhs: ModelContext) -> Bool {
        return lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

public struct EditingState: Equatable, Hashable {
    public let id: UUID
    public let author: TransactionAuthor?

    public init(author: TransactionAuthor? = nil) {
        self.id = UUID()
        self.author = author
    }
}

public struct TransactionAuthor: Equatable, Hashable {
    public let name: String
    public init(_ name: String) { self.name = name }
}

public struct HistoryDescriptor: Equatable, Hashable {
    public let predicate: Predicate<HistoryTransaction>?
    public let sortBy: [SortDescriptor<HistoryTransaction>]
    public let fetchLimit: Int?

    public init(predicate: Predicate<HistoryTransaction>? = nil, sortBy: [SortDescriptor<HistoryTransaction>] = [], fetchLimit: Int? = nil) {
        self.predicate = predicate
        self.sortBy = sortBy
        self.fetchLimit = fetchLimit
    }

    public init(predicate: Predicate<HistoryTransaction>?) {
        self.predicate = predicate
        self.sortBy = []
        self.fetchLimit = nil
    }
}

public struct HistoryTransaction: Equatable, Hashable {
    public let transactionIdentifier: UUID
    public let token: HistoryToken
    public let timestamp: Date
    public let storeIdentifier: String
    public let changes: [HistoryChange]
    public let author: TransactionAuthor?
}

public protocol HistoryProviding {
    associatedtype HistoryType
    func fetchHistory(_ descriptor: HistoryDescriptor) throws -> [HistoryType]
    func deleteHistory(_ descriptor: HistoryDescriptor) throws
}

public enum HistoryChange: Equatable, Hashable {
    case insert, update, delete
}

public struct HistoryToken: Equatable, Hashable {
    public let tokenValue: Data
    public init(tokenValue: Data) { self.tokenValue = tokenValue }
}

public protocol HistoryTransactionProtocol {
    var transactionIdentifier: UUID { get }
    var token: HistoryToken { get }
    var timestamp: Date { get }
    var storeIdentifier: String { get }
    var changes: [HistoryChange] { get }
    var author: TransactionAuthor? { get }
}

public protocol HistoryTokenProtocol {
    var tokenValue: Data { get }
}

public protocol HistoryInsert {
    var transactionIdentifier: UUID { get }
    var changedPersistentIdentifier: PersistentIdentifier { get }
    var changeIdentifier: UUID { get }
}

public protocol HistoryDelete {
    var transactionIdentifier: UUID { get }
    var changedPersistentIdentifier: PersistentIdentifier { get }
    var changeIdentifier: UUID { get }
    var tombstone: HistoryTombstone { get }
}

public protocol HistoryUpdate {
    var transactionIdentifier: UUID { get }
    var changedPersistentIdentifier: PersistentIdentifier { get }
    var changeIdentifier: UUID { get }
    var updatedAttributes: [String] { get }
}

public struct HistoryTombstone: Equatable, Hashable {
    private let values: [String: String]
    
    public subscript(keyPath: String) -> String? {
        return values[keyPath]
    }
    
    public func makeIterator() -> Iterator {
        return Iterator(values: values)
    }
    
    public struct Iterator: IteratorProtocol {
        private let values: [String: String]
        private var index = 0
        private let keys: [String]
        
        init(values: [String: String]) {
            self.values = values
            self.keys = Array(values.keys)
        }
        
        public mutating func next() -> (String, String)? {
            guard index < keys.count else { return nil }
            let key = keys[index]
            index += 1
            return (key, values[key] ?? "")
        }
    }
}