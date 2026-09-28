// ModelConfiguration.swift
// SwiftData ModelConfiguration implementation over Core Data for iOS 6

@preconcurrency import Foundation
import CoreData

public struct ModelConfiguration: Sendable, Codable, Equatable, Hashable {
    public let name: String
    public let schema: Schema?
    public let url: URL?
    public let allowsSave: Bool
    public let isStoredInMemoryOnly: Bool
    public let cloudKitContainerIdentifier: String?
    public let cloudKitDatabase: CloudKitDatabase
    public let groupContainer: GroupContainer
    public let groupAppContainerIdentifier: String?

    public init(
        _ name: String,
        schema: Schema? = nil,
        url: URL? = nil,
        allowsSave: Bool = true,
        cloudKitDatabase: CloudKitDatabase = .none,
        groupContainer: GroupContainer = .none
    ) {
        self.name = name
        self.schema = schema
        self.url = url
        self.allowsSave = allowsSave
        self.isStoredInMemoryOnly = url == nil
        self.cloudKitContainerIdentifier = nil
        self.cloudKitDatabase = cloudKitDatabase
        self.groupContainer = groupContainer
        self.groupAppContainerIdentifier = nil
    }

    public init(
        _ name: String,
        schema: Schema,
        isStoredInMemoryOnly: Bool = false,
        allowsSave: Bool = true,
        groupContainer: GroupContainer = .none,
        cloudKitDatabase: CloudKitDatabase = .none
    ) {
        self.name = name
        self.schema = schema
        self.url = nil
        self.allowsSave = allowsSave
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
        self.cloudKitContainerIdentifier = nil
        self.cloudKitDatabase = cloudKitDatabase
        self.groupContainer = groupContainer
        self.groupAppContainerIdentifier = nil
    }

    public init(
        for modelType: any PersistentModel.Type,
        isStoredInMemoryOnly: Bool = false
    ) {
        self.name = "default"
        self.schema = Schema([modelType])
        self.url = nil
        self.allowsSave = true
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
        self.cloudKitContainerIdentifier = nil
        self.cloudKitDatabase = .none
        self.groupContainer = .none
        self.groupAppContainerIdentifier = nil
    }

    public init(
        _ name: String,
        schema: Schema,
        url: URL,
        allowsSave: Bool,
        cloudKitDatabase: CloudKitDatabase
    ) {
        self.name = name
        self.schema = schema
        self.url = url
        self.allowsSave = allowsSave
        self.isStoredInMemoryOnly = false
        self.cloudKitContainerIdentifier = nil
        self.cloudKitDatabase = cloudKitDatabase
        self.groupContainer = .none
        self.groupAppContainerIdentifier = nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.schema = try container.decodeIfPresent(Schema.self, forKey: .schema)
        self.url = try container.decodeIfPresent(URL.self, forKey: .url)
        self.allowsSave = try container.decodeIfPresent(Bool.self, forKey: .allowsSave) ?? true
        self.isStoredInMemoryOnly = try container.decodeIfPresent(Bool.self, forKey: .isStoredInMemoryOnly) ?? false
        self.cloudKitContainerIdentifier = try container.decodeIfPresent(String.self, forKey: .cloudKitContainerIdentifier)
        self.cloudKitDatabase = try container.decodeIfPresent(CloudKitDatabase.self, forKey: .cloudKitDatabase) ?? .none
        self.groupContainer = try container.decodeIfPresent(GroupContainer.self, forKey: .groupContainer) ?? .none
        self.groupAppContainerIdentifier = try container.decodeIfPresent(String.self, forKey: .groupAppContainerIdentifier)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(schema, forKey: .schema)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(allowsSave, forKey: .allowsSave)
        try container.encode(isStoredInMemoryOnly, forKey: .isStoredInMemoryOnly)
        try container.encodeIfPresent(cloudKitContainerIdentifier, forKey: .cloudKitContainerIdentifier)
        try container.encode(cloudKitDatabase, forKey: .cloudKitDatabase)
        try container.encode(groupContainer, forKey: .groupContainer)
        try container.encodeIfPresent(groupAppContainerIdentifier, forKey: .groupAppContainerIdentifier)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(schema)
        hasher.combine(url)
        hasher.combine(allowsSave)
        hasher.combine(isStoredInMemoryOnly)
        hasher.combine(cloudKitContainerIdentifier)
        hasher.combine(cloudKitDatabase)
        hasher.combine(groupContainer)
        hasher.combine(groupAppContainerIdentifier)
    }

