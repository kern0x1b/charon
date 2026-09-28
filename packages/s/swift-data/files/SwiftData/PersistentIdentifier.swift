// PersistentIdentifier.swift
// SwiftData PersistentIdentifier implementation over Core Data for iOS 6

@preconcurrency import Foundation
import CoreData

public struct PersistentIdentifier: Codable, Equatable, Hashable, Comparable {
    public let id: UUID
    public let entityName: String
    public let storeIdentifier: String

    public init(id: UUID = UUID(), entityName: String, storeIdentifier: String = "default") {
        self.id = id
        self.entityName = entityName
        self.storeIdentifier = storeIdentifier
    }

    public init(_ managedObjectID: NSManagedObjectID) {
        self.id = UUID() // In real implementation, this would be derived from the managedObjectID
        self.entityName = managedObjectID.entity.name ?? "Unknown"
        self.storeIdentifier = managedObjectID.persistentStore?.identifier ?? "default"
    }

    public var managedObjectID: NSManagedObjectID {
        // In real implementation, this would reconstruct the NSManagedObjectID
        return NSManagedObjectID()
    }

    public static func identifier(for entityName: String, primaryKey: Any) -> PersistentIdentifier {
        return PersistentIdentifier(entityName: entityName)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(entityName)
        hasher.combine(storeIdentifier)
    }

    public static func == (lhs: PersistentIdentifier, rhs: PersistentIdentifier) -> Bool {
        lhs.id == rhs.id && lhs.entityName == rhs.entityName && lhs.storeIdentifier == rhs.storeIdentifier
    }

    public static func < (lhs: PersistentIdentifier, rhs: PersistentIdentifier) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(entityName, forKey: .entityName)
        try container.encode(storeIdentifier, forKey: .storeIdentifier)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.entityName = try container.decode(String.self, forKey: .entityName)
        self.storeIdentifier = try container.decode(String.self, forKey: .storeIdentifier)
    }

    public var debugDescription: String { "PersistentIdentifier(\(entityName): \(id))" }

    public var hashValue: Int { id.hashValue }

    private enum CodingKeys: String, CodingKey {
        case id, entityName, storeIdentifier
    }
}

public extension PersistentIdentifier {
    struct ID: Codable, Equatable, Hashable {
        public let uuid: UUID

        public init(_ uuid: UUID = UUID()) { self.uuid = uuid }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.uuid = try container.decode(UUID.self)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(uuid)
        }

        public func hash(into hasher: inout Hasher) { hasher.combine(uuid) }

        public static func == (lhs: ID, rhs: ID) -> Bool { lhs.uuid == rhs.uuid }

        public var hashValue: Int { uuid.hashValue }
    }
}

public protocol PersistentModel: AnyObject {
    static var entityName: String { get }
    var persistentModelID: PersistentIdentifier { get }
    var persistentBackingData: BackingData { get }
    var modelContext: ModelContext? { get }
    var isDeleted: Bool { get }
    var hasChanges: Bool { get }
    var schemaMetadata: Schema.PropertyMetadata? { get }

    init(backingData: BackingData)
    func getValue(forKey key: String) -> Any?
    func setValue(_ value: Any?, forKey key: String)
    func getTransformableValue(forKey key: String) -> Any?
    func setTransformableValue(_ value: Any?, forKey key: String)
    func createBackingData() -> BackingData
}

public extension PersistentModel {
    static var entityName: String { String(describing: Self.self) }
}

public struct BackingData: Codable, Equatable, Hashable {
    public let persistentModelID: PersistentIdentifier
    public let metadata: [String: String]

    public init(for modelID: PersistentIdentifier, metadata: [String: String] = [:]) {
        self.persistentModelID = modelID
        self.metadata = metadata
    }

    public func getValue(forKey key: String) -> Any? { metadata[key] }
    public func setValue(_ value: Any?, forKey key: String) -> BackingData {
        var newMetadata = metadata
        if let value = value {
            newMetadata[key] = String(describing: value)
        } else {
            newMetadata[key] = nil
        }
        return BackingData(for: persistentModelID, metadata: newMetadata)
    }
    public func getTransformableValue(forKey key: String) -> Any? { metadata[key] }
    public func setTransformableValue(_ value: Any?, forKey key: String) -> BackingData {
        var newMetadata = metadata
        if let value = value {
            newMetadata[key] = String(describing: value)
        } else {
            newMetadata[key] = nil
        }
        return BackingData(for: persistentModelID, metadata: newMetadata)
    }
}

public protocol ModelExecutor {
    var modelContext: ModelContext { get }
    func enqueue(_ job: @escaping @Sendable () -> Void)
}

public protocol ModelActor: Actor {
    var modelContainer: ModelContainer { get }
    var modelContext: ModelContext { get }
    var modelExecutor: ModelExecutor { get }
    subscript<Result>(id: PersistentIdentifier, as type: Result.Type) -> Result? { get }
}

public protocol SerialModelExecutor: ModelExecutor {
    func asUnownedSerialExecutor() -> UnownedSerialExecutor
}

