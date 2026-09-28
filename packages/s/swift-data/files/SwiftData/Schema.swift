// Schema.swift
// SwiftData Schema implementation over Core Data for iOS 6

import Foundation
import CoreData

public struct Schema: Sendable, Codable, Equatable, Hashable {
    public let entities: [Entity]
    public let version: Version
    public let encodingVersion: Int

    public init(_ types: [any PersistentModel.Type], version: Version = Version(1, 0, 0)) {
        self.entities = types.map { Entity($0) }
        self.version = version
        self.encodingVersion = 1
    }

    public init(versionedSchema: any VersionedSchema) {
        let versionedSchemaType = type(of: versionedSchema)
        self.entities = versionedSchemaType.models.map { Entity($0) }
        self.version = versionedSchemaType.version
        self.encodingVersion = 1
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.entities = try container.decode([Entity].self, forKey: .entities)
        self.version = try container.decode(Version.self, forKey: .version)
        self.encodingVersion = try container.decodeIfPresent(Int.self, forKey: .encodingVersion) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entities, forKey: .entities)
        try container.encode(version, forKey: .version)
        try container.encode(encodingVersion, forKey: .encodingVersion)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(entities)
        hasher.combine(version)
        hasher.combine(encodingVersion)
    }

    public static func == (lhs: Schema, rhs: Schema) -> Bool {
        lhs.entities == rhs.entities && lhs.version == rhs.version && lhs.encodingVersion == rhs.encodingVersion
    }

    public var entitiesByName: [String: Entity] {
        Dictionary(uniqueKeysWithValues: entities.map { ($0.name, $0) })
    }

    public var debugDescription: String {
        "Schema(version: \(version), entities: \(entities.map { $0.name }))"
    }

    public func entityName(for modelType: any PersistentModel.Type) -> String {
        return String(describing: modelType)
    }

    public func entity(for modelType: any PersistentModel.Type) -> Entity? {
        return entitiesByName[entityName(for: modelType)]
    }

    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url)
    }

    public static func load(from url: URL) throws -> Schema {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Schema.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case entities, version, encodingVersion
    }
}

extension Schema {
    public struct Version: Sendable, Codable, Equatable, Hashable, Comparable {
        public let major: Int
        public let minor: Int
        public let patch: Int

        public init(_ major: Int, _ minor: Int, _ patch: Int) {
            self.major = major
            self.minor = minor
            self.patch = patch
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let components = string.split(separator: ".").compactMap { Int($0) }
            guard components.count >= 1 else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid version string") }
            self.major = components[0]
            self.minor = components.count > 1 ? components[1] : 0
            self.patch = components.count > 2 ? components[2] : 0
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode("\(major).\(minor).\(patch)")
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(major)
            hasher.combine(minor)
            hasher.combine(patch)
        }

        public static func == (lhs: Version, rhs: Version) -> Bool {
            lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch
        }

        public static func < (lhs: Version, rhs: Version) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            return lhs.patch < rhs.patch
        }

        public var description: String { "\(major).\(minor).\(patch)" }
    }

    public struct Entity: Sendable, Codable, Equatable, Hashable {
        public let name: String
        public let superentityName: String?
        public let attributes: [Attribute]
        public let relationships: [Relationship]
        public let compositeAttributes: [CompositeAttribute]
        public let indices: [Index]
        public let uniquenessConstraints: [[String]]
        public let inheritedProperties: [Property]
        public let subentities: [Entity]

        public init(_ modelType: any PersistentModel.Type) {
            self.name = String(describing: modelType)
            self.superentityName = nil
            self.attributes = []
            self.relationships = []
            self.compositeAttributes = []
            self.indices = []
            self.uniquenessConstraints = []
            self.inheritedProperties = []
            self.subentities = []
        }

        public init(_ name: String, subentities: [Entity] = [], attributes: [Attribute] = [], relationships: [Relationship] = [], compositeAttributes: [CompositeAttribute] = []) {
            self.name = name
            self.superentityName = nil
            self.attributes = attributes
            self.relationships = relationships
            self.compositeAttributes = compositeAttributes
            self.indices = []
            self.uniquenessConstraints = []
            self.inheritedProperties = []
            self.subentities = subentities
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try container.decode(String.self, forKey: .name)
            self.superentityName = try container.decodeIfPresent(String.self, forKey: .superentityName)
            self.attributes = try container.decode([Attribute].self, forKey: .attributes)
            self.relationships = try container.decode([Relationship].self, forKey: .relationships)
            self.compositeAttributes = try container.decodeIfPresent([CompositeAttribute].self, forKey: .compositeAttributes) ?? []
            self.indices = try container.decodeIfPresent([Index].self, forKey: .indices) ?? []
            self.uniquenessConstraints = try container.decodeIfPresent([[String]].self, forKey: .uniquenessConstraints) ?? []
            self.inheritedProperties = try container.decodeIfPresent([Property].self, forKey: .inheritedProperties) ?? []
            self.subentities = try container.decodeIfPresent([Entity].self, forKey: .subentities) ?? []
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(superentityName, forKey: .superentityName)
            try container.encode(attributes, forKey: .attributes)
            try container.encode(relationships, forKey: .relationships)
            try container.encode(compositeAttributes, forKey: .compositeAttributes)
            try container.encode(indices, forKey: .indices)
            try container.encode(uniquenessConstraints, forKey: .uniquenessConstraints)
            try container.encode(inheritedProperties, forKey: .inheritedProperties)
            try container.encode(subentities, forKey: .subentities)
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
            hasher.combine(superentityName)
            hasher.combine(attributes)
            hasher.combine(relationships)
            hasher.combine(compositeAttributes)
        }

        public static func == (lhs: Entity, rhs: Entity) -> Bool {
            lhs.name == rhs.name && lhs.superentityName == rhs.superentityName && lhs.attributes == rhs.attributes && lhs.relationships == rhs.relationships && lhs.compositeAttributes == rhs.compositeAttributes
        }

        public var storedProperties: [any SchemaProperty] {
            var props: [any SchemaProperty] = []
            props.append(contentsOf: attributes)
            props.append(contentsOf: relationships)
            props.append(contentsOf: compositeAttributes)
            return props
        }
        public var relationshipsByName: [String: Relationship] { Dictionary(uniqueKeysWithValues: relationships.map { ($0.name, $0) }) }
        public var attributesByName: [String: Attribute] { Dictionary(uniqueKeysWithValues: attributes.map { ($0.name, $0) }) }

        public var debugDescription: String { "Entity(\(name))" }

        private enum CodingKeys: String, CodingKey {
            case name, superentityName, attributes, relationships, compositeAttributes, indices, uniquenessConstraints, inheritedProperties, subentities
        }
    }

    public struct Property: Sendable, Codable, Equatable, Hashable {
        public let name: String
        public let originalName: String?
        public let isOptional: Bool
        public let isTransient: Bool
        public let isUnique: Bool

        public init(name: String, originalName: String? = nil, isOptional: Bool = false, isTransient: Bool = false, isUnique: Bool = false) {
            self.name = name
            self.originalName = originalName
            self.isOptional = isOptional
            self.isTransient = isTransient
            self.isUnique = isUnique
        }
    }

    public struct Attribute: SchemaProperty, Sendable, Codable, Equatable, Hashable {
        public let name: String
        public let originalName: String?
        public let isOptional: Bool
        public let isTransient: Bool
        public let isUnique: Bool
        public let options: [Option]
        public let valueType: String
        public let hashModifier: Int?

        public var isRelationship: Bool { false }
        public var isAttribute: Bool { true }

        public init(name: String, originalName: String? = nil, options: [Option] = [], valueType: String, defaultValue: Any? = nil, hashModifier: Int? = nil) {
            self.name = name
            self.originalName = originalName
            self.isOptional = false
            self.isTransient = false
            self.isUnique = options.contains(.unique)
            self.options = options
            self.valueType = valueType
            self.hashModifier = hashModifier
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try container.decode(String.self, forKey: .name)
            self.originalName = try container.decodeIfPresent(String.self, forKey: .originalName)
            self.isOptional = try container.decodeIfPresent(Bool.self, forKey: .isOptional) ?? false
            self.isTransient = try container.decodeIfPresent(Bool.self, forKey: .isTransient) ?? false
            self.isUnique = try container.decodeIfPresent(Bool.self, forKey: .isUnique) ?? false
            self.options = try container.decodeIfPresent([Option].self, forKey: .options) ?? []
            self.valueType = try container.decode(String.self, forKey: .valueType)
            self.hashModifier = try container.decodeIfPresent(Int.self, forKey: .hashModifier)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(originalName, forKey: .originalName)
            try container.encode(isOptional, forKey: .isOptional)
            try container.encode(isTransient, forKey: .isTransient)
            try container.encode(isUnique, forKey: .isUnique)
            try container.encode(options, forKey: .options)
            try container.encode(valueType, forKey: .valueType)
            try container.encodeIfPresent(hashModifier, forKey: .hashModifier)
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
            hasher.combine(originalName)
            hasher.combine(isOptional)
            hasher.combine(isTransient)
            hasher.combine(isUnique)
            hasher.combine(options)
            hasher.combine(valueType)
            hasher.combine(hashModifier)
        }

        public static func == (lhs: Attribute, rhs: Attribute) -> Bool {
            lhs.name == rhs.name && lhs.originalName == rhs.originalName && lhs.isOptional == rhs.isOptional && lhs.isTransient == rhs.isTransient && lhs.isUnique == rhs.isUnique && lhs.options == rhs.options && lhs.valueType == rhs.valueType && lhs.hashModifier == rhs.hashModifier
        }

        public var debugDescription: String { "Attribute(\(name): \(valueType))" }

        public enum Option: Sendable, Codable, Equatable, Hashable {
            case unique, spotlight, preserveValueOnDeletion, externalStorage, ephemeral, allowsCloudEncryption, transformable(String)

            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                let string = try container.decode(String.self)
                switch string {
                case "unique": self = .unique
                case "spotlight": self = .spotlight
                case "preserveValueOnDeletion": self = .preserveValueOnDeletion
                case "externalStorage": self = .externalStorage
                case "ephemeral": self = .ephemeral
                case "allowsCloudEncryption": self = .allowsCloudEncryption
                default: self = .transformable(string)
                }
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .unique: try container.encode("unique")
                case .spotlight: try container.encode("spotlight")
                case .preserveValueOnDeletion: try container.encode("preserveValueOnDeletion")
                case .externalStorage: try container.encode("externalStorage")
                case .ephemeral: try container.encode("ephemeral")
                case .allowsCloudEncryption: try container.encode("allowsCloudEncryption")
                case .transformable(let value): try container.encode("transformable:\(value)")
                }
            }

            public func hash(into hasher: inout Hasher) {
                switch self {
                case .unique: hasher.combine("unique")
                case .spotlight: hasher.combine("spotlight")
                case .preserveValueOnDeletion: hasher.combine("preserveValueOnDeletion")
                case .externalStorage: hasher.combine("externalStorage")
                case .ephemeral: hasher.combine("ephemeral")
                case .allowsCloudEncryption: hasher.combine("allowsCloudEncryption")
                case .transformable(let value): hasher.combine("transformable:\(value)")
                }
            }

            public static func == (lhs: Option, rhs: Option) -> Bool {
                switch (lhs, rhs) {
                case (.unique, .unique), (.spotlight, .spotlight), (.preserveValueOnDeletion, .preserveValueOnDeletion), (.externalStorage, .externalStorage), (.ephemeral, .ephemeral), (.allowsCloudEncryption, .allowsCloudEncryption):
                    return true
                case (.transformable(let a), .transformable(let b)):
                    return a == b
                default:
                    return false
                }
            }

            public var debugDescription: String {
                switch self {
                case .unique: return "unique"
                case .spotlight: return "spotlight"
                case .preserveValueOnDeletion: return "preserveValueOnDeletion"
                case .externalStorage: return "externalStorage"
                case .ephemeral: return "ephemeral"
                case .allowsCloudEncryption: return "allowsCloudEncryption"
                case .transformable(let value): return "transformable(\(value))"
                }
            }
        }

        private enum CodingKeys: String, CodingKey {
            case name, originalName, isOptional, isTransient, isUnique, options, valueType, hashModifier
        }
    }

    public struct CompositeAttribute: SchemaProperty, Sendable, Codable, Equatable, Hashable {
        public let name: String
        public let originalName: String?
        public let isOptional: Bool
        public let isTransient: Bool
        public let isUnique: Bool = false
        public let properties: [Property]
        public let hashModifier: Int?

        public var isRelationship: Bool { false }
        public var isAttribute: Bool { true }
        public var valueType: String { "Composite" }

        public init(name: String, originalName: String? = nil, options: [Attribute.Option] = [], valueType: String, defaultValue: Any? = nil, hashModifier: Int? = nil) {
            self.name = name
            self.originalName = originalName
            self.isOptional = false
            self.isTransient = false
            self.properties = []
            self.hashModifier = hashModifier
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try container.decode(String.self, forKey: .name)
            self.originalName = try container.decodeIfPresent(String.self, forKey: .originalName)
            self.isOptional = try container.decodeIfPresent(Bool.self, forKey: .isOptional) ?? false
            self.isTransient = try container.decodeIfPresent(Bool.self, forKey: .isTransient) ?? false
            self.properties = try container.decode([Property].self, forKey: .properties)
            self.hashModifier = try container.decodeIfPresent(Int.self, forKey: .hashModifier)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(originalName, forKey: .originalName)
            try container.encode(isOptional, forKey: .isOptional)
            try container.encode(isTransient, forKey: .isTransient)
            try container.encode(properties, forKey: .properties)
            try container.encodeIfPresent(hashModifier, forKey: .hashModifier)
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
            hasher.combine(originalName)
            hasher.combine(isOptional)
            hasher.combine(isTransient)
            hasher.combine(properties)
            hasher.combine(hashModifier)
        }

        public static func == (lhs: CompositeAttribute, rhs: CompositeAttribute) -> Bool {
            lhs.name == rhs.name && lhs.originalName == rhs.originalName && lhs.isOptional == rhs.isOptional && lhs.isTransient == rhs.isTransient && lhs.properties == rhs.properties && lhs.hashModifier == rhs.hashModifier
        }

        public var debugDescription: String { "CompositeAttribute(\(name))" }

        private enum CodingKeys: String, CodingKey {
            case name, originalName, isOptional, isTransient, properties, hashModifier
        }
    }

    public struct Relationship: SchemaProperty, Sendable, Codable, Equatable, Hashable {
        public let name: String
        public let originalName: String?
        public let isOptional: Bool
        public let isTransient: Bool
        public let isUnique: Bool
        public let destination: String
        public let inverseName: String?
        public let inverseKeyPath: String?
        public let minimumModelCount: Int
        public let maximumModelCount: Int
        public let options: [Option]
        public let deleteRule: DeleteRule
        public let keypath: String
        public let hashModifier: Int?

        public var isRelationship: Bool { true }
        public var isAttribute: Bool { false }
        public var valueType: String { destination }

        public init(name: String, originalName: String? = nil, deleteRule: DeleteRule = .nullify, minimumModelCount: Int = 1, maximumModelCount: Int = 1, inverseName: String? = nil, inverseKeyPath: String? = nil, destination: String, keypath: String, hashModifier: Int? = nil) {
            self.name = name
            self.originalName = originalName
            self.isOptional = false
            self.isTransient = false
            self.isUnique = false
            self.destination = destination
            self.inverseName = inverseName
            self.inverseKeyPath = inverseKeyPath
            self.minimumModelCount = minimumModelCount
            self.maximumModelCount = maximumModelCount
            self.options = []
            self.deleteRule = deleteRule
            self.keypath = keypath
            self.hashModifier = hashModifier
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try container.decode(String.self, forKey: .name)
            self.originalName = try container.decodeIfPresent(String.self, forKey: .originalName)
            self.isOptional = try container.decodeIfPresent(Bool.self, forKey: .isOptional) ?? false
            self.isTransient = try container.decodeIfPresent(Bool.self, forKey: .isTransient) ?? false
            self.isUnique = try container.decodeIfPresent(Bool.self, forKey: .isUnique) ?? false
            self.destination = try container.decode(String.self, forKey: .destination)
            self.inverseName = try container.decodeIfPresent(String.self, forKey: .inverseName)
            self.inverseKeyPath = try container.decodeIfPresent(String.self, forKey: .inverseKeyPath)
            self.minimumModelCount = try container.decodeIfPresent(Int.self, forKey: .minimumModelCount) ?? 1
            self.maximumModelCount = try container.decodeIfPresent(Int.self, forKey: .maximumModelCount) ?? 1
            self.options = try container.decodeIfPresent([Option].self, forKey: .options) ?? []
            self.deleteRule = try container.decode(DeleteRule.self, forKey: .deleteRule)
            self.keypath = try container.decode(String.self, forKey: .keypath)
            self.hashModifier = try container.decodeIfPresent(Int.self, forKey: .hashModifier)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(originalName, forKey: .originalName)
            try container.encode(isOptional, forKey: .isOptional)
            try container.encode(isTransient, forKey: .isTransient)
            try container.encode(isUnique, forKey: .isUnique)
            try container.encode(destination, forKey: .destination)
            try container.encodeIfPresent(inverseName, forKey: .inverseName)
            try container.encodeIfPresent(inverseKeyPath, forKey: .inverseKeyPath)
            try container.encode(minimumModelCount, forKey: .minimumModelCount)
            try container.encode(maximumModelCount, forKey: .maximumModelCount)
            try container.encode(options, forKey: .options)
            try container.encode(deleteRule, forKey: .deleteRule)
            try container.encode(keypath, forKey: .keypath)
            try container.encodeIfPresent(hashModifier, forKey: .hashModifier)
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
            hasher.combine(originalName)
            hasher.combine(isOptional)
            hasher.combine(isTransient)
            hasher.combine(isUnique)
            hasher.combine(destination)
            hasher.combine(inverseName)
            hasher.combine(inverseKeyPath)
            hasher.combine(minimumModelCount)
            hasher.combine(maximumModelCount)
            hasher.combine(options)
            hasher.combine(deleteRule)
            hasher.combine(keypath)
            hasher.combine(hashModifier)
        }

        public static func == (lhs: Relationship, rhs: Relationship) -> Bool {
            lhs.name == rhs.name && lhs.originalName == rhs.originalName && lhs.isOptional == rhs.isOptional && lhs.isTransient == rhs.isTransient && lhs.isUnique == rhs.isUnique && lhs.destination == rhs.destination && lhs.inverseName == rhs.inverseName && lhs.inverseKeyPath == rhs.inverseKeyPath && lhs.minimumModelCount == rhs.minimumModelCount && lhs.maximumModelCount == rhs.maximumModelCount && lhs.options == rhs.options && lhs.deleteRule == rhs.deleteRule && lhs.keypath == rhs.keypath && lhs.hashModifier == rhs.hashModifier
        }

        public var debugDescription: String { "Relationship(\(name) -> \(destination))" }

        public enum Option: Sendable, Codable, Equatable, Hashable {
            case unique

            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                let string = try container.decode(String.self)
                if string == "unique" { self = .unique } else { self = .unique }
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode("unique")
            }

            public func hash(into hasher: inout Hasher) { hasher.combine("unique") }

            public static func == (lhs: Option, rhs: Option) -> Bool { true }
        }

        public enum DeleteRule: String, Sendable, Codable, Equatable, Hashable {
            case nullify, cascade, deny, noAction

            public init?(rawValue: String) {
                switch rawValue {
                case "nullify": self = .nullify
                case "cascade": self = .cascade
                case "deny": self = .deny
                case "noAction": self = .noAction
                default: return nil
                }
            }

            public var rawValue: String {
                switch self {
                case .nullify: return "nullify"
                case .cascade: return "cascade"
                case .deny: return "deny"
                case .noAction: return "noAction"
                }
            }
        }

        private enum CodingKeys: String, CodingKey {
            case name, originalName, isOptional, isTransient, isUnique, destination, inverseName, inverseKeyPath, minimumModelCount, maximumModelCount, options, deleteRule, keypath, hashModifier
        }
    }

    public struct Index: Sendable, Codable, Equatable, Hashable {
        public let name: String
        public let originalName: String?
        public let isUnique: Bool
        public let indices: [String]

        public init(_ name: String) {
            self.name = name
            self.originalName = nil
            self.isUnique = false
            self.indices = []
        }

        public init(name: String, originalName: String? = nil, isUnique: Bool = false, indices: [String] = []) {
            self.name = name
            self.originalName = originalName
            self.isUnique = isUnique
            self.indices = indices
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try container.decode(String.self, forKey: .name)
            self.originalName = try container.decodeIfPresent(String.self, forKey: .originalName)
            self.isUnique = try container.decodeIfPresent(Bool.self, forKey: .isUnique) ?? false
            self.indices = try container.decodeIfPresent([String].self, forKey: .indices) ?? []
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(originalName, forKey: .originalName)
            try container.encode(isUnique, forKey: .isUnique)
            try container.encode(indices, forKey: .indices)
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
            hasher.combine(originalName)
            hasher.combine(isUnique)
            hasher.combine(indices)
        }

        public static func == (lhs: Index, rhs: Index) -> Bool {
            lhs.name == rhs.name && lhs.originalName == rhs.originalName && lhs.isUnique == rhs.isUnique && lhs.indices == rhs.indices
        }

        public var debugDescription: String { "Index(\(name))" }

        public enum Types: String, Sendable, Codable, Equatable, Hashable {
            case binary, rtree
        }

        private enum CodingKeys: String, CodingKey {
            case name, originalName, isUnique, indices
        }
    }

    public struct Unique: Sendable, Codable, Equatable, Hashable {
        public let constraints: [[String]]

        public init(_ constraints: [String]...) {
            self.constraints = constraints
        }

        public init(_ constraints: [[String]]) {
            self.constraints = constraints
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.constraints = try container.decode([[String]].self, forKey: .constraints)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(constraints, forKey: .constraints)
        }

        public func hash(into hasher: inout Hasher) { hasher.combine(constraints) }

        public static func == (lhs: Unique, rhs: Unique) -> Bool { lhs.constraints == rhs.constraints }

        public var debugDescription: String { "Unique(\(constraints))" }

        public enum CodingKeys: String, CodingKey { case constraints }
    }

    public struct PropertyMetadata: Sendable, Codable, Equatable, Hashable {
        public let name: String
        public let keypath: String
        public let defaultValue: String?
        public let metadata: [String: String]?

        public init(name: String, keypath: String, defaultValue: String? = nil, metadata: [String: String]? = nil) {
            self.name = name
            self.keypath = keypath
            self.defaultValue = defaultValue
            self.metadata = metadata
        }
    }
}

public protocol VersionedSchema {
    static var version: Schema.Version { get }
    static var models: [any PersistentModel.Type] { get }
}

public protocol SchemaProperty: Sendable {
    var name: String { get }
    var originalName: String? { get }
    var valueType: String { get }
    var isUnique: Bool { get }
    var isTransient: Bool { get }
    var isRelationship: Bool { get }
    var isAttribute: Bool { get }
    var isOptional: Bool { get }
}

public protocol SchemaMigrationPlan {
    static var schemas: [Schema] { get }
    static var stages: [MigrationStage] { get }
}

public enum MigrationStage: Sendable {
    case lightweight
    case custom
}