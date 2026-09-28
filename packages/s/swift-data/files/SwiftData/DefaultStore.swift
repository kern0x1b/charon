// The store: an NSPersistentStoreCoordinator, the model made from a schema, and the history the
// store keeps of what was saved.

import Foundation
import CoreData

public final class DefaultStore: DataStore, DataStoreBatching, @unchecked Sendable {
    public typealias Configuration = ModelConfiguration
    public typealias Snapshot = DefaultSnapshot
    public typealias HistoryType = DefaultHistoryTransaction
    public typealias TokenType = DefaultHistoryToken

    /// A CloudKit container is an NSPersistentContainer, so a store that names a CloudKit
    /// container is that subclass and one that names none is the base class. No release this port
    /// runs on has CloudKit, so nothing mirrors; the class is still what a store of this
    /// configuration is, and its identifier is what the configuration is asked for.
    public let name: String
    public let schema: Schema
    public let configuration: ModelConfiguration
    public let coordinator: NSPersistentStoreCoordinator
    public let container: NSPersistentContainer

    public var identifier: String { name }

    public convenience init(_ configuration: ModelConfiguration,
                            migrationPlan: (any SchemaMigrationPlan.Type)? = nil) throws {
        try self.init(configuration, migrationPlan: migrationPlan, schema: configuration.schema ?? Schema())
    }