public final class DefaultSerialModelExecutor: SerialModelExecutor, @unchecked Sendable {
    public let modelContext: ModelContext
    private let queue: DispatchQueue

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.queue = DispatchQueue(label: "SwiftData.ModelExecutor")
    }

    public func enqueue(_ job: @escaping @Sendable () -> Void) {
        queue.async(execute: job)
    }

    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        // Full Swift concurrency not available on iOS 6
        fatalError("UnownedSerialExecutor not available on iOS 6")
    }
}

public protocol DataStore {
    associatedtype Model: PersistentModel
    var schema: Schema { get }
    var identifier: String { get }
    var configuration: DataStoreConfiguration { get }
    func fetch(_ request: DataStoreFetchRequest<Model>) throws -> DataStoreFetchResult<Model>
    func fetchCount(_ request: DataStoreFetchRequest<Model>) throws -> Int
    func fetchIdentifiers(_ request: DataStoreFetchRequest<Model>) throws -> [PersistentIdentifier]
    func save(_ request: DataStoreSaveChangesRequest<Model>) throws -> DataStoreSaveChangesResult
    func initializeState(for configuration: DataStoreConfiguration) throws
    func invalidateState(for configuration: DataStoreConfiguration) throws
    func erase() throws
    func cachedSnapshots(for editingState: EditingState) -> [DataStoreSnapshot]
}

public protocol DataStoreConfiguration {
    var schema: Schema { get }
    var name: String { get }
    func validate() throws
}

public protocol DataStoreBatching {
    associatedtype Model: PersistentModel
    func delete(_ request: DataStoreBatchDeleteRequest<Model>) throws
}

public struct DataStoreFetchRequest<Model: PersistentModel> {
    public let descriptor: FetchDescriptor<Model>
    public let editingState: EditingState?
}

public struct DataStoreFetchResult<Model: PersistentModel> {
    public let descriptor: FetchDescriptor<Model>
    public let fetchedSnapshots: [DataStoreSnapshot]
    public let relatedSnapshots: [DataStoreSnapshot]
}

public struct DataStoreSaveChangesRequest<Model: PersistentModel> {
    public let inserted: [BackingData]
    public let updated: [BackingData]
    public let deleted: [BackingData]
    public let editingState: EditingState
}

public struct DataStoreSaveChangesResult {
    public let storeIdentifier: String
    public let snapshotsToReregister: [DataStoreSnapshot]
    public let remappedIdentifiers: [PersistentIdentifier: PersistentIdentifier]
}

public struct DataStoreBatchDeleteRequest<Model: PersistentModel> {
    public let predicate: Predicate<Model>?
    public let includeSubclasses: Bool
    public let editingState: EditingState
}

public struct DataStoreConfigurationImpl: DataStoreConfiguration {
    public let schema: Schema
    public let name: String

    public func validate() throws {
        if name.isEmpty { throw SwiftDataError.configurationFileNameContainsInvalidCharacters }
    }
}

public struct DataStoreError: Error, Equatable, Hashable {
    public static let unsupportedFeature = DataStoreError("unsupportedFeature")
    public static let preferInMemorySort = DataStoreError("preferInMemorySort")
    public static let preferInMemoryFilter = DataStoreError("preferInMemoryFilter")
    public static let invalidPredicate = DataStoreError("invalidPredicate")

    let code: String
    private init(_ code: String) { self.code = code }

    public static func == (lhs: DataStoreError, rhs: DataStoreError) -> Bool { lhs.code == rhs.code }
    public func hash(into hasher: inout Hasher) { hasher.combine(code) }
}

public struct DataStoreSnapshot: Codable, Equatable, Hashable {
    public let persistentIdentifier: PersistentIdentifier
    public let values: [String: String]

    public init(from backingData: BackingData, relatedBackingDatas: [BackingData] = []) {
        self.persistentIdentifier = backingData.persistentModelID
        self.values = backingData.metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.persistentIdentifier = try container.decode(PersistentIdentifier.self, forKey: .persistentIdentifier)
        self.values = try container.decode([String: String].self, forKey: .values)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(persistentIdentifier, forKey: .persistentIdentifier)
        try container.encode(values, forKey: .values)
    }

    public func copy(persistentIdentifier: PersistentIdentifier, remappedIdentifiers: [PersistentIdentifier: PersistentIdentifier]) -> DataStoreSnapshot {
        return DataStoreSnapshot(from: BackingData(for: persistentIdentifier, metadata: values))
    }

    private enum CodingKeys: String, CodingKey {
        case persistentIdentifier, values
    }
}

public struct DataStoreSnapshotCodingKey: CodingKey, Equatable, Hashable {
    public let stringValue: String
    public let intValue: Int?

    public init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
    public init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }

    public static let persistentIdentifier = DataStoreSnapshotCodingKey(stringValue: "persistentIdentifier")!
    public static let modeledProperty = DataStoreSnapshotCodingKey(stringValue: "modeledProperty")!
}