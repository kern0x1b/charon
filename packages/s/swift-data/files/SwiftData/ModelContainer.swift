// ModelContainer.swift
// SwiftData ModelContainer implementation over Core Data for iOS 6

@preconcurrency import Foundation
import CoreData

public final class ModelContainer: @unchecked Sendable {
    public let schema: Schema
    public let configurations: [ModelConfiguration]
    public let mainContext: ModelContext
    public private(set) var migrationPlan: (any SchemaMigrationPlan)?

    private let persistentStoreCoordinator: NSPersistentStoreCoordinator
    private let managedObjectModel: NSManagedObjectModel
    private var contexts: [ModelContext] = []
    
    internal var persistentStoreCoordinatorForContext: NSPersistentStoreCoordinator {
        return persistentStoreCoordinator
    }

    private init(
        schema: Schema,
        migrationPlan: (any SchemaMigrationPlan)?,
        configurations: [ModelConfiguration],
        managedObjectModel: NSManagedObjectModel,
        persistentStoreCoordinator: NSPersistentStoreCoordinator,
        mainContext: ModelContext,
        contexts: [ModelContext]
    ) {
        self.schema = schema
        self.migrationPlan = migrationPlan
        self.configurations = configurations
        self.managedObjectModel = managedObjectModel
        self.persistentStoreCoordinator = persistentStoreCoordinator
        self.mainContext = mainContext
        self.contexts = contexts
    }

    public static func create(
        for types: [any PersistentModel.Type],
        migrationPlan: (any SchemaMigrationPlan)? = nil,
        configurations: [ModelConfiguration] = []
    ) throws -> ModelContainer {
        let schema = Schema(types)
        let configs = configurations.isEmpty ? [ModelConfiguration("default", schema: schema)] : configurations
        
        let managedObjectModel = schema.managedObjectModel
        let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
        
        for config in configs {
            let storeType = config.isStoredInMemoryOnly ? NSInMemoryStoreType : NSSQLiteStoreType
            _ = try persistentStoreCoordinator.addPersistentStore(
                ofType: storeType,
                configurationName: nil,
                at: config.url,
                options: nil
            )
        }
        
        let viewContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        viewContext.persistentStoreCoordinator = persistentStoreCoordinator
        let mainContext = ModelContext(context: viewContext)
        let contexts = [mainContext]
        
        let container = ModelContainer(
            schema: schema,
            migrationPlan: migrationPlan,
            configurations: configs,
            managedObjectModel: managedObjectModel,
            persistentStoreCoordinator: persistentStoreCoordinator,
            mainContext: mainContext,
            contexts: contexts
        )
        
        mainContext.setContainer(container)
        
        return container
    }

    public func erase() throws {
        for store in persistentStoreCoordinator.persistentStores {
            let url = store.url
            if let url = url, !configurations.contains(where: { $0.url == url && $0.isStoredInMemoryOnly }) {
                try persistentStoreCoordinator.remove(store)
            }
        }
    }

    public func deleteAllData() throws {
        for entity in schema.entities {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entity.name)
            let objects = try mainContext.context.fetch(fetchRequest)
            for object in objects {
                mainContext.context.delete(object)
            }
        }
        try mainContext.context.save()
    }

    public func newBackgroundContext() -> ModelContext {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = persistentStoreCoordinator
        let modelContext = ModelContext(context: context)
        modelContext.setContainer(self)
        contexts.append(modelContext)
        return modelContext
    }

    public static func == (lhs: ModelContainer, rhs: ModelContainer) -> Bool {
        return lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

extension Schema {
    var managedObjectModel: NSManagedObjectModel {
        let model = NSManagedObjectModel()
        var entities: [NSEntityDescription] = []
        
        for entity in self.entities {
            let entityDescription = NSEntityDescription()
            entityDescription.name = entity.name
            entityDescription.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
            
            var properties: [NSPropertyDescription] = []
            
            for attribute in entity.attributes {
                let attr = NSAttributeDescription()
                attr.name = attribute.name
                attr.attributeType = attribute.coreDataAttributeType
                attr.isOptional = attribute.isOptional
                attr.isTransient = attribute.isTransient
                properties.append(attr)
            }
            
            for relationship in entity.relationships {
                let rel = NSRelationshipDescription()
                rel.name = relationship.name
                rel.destinationEntity = entities.first { $0.name == relationship.destination }
                rel.minCount = relationship.minimumModelCount
                rel.maxCount = relationship.maximumModelCount
                rel.deleteRule = relationship.deleteRule.coreDataDeleteRule
                properties.append(rel)
            }
            
            entityDescription.properties = properties
            entities.append(entityDescription)
        }
        
        model.entities = entities
        return model
    }
}

extension Schema.Attribute {
    var coreDataAttributeType: NSAttributeType {
        switch valueType {
        case "String", "NSString": return .stringAttributeType
        case "Int", "Int64", "Int32", "Int16": return .integer64AttributeType
        case "Double", "Float": return .doubleAttributeType
        case "Bool": return .booleanAttributeType
        case "Date": return .dateAttributeType
        case "Data": return .binaryDataAttributeType
        case "UUID": return .stringAttributeType // UUID stored as string on iOS 6
        case "Decimal": return .decimalAttributeType
        default: return .stringAttributeType
        }
    }
}

extension Schema.Relationship.DeleteRule {
    var coreDataDeleteRule: NSDeleteRule {
        switch self {
        case .nullify: return .nullifyDeleteRule
        case .cascade: return .cascadeDeleteRule
        case .deny: return .denyDeleteRule
        case .noAction: return .noActionDeleteRule
        }
    }
}