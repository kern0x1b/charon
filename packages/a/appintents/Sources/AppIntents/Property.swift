// The property of an entity an intent can be asked about, and the modifiers such a property carries.

import Foundation

/// A property of an entity, which is a parameter of the intent that asks about it. It is a property
/// wrapper of its own: an entity writes `@Parameter(title: "Rating") var rating: Double`, and the
/// query reads the parameter the wrapper holds.
@propertyWrapper
public struct EntityProperty<Value>: @unchecked Sendable where Value: _IntentValue {
    /// The value the property holds, and the name the index knows it by.
    public var wrappedValue: Value
    public var projectedValue: EntityProperty<Value> { return self }

    /// The name the property is indexed and searched under.
    public var indexingKey: String
    /// The name the property is shown with.
    public var title: LocalizedStringResource
    /// Whether the property may have no value.
    public var isOptional: Bool
    /// What the property's name is, as the index stores it.
    public var identifier: String
    /// The modifiers the property carries, added in iOS 26.
    public var modifiers: EntityPropertyModifiers
    /// Whether the property is only read and never written by an intent.
    public var isReadOnly: Bool
    /// The getter the property is read with, which a property that is indexed asynchronously uses.
    public var getter: ((EntityProperty<Value>) async -> Value)?
    /// The setter the property is written with.
    public var setter: ((Value) async -> Void)?

    public init() {
        self.wrappedValue = CharonEmptyValue() as! Value
        self.indexingKey = ""
        self.title = LocalizedStringResource("")
        self.isOptional = true
        self.identifier = ""
        self.modifiers = []
        self.isReadOnly = false
        self.getter = nil
        self.setter = nil
    }

    public init(title: LocalizedStringResource) {
        self.init()
        self.title = title
        self.indexingKey = title.localizedString()
        self.isOptional = false
    }

    public init(title: LocalizedStringResource, indexingKey: String) {
        self.init(title: title)
        self.indexingKey = indexingKey
    }

    public init(title: LocalizedStringResource, customIndexingKey: String) {
        self.init(title: title)
        self.indexingKey = customIndexingKey
    }


    public init(customIndexingKey: String) {
        self.init()
        self.indexingKey = customIndexingKey
    }

    public init(indexingKey: String) {
        self.init()
        self.indexingKey = indexingKey
    }

    public init(identifier: String) {
        self.init()
        self.identifier = identifier
        self.indexingKey = identifier
    }

    public init(identifier: String, title: LocalizedStringResource) {
        self.init(identifier: identifier)
        self.title = title
    }

    public init(identifier: String, title: LocalizedStringResource, indexingKey: String) {
        self.init(identifier: identifier, title: title)
        self.indexingKey = indexingKey
    }

    public init(identifier: String, title: LocalizedStringResource, indexingKey: String,
                customIndexingKey: String) {
        self.init(identifier: identifier, title: title)
        self.indexingKey = customIndexingKey
    }

    public init(identifier: String, title: LocalizedStringResource, customIndexingKey: String) {
        self.init(identifier: identifier, title: title)
        self.indexingKey = customIndexingKey
    }

    public init(identifier: String, title: LocalizedStringResource, customIndexingKey: String, indexingKey: String) {
        self.init(identifier: identifier, title: title)
        self.indexingKey = indexingKey
    }

    public init(identifier: String, customIndexingKey: String) {
        self.init(identifier: identifier)
        self.indexingKey = customIndexingKey
    }

    public init(identifier: String, indexingKey: String) {
        self.init(identifier: identifier)
        self.indexingKey = indexingKey
    }

    public init(identifier: String, customIndexingKey: String, indexingKey: String) {
        self.init(identifier: identifier)
        self.indexingKey = indexingKey
    }

    public init(identifier: String, getter: @escaping (EntityProperty<Value>) async -> Value) {
        self.init(identifier: identifier)
        self.getter = getter
        self.modifiers = [.async]
    }

    public init(identifier: String, title: LocalizedStringResource,
                getter: @escaping (EntityProperty<Value>) async -> Value) {
        self.init(identifier: identifier, title: title)
        self.getter = getter
        self.modifiers = [.async]
    }