    public static func == (lhs: ModelConfiguration, rhs: ModelConfiguration) -> Bool {
        lhs.name == rhs.name && lhs.schema == rhs.schema && lhs.url == rhs.url && lhs.allowsSave == rhs.allowsSave && lhs.isStoredInMemoryOnly == rhs.isStoredInMemoryOnly && lhs.cloudKitContainerIdentifier == rhs.cloudKitContainerIdentifier && lhs.cloudKitDatabase == rhs.cloudKitDatabase && lhs.groupContainer == rhs.groupContainer && lhs.groupAppContainerIdentifier == rhs.groupAppContainerIdentifier
    }

    public var debugDescription: String { "ModelConfiguration(\(name), inMemory: \(isStoredInMemoryOnly))" }

    public func validate() throws {
        if name.isEmpty {
            throw SwiftDataError.configurationFileNameContainsInvalidCharacters
        }
        if name.count > 255 {
            throw SwiftDataError.configurationFileNameTooLong
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name, schema, url, allowsSave, isStoredInMemoryOnly, cloudKitContainerIdentifier, cloudKitDatabase, groupContainer, groupAppContainerIdentifier
    }

    public enum GroupContainer: Sendable, Codable, Equatable, Hashable {
        case none, automatic, identifier(String)

        public static func makeIdentifier(_ identifier: String) -> GroupContainer { .identifier(identifier) }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            switch string {
            case "none": self = .none
            case "automatic": self = .automatic
            default: self = .identifier(string)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .none: try container.encode("none")
            case .automatic: try container.encode("automatic")
            case .identifier(let id): try container.encode(id)
            }
        }

        public func hash(into hasher: inout Hasher) {
            switch self {
            case .none: hasher.combine("none")
            case .automatic: hasher.combine("automatic")
            case .identifier(let id): hasher.combine(id)
            }
        }

        public static func == (lhs: GroupContainer, rhs: GroupContainer) -> Bool {
            switch (lhs, rhs) {
            case (.none, .none), (.automatic, .automatic): return true
            case (.identifier(let a), .identifier(let b)): return a == b
            default: return false
            }
        }
    }

    public enum CloudKitDatabase: Sendable, Codable, Equatable, Hashable {
        case none, automatic, `private`(String), shared(String), `public`(String)

        public static func makePrivate(_ identifier: String) -> CloudKitDatabase { .`private`(identifier) }
        public static func makeShared(_ identifier: String) -> CloudKitDatabase { .shared(identifier) }
        public static func makePublic(_ identifier: String) -> CloudKitDatabase { .`public`(identifier) }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if string == "none" { self = .none }
            else if string == "automatic" { self = .automatic }
            else if string.hasPrefix("private:") { self = .`private`(String(string.dropFirst(8))) }
            else if string.hasPrefix("shared:") { self = .shared(String(string.dropFirst(7))) }
            else if string.hasPrefix("public:") { self = .`public`(String(string.dropFirst(7))) }
            else { self = .none }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .none: try container.encode("none")
            case .automatic: try container.encode("automatic")
            case .`private`(let id): try container.encode("private:\(id)")
            case .shared(let id): try container.encode("shared:\(id)")
            case .`public`(let id): try container.encode("public:\(id)")
            }
        }

        public func hash(into hasher: inout Hasher) {
            switch self {
            case .none: hasher.combine("none")
            case .automatic: hasher.combine("automatic")
            case .`private`(let id): hasher.combine("private:\(id)")
            case .shared(let id): hasher.combine("shared:\(id)")
            case .`public`(let id): hasher.combine("public:\(id)")
            }
        }

        public static func == (lhs: CloudKitDatabase, rhs: CloudKitDatabase) -> Bool {
            switch (lhs, rhs) {
            case (.none, .none), (.automatic, .automatic): return true
            case (.`private`(let a), .`private`(let b)): return a == b
            case (.shared(let a), .shared(let b)): return a == b
            case (.`public`(let a), .`public`(let b)): return a == b
            default: return false
            }
        }
    }
}