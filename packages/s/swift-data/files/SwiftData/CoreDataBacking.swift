// The Core Data behind a model: the NSManagedObject a context owns, and the pair of untyped
// entry points every typed member of `BackingData` is a thin wrapper around.

import Foundation
import CoreData

public final class CoreDataBacking<Model: PersistentModel>: BackingData, @unchecked Sendable {
    /// The model this storage is for. Weak, because the model holds this and a cycle between them
    /// would keep a deleted row alive for as long as the process is.
    weak var owner: Model?

    let context: NSManagedObjectContext

    /// The row. Public because a model's identity in a store is this object, and a context
    /// registers models by it.
    public let object: NSManagedObject

    public var persistentModelID: PersistentIdentifier? {
        get {
            guard !object.isTemporaryID else { return nil }
            return PersistentIdentifier(object.objectID, entityName: object.entity.name ?? entityName)
        }
        set {
            if let resolved = newValue?.id.object { context.replace(object, with: resolved) }
        }
    }

    public var metadata: Any { entityName }

    public var modelContext: ModelContext? { context.modelContext }

    public var isDeleted: Bool { object.isDeleted }

    public var hasChanges: Bool { object.hasChanges }

    public required init(for modelType: Model.Type) {
        self.context = ModelContext.detachedContext()
        self.object = NSManagedObject()
    }

    init(for modelType: Model.Type, object: NSManagedObject, context: NSManagedObjectContext, owner: Model?) {
        self.context = context
        self.object = object
        self.owner = owner
    }

    public func _generateCurrentClassBackingData<CurrentClass>() -> any BackingData<CurrentClass>
    where CurrentClass: PersistentModel {
        CoreDataBacking<CurrentClass>(for: CurrentClass.self, object: object, context: context, owner: nil)
    }

    public func _superClassBackingData<SuperClass>(of givenType: any PersistentModel.Type) -> any BackingData<SuperClass>
    where SuperClass: PersistentModel {
        CoreDataBacking<SuperClass>(for: SuperClass.self, object: object, context: context, owner: owner as? SuperClass)
    }

    // MARK: The two untyped doors every typed member goes through

    func raw(_ key: String) -> Any? {
        if let set = object.value(forKey: key) as? Set<NSManagedObject> { return Array(set) }
        return object.value(forKey: key)
    }

    func write(_ key: String, _ value: Any?) {
        object.setValue(value, forKey: key)
    }

    // MARK: Reading

    @_disfavoredOverload
    public func getValue<Value>(forKey keyPath: KeyPath<Model, Value>) -> Value where Value: Decodable {
        Model.storedValue(raw(keyPath._kvcKeyPathString), for: keyPath, entity: entityName)
    }

    public func getValue<Value>(forKey keyPath: KeyPath<Model, Value>) -> Value where Value: PersistentModel {
        model(Value.self, from: raw(keyPath._kvcKeyPathString))
    }

    public func getValue<Value>(forKey keyPath: KeyPath<Model, Value?>) -> Value? where Value: PersistentModel {
        model(Value.self, from: raw(keyPath._kvcKeyPathString))
    }

    public func getValue<Value, OtherModel>(forKey keyPath: KeyPath<Model, Value>) -> Value
    where Value: RelationshipCollection, OtherModel == Value.PersistentElement {
        related(Value.self, from: raw(keyPath._kvcKeyPathString))
    }

    public func getValue<Value, OtherModel>(forKey keyPath: KeyPath<Model, Value>) -> Value
    where Value: Decodable, Value: RelationshipCollection, OtherModel == Value.PersistentElement {
        related(Value.self, from: raw(keyPath._kvcKeyPathString))
    }

    public func getTransformableValue<Value>(forKey keyPath: KeyPath<Model, Value>) -> Value {
        Model.storedValue(raw(keyPath._kvcKeyPathString), for: keyPath, entity: entityName)
    }

    // MARK: Writing

    @_disfavoredOverload
    public func setValue<Value>(forKey keyPath: KeyPath<Model, Value>, to newValue: Value) where Value: Encodable {
        write(keyPath._kvcKeyPathString, StoredValue.store(newValue))
    }

    public func setValue<Value>(forKey keyPath: KeyPath<Model, Value>, to newValue: Value) where Value: PersistentModel {
        write(keyPath._kvcKeyPathString, newValue.backingObject)
    }

    public func setValue<Value>(forKey keyPath: KeyPath<Model, Value?>, to newValue: Value?) where Value: PersistentModel {
        write(keyPath._kvcKeyPathString, newValue?.backingObject)
    }

    public func setValue<Value, OtherModel>(forKey keyPath: KeyPath<Model, Value>, to newValue: Value)
    where Value: RelationshipCollection, OtherModel == Value.PersistentElement {
        write(keyPath._kvcKeyPathString, rows(of: newValue))
    }

    public func setValue<Value, OtherModel>(forKey keyPath: KeyPath<Model, Value>, to newValue: Value)
    where Value: Encodable, Value: RelationshipCollection, OtherModel == Value.PersistentElement {
        write(keyPath._kvcKeyPathString, rows(of: newValue))
    }

    public func setTransformableValue<Value>(forKey keyPath: KeyPath<Model, Value>, to newValue: Value) {
        write(keyPath._kvcKeyPathString, StoredValue.store(newValue))
    }

    // MARK: The two conversions the typed members share

    /// A row read as a model. The model is made over the row itself, so a value read through two
    /// models of the same row is the same value - which is what Core Data does for a managed
    /// object and what a model's identity rests on.
    private func model<Value: PersistentModel>(_ type: Value.Type, from value: Any?) -> Value? {
        guard let row = value as? NSManagedObject else { return nil }
        if let registered = context.modelContext?.registeredModel(forObject: row) as? Value { return registered }
        let backing = CoreDataBacking<Value>(for: Value.self, object: row, context: context, owner: nil)
        let made = Value(backingData: backing)
        context.modelContext?.register(made, for: row)
        return made
    }

    /// A relationship read as the collection the model asked for. `RelationshipCollection` is
    /// conformed to by `Array` alone, so the collection is that, and the cast says so out loud
    /// rather than quietly returning something else.
    private func related<Value: RelationshipCollection>(_ type: Value.Type, from value: Any?) -> Value {
        var rows = [Value.PersistentElement]()
        if let one = value as? NSManagedObject {
            if let model = model(Value.PersistentElement.self, from: one) { rows.append(model) }
        }
        for row in (value as? [NSManagedObject]) ?? [] {
            if let model = model(Value.PersistentElement.self, from: row) { rows.append(model) }
        }
        guard let array = rows as? Value else {
            preconditionFailure("a relationship of \(entityName) is read as \(Value.self), " +
                                "which is not the Array its RelationshipCollection conformance is for")
        }
        return array
    }

    private func rows<Value>(of value: Value) -> [NSManagedObject]? {
        (value as? any PersistentModel)?.backingObject.map { [$0] }
            ?? (value as? any CollectionProtocol)?.compactMap { ($0 as? any PersistentModel)?.backingObject }
    }
}

extension PersistentModel {
    /// The Core Data object behind a model, or nil for a model that is in no context.
    var backingObject: NSManagedObject? {
        (persistentBackingData as? CoreDataBacking<Self>)?.object
    }

    /// What a property reads when the row has no value for it: the value `@Model` recorded as its
    /// starting one, and for the value types Core Data has a column for, that type's own zero.
    /// A property with neither is one the model declares and the store does not hold, which is
    /// said out loud with the property's name rather than answered with a value nobody chose.
    static func storedValue<Value>(_ value: Any?, for keyPath: KeyPath<Self, Value>,
                                   entity: String) -> Value {
        if let cast = StoredValue.cast(value, to: Value.self) { return cast }
        let name = keyPath._kvcKeyPathString
        for entry in schemaMetadata where entry.name == name || "\(entry.keypath)" == name {
            if let stored = StoredValue.cast(entry.defaultValue, to: Value.self) { return stored }
        }
        if let zero = StoredValue.zero(of: Value.self) { return zero }
        preconditionFailure("\(entity).\(name) has no value and no default to read")
    }
}