    public init(identifier: String, title: LocalizedStringResource, asyncGetter: Bool) {
        self.init(identifier: identifier, title: title)
        if asyncGetter { self.modifiers = [.async] }
    }

    public init(identifier: String, customIndexingKey: String,
                getter: @escaping (EntityProperty<Value>) async -> Value) {
        self.init(identifier: identifier)
        self.indexingKey = customIndexingKey
        self.getter = getter
        self.modifiers = [.async]
    }

    public init(identifier: String, title: LocalizedStringResource, customIndexingKey: String,
                getter: @escaping (EntityProperty<Value>) async -> Value) {
        self.init(identifier: identifier, title: title, customIndexingKey: customIndexingKey)
        self.getter = getter
        self.modifiers = [.async]
    }

    public init(identifier: String, title: LocalizedStringResource, indexingKey: String,
                getter: @escaping (EntityProperty<Value>) async -> Value) {
        self.init(identifier: identifier, title: title, indexingKey: indexingKey)
        self.getter = getter
        self.modifiers = [.async]
    }

    public init(identifier: String, title: LocalizedStringResource, customIndexingKey: String, indexingKey: String,
                getter: @escaping (EntityProperty<Value>) async -> Value) {
        self.init(identifier: identifier, title: title, indexingKey: indexingKey)
        self.getter = getter
        self.modifiers = [.async]
    }

    public init(identifier: String, getSetter: @escaping (Value) async -> Void) {
        self.init(identifier: identifier)
        self.setter = getSetter
    }

    public init(identifier: String, customIndexingKey: String, getSetter: @escaping (Value) async -> Void) {
        self.init(identifier: identifier)
        self.indexingKey = customIndexingKey
        self.setter = getSetter
    }

    public init(identifier: String, title: LocalizedStringResource, getSetter: @escaping (Value) async -> Void) {
        self.init(identifier: identifier, title: title)
        self.setter = getSetter
    }

    public init(identifier: String, title: LocalizedStringResource, customIndexingKey: String,
                getSetter: @escaping (Value) async -> Void) {
        self.init(identifier: identifier, title: title, customIndexingKey: customIndexingKey)
        self.setter = getSetter
    }

    public init(identifier: String, title: LocalizedStringResource, indexingKey: String,
                getSetter: @escaping (Value) async -> Void) {
        self.init(identifier: identifier, title: title, indexingKey: indexingKey)
        self.setter = getSetter
    }

    public init(identifier: String, title: LocalizedStringResource, customIndexingKey: String, indexingKey: String,
                getSetter: @escaping (Value) async -> Void) {
        self.init(identifier: identifier, title: title, indexingKey: indexingKey)
        self.setter = getSetter
    }

    public init(identifier: String, title: LocalizedStringResource, customIndexingKey: String,
                getSetter: @escaping (Value) async -> Void,
                getter: @escaping (EntityProperty<Value>) async -> Value) {
        self.init(identifier: identifier, title: title, customIndexingKey: customIndexingKey)
        self.setter = getSetter
        self.getter = getter
    }

    /// What the index stores for a property, which is its name and the value it holds.
    public struct IndexRecord: Codable {
        public let key: String
        public let value: String

        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(identifier: try container.decode(String.self, forKey: .identifier))
        if let title = try container.decodeIfPresent(String.self, forKey: .title) { self.title = LocalizedStringResource(title) }
        if let key = try container.decodeIfPresent(String.self, forKey: .indexingKey) { self.indexingKey = key }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(title.localizedString(), forKey: .title)
        try container.encode(indexingKey, forKey: .indexingKey)
    }

    private enum CodingKeys: String, CodingKey {
        case identifier
        case title
        case indexingKey
    }
}

extension EntityProperty: CustomStringConvertible {
    /// The property's name as the index and a search result show it.
    public var description: String { return title.localizedString() }
}

/// What a property of an entity may and may not do, added in iOS 26.
public struct EntityPropertyModifiers: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The property is read without the entity being read whole, which is what an entity too large to
    /// index at once needs.
    public static let async = EntityPropertyModifiers(rawValue: 1 << 0)
    /// The property is read and never written by an intent.
    public static let readOnly = EntityPropertyModifiers(rawValue: 1 << 1)
}