    public init(_ configuration: ModelConfiguration, migrationPlan: (any SchemaMigrationPlan.Type)?,
                schema: Schema) throws {
        self.configuration = configuration
        self.schema = schema
        self.name = configuration.name
        let model = try DefaultStore.model(from: schema)
        if configuration.cloudKitContainerIdentifier != nil {
            self.container = NSPersistentCloudKitContainer(name: configuration.name, managedObjectModel: model)
        } else {
            self.container = NSPersistentContainer(name: configuration.name, managedObjectModel: model)
        }
        self.coordinator = container.persistentStoreCoordinator
        let description = NSPersistentStoreDescription(url: configuration.url)
        description.type = configuration.isStoredInMemoryOnly ? NSInMemoryStoreType : NSSQLiteStoreType
        // A store that keeps history says so with the key the release reads, and the history
        // tracking itself is a backport (registry/CoreData/ios11.json); without it the release
        // ignores the option and the store answers every history fetch with nothing.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        try container.loadPersistentStores(completionHandler: { _, error in
            if let error { DefaultStore.lastLoadError = error }
        })
        if let error = DefaultStore.lastLoadError {
            DefaultStore.lastLoadError = nil
            throw error
        }
        if let migrationPlan, let last = migrationPlan.schemas.last {
            try migrate(from: last, to: schema, plan: migrationPlan)
        }
    }

    /// What `loadPersistentStores` hands back, which arrives after the closure has run.
    private static var lastLoadError: Error?

    /// The Core Data model a schema describes: one entity per schema entity, one property per
    /// schema property, and the indexes the schema names. A relationship's far end is filled in
    /// after every entity exists, because Core Data needs both ends to point at something.
    static func model(from schema: Schema) throws -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        var entities = [NSEntityDescription]()
        for schemaEntity in schema.entities {
            let entity = NSEntityDescription()
            entity.name = schemaEntity.name
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
            var properties = [NSPropertyDescription]()
            for property in schemaEntity.storedProperties {
                if let relationship = property as? Schema.Relationship {
                    let description = NSRelationshipDescription()
                    description.name = relationship.name
                    description.deleteRule = DefaultStore.deleteRule(of: relationship.deleteRule)
                    if let minimum = relationship.minimumModelCount { description.minCount = minimum }
                    if let maximum = relationship.maximumModelCount { description.maxCount = maximum }
                    properties.append(description)
                } else if let attribute = property as? Schema.Attribute {
                    properties.append(DefaultStore.attribute(from: attribute))
                }
            }
            entity.properties = properties
            entities.append(entity)
        }
        model.entities = entities
        // The far ends, now that every entity has a description to point at.
        for (index, schemaEntity) in schema.entities.enumerated() {
            for property in schemaEntity.relationships {
                guard let relationship = property as? Schema.Relationship,
                      let description = entities[index].relationshipsByName[relationship.name]
                else { continue }
                description.destinationEntity = entities.first { $0.name == relationship.destination }
                    ?? entities[index]
            }
        }
        for (index, schemaEntity) in schema.entities.enumerated() {
            let indexes = schemaEntity.indices.map { names in
                NSFetchIndexDescription(name: names.joined(separator: "_"),
                                        elements: names.map { name in
                                            guard let property = entities[index].propertiesByName[name]
                                            else { return NSFetchIndexElementDescription(property: NSAttributeDescription(),
                                                                                          collationType: .binary) }
                                            return NSFetchIndexElementDescription(property: property, collationType: .binary)
                                        })
            }
            if !indexes.isEmpty { entities[index].indexes = indexes }
        }
        if model.entities.contains(where: { $0.properties.isEmpty }) {
            throw SwiftDataError.modelValidationFailure
        }
        return model
    }

    /// One schema attribute as a Core Data attribute. The type is the one the Swift value has, by
    /// the table in `AttributeMapping`; a value with no column of its own - a struct, an array, a
    /// `UUID`, a `URL` on a release whose `NSUUIDAttributeType` is iOS 11 and later - is stored as
    /// the transformable Core Data has had since iOS 3.0, which keeps the type.
    static func attribute(from attribute: Schema.Attribute) -> NSAttributeDescription {
        let description = NSAttributeDescription()
        description.name = attribute.name
        description.attributeType = AttributeMapping.coreDataType(of: attribute.valueType,
                                                                  transformable: attribute.isTransformable)
        description.isOptional = attribute.isOptional
        if let defaultValue = attribute.defaultValue { description.defaultValue = StoredValue.store(defaultValue) }
        if let name = attribute.transformerName { description.valueTransformerName = name }
        if attribute.options.contains(.externalStorage) { description.allowsExternalBinaryDataStorage = true }
        return description
    }

    static func deleteRule(of rule: Schema.Relationship.DeleteRule) -> NSDeleteRule {
        switch rule {
        case .noAction: return .noActionDeleteRule
        case .nullify: return .nullifyDeleteRule
        case .cascade: return .cascadeDeleteRule
        case .deny: return .denyDeleteRule
        }
    }

    /// A store that is already at the schema it is opened with has nothing to migrate.
    private func migrate(from last: any VersionedSchema.Type, to schema: Schema,
                          plan: any SchemaMigrationPlan.Type) throws {
        let target = Schema(versionedSchema: last)
        guard target != schema else { return }
        let mapping = NSMappingModel.inferredMappingModel(forSourceModel: try Self.model(from: target),
                                                          destinationModel: try Self.model(from: schema))
        // The release's own signature takes the file the store is migrated to, not a store: a
        // migration writes a new file and the old one is removed by the caller, which is why
        // this one is migrated into a temporary name and back.
        // The release's own signature takes the file a store is migrated to, not a store: a
        // migration writes a new file, so the store is migrated beside itself and the result put
        // in its place. `inferredMappingModel` is optional and answers nil when it finds no
        // mapping, which is the store being already at the schema it is opened with.
        if let mapping, let store = coordinator.persistentStores.first, let url = store.url {
            let moved = url.deletingLastPathComponent()
                .appendingPathComponent(url.lastPathComponent + ".migrating")
            try coordinator.migratePersistentStore(store, to: moved, options: nil, withType: NSSQLiteStoreType)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: moved)
        }
        for stage in plan.stages {
            switch stage {
            case .lightweight:
                break
            case .custom(_, _, let willMigrate, let didMigrate):
                // A custom stage's two closures are handed a context over the store being
                // migrated, so that what they change is what the migration writes.
                let container = ModelContainer(self, schema: schema)
                try willMigrate?(ModelContext(container))
                try didMigrate?(ModelContext(container))
            }
        }
    }

    /// The entity a model type is stored as, in this store's model.
    public func entityDescription(for name: String) -> NSEntityDescription {
        coordinator.managedObjectModel.entitiesByName[name]
            ?? NSEntityDescription()
    }

    /// Which Swift type an entity holds, as far as this store has been told. A model type is
    /// recorded here the first time a row of its entity is read as that model, which is the only
    /// place the type is statically known; the schema holds the entities and this holds the types
    /// the rows of each have been read as.
    private var modelTypes: [String: any PersistentModel.Type] = [:]

    func remember<T>(_ type: T.Type, for entityName: String) where T: PersistentModel {
        modelTypes[entityName] = type
    }

    public func modelType(for entityName: String) -> (any PersistentModel.Type)? {
        modelTypes[entityName]
    }

    // MARK: The DataStore

    public func erase() throws {
        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }
        try container.loadPersistentStores(completionHandler: { _, error in
            if let error { DefaultStore.lastLoadError = error }
        })
        if let error = DefaultStore.lastLoadError { throw error }
    }

    public func fetch<T>(_ request: DataStoreFetchRequest<T>) throws -> DataStoreFetchResult<T, DefaultSnapshot>
    where T: PersistentModel {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let rows = NSFetchRequest<NSManagedObject>(entityName: Schema.entityName(for: T.self))
        rows.includesPendingChanges = request.descriptor.includePendingChanges
        var snapshots = [DefaultSnapshot]()
        for row in try context.fetch(rows) where !row.objectID.isTemporaryID {
            let backing = CoreDataBacking<T>(for: T.self, object: row, context: context, owner: nil)
            var related = [PersistentIdentifier: any BackingData<T>]()
            snapshots.append(DefaultSnapshot(from: backing, relatedBackingDatas: &related))
        }
        return DataStoreFetchResult(descriptor: request.descriptor, fetchedSnapshots: snapshots)
    }

    public func save(_ request: DataStoreSaveChangesRequest<DefaultSnapshot>) throws
    -> DataStoreSaveChangesResult<DefaultSnapshot> {
        // A context holds the rows; a save of snapshots is a context's own save, which the
        // context does. What a store has to answer is which identities changed.
        var remapped = [PersistentIdentifier: PersistentIdentifier]()
        for snapshot in request.inserted + request.updated where snapshot.persistentIdentifier.id.object == nil {
            remapped[snapshot.persistentIdentifier] = snapshot.persistentIdentifier
        }
        return DataStoreSaveChangesResult(for: identifier, remappedIdentifiers: remapped)
    }

    public func delete<T>(_ request: DataStoreBatchDeleteRequest<T>) throws where T: PersistentModel {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: Schema.entityName(for: T.self))
        let delete = NSBatchDeleteRequest(fetchRequest: fetch)
        delete.resultType = .resultTypeObjectIDs
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        try context.execute(delete)
    }

    /// The uniqueness constraints the schema names, checked against the rows of the store. The
    /// store of the port cannot enforce them - `NSEntityDescription.uniquenessConstraints` is
    /// registered `absent` for iOS 6 - so this is where they are checked, and a duplicate is
    /// refused rather than written.
    func checkUniqueness(in context: ModelContext) throws {
        for schemaEntity in schema.entities where !schemaEntity.uniquenessConstraints.isEmpty {
            for constraint in schemaEntity.uniquenessConstraints {
                let request = NSFetchRequest<NSManagedObject>(entityName: schemaEntity.name)
                request.includesPendingChanges = true
                var seen = [String: NSManagedObject]()
                for row in try context.context.fetch(request) {
                    let key = constraint.map { name in
                        String(describing: row.value(forKey: name) ?? NSNull())
                    }.joined(separator: "\u{1}")
                    if let first = seen[key], first !== row {
                        // A uniqueness constraint the store of the port cannot enforce, broken.
                        // `NSEntityDescription.uniquenessConstraints` is registered `absent` for
                        // iOS 6, and `NSConstraintConflict` is an Objective-C class this module
                        // cannot throw, so the refusal is a Swift error that carries both the
                        // constraint that was broken and Core Data's own value for the conflict.
                        let conflict = NSConstraintConflict(constraint: constraint, databaseObject: row,
                                                            databaseSnapshot: nil,
                                                            conflictingObjects: [first, row],
                                                            conflictingSnapshots: [])
                        throw UniquenessViolation(entity: schemaEntity.name, constraint: constraint,
                                                  conflict: conflict)
                    }
                    seen[key] = row
                }
            }
        }
    }
}

/// The Core Data type a Swift value is stored as. The table is the whole of it, and a type with
/// no row in it is transformable, which is the one type that can hold anything: what the value
/// *is* is kept by the transformer or, with none, by `NSCoding`.
enum AttributeMapping {
    static func coreDataType(of type: any Any.Type, transformable: Bool) -> NSAttributeType {
        if transformable { return .transformableAttributeType }
        switch type {
        case is String.Type, is Substring.Type: return .stringAttributeType
        case is Int.Type, is Int64.Type, is Int32.Type, is Int16.Type, is Int8.Type: return .integer64AttributeType
        case is UInt.Type, is UInt64.Type, is UInt32.Type, is UInt16.Type, is UInt8.Type: return .integer64AttributeType
        case is Double.Type, is Float.Type: return .doubleAttributeType
        case is Bool.Type: return .booleanAttributeType
        case is Date.Type: return .dateAttributeType
        case is Data.Type: return .binaryDataAttributeType
        case is Decimal.Type: return .decimalAttributeType
        default: return .transformableAttributeType
        }
    }
}

/// A uniqueness constraint the store of the port cannot enforce, broken. `NSEntityDescription.
/// uniquenessConstraints` is registered `absent` for iOS 6, and `NSConstraintConflict` is an
/// Objective-C class this module cannot throw, so the refusal is a Swift error that carries both
/// the constraint that was broken and Core Data's own value for the conflict.
public struct UniquenessViolation: Error {
    public let entity: String
    public let constraint: [String]
    public let conflict: NSConstraintConflict
}
