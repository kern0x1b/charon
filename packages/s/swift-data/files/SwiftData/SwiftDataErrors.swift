// SwiftDataErrors.swift
// SwiftData error types and SwiftUI integration stubs

@preconcurrency import Foundation

public enum SwiftDataError: Error, Equatable, Hashable {
    case unsupportedPredicate
    case unsupportedSortDescriptor
    case unsupportedKeyPath
    case unknownSchema
    case sortingPendingChangesWithIdentifiers
    case modelValidationFailure
    case missingModelContext
    case loadIssueModelContainer
    case invalidTransactionFetchRequest
    case includePendingChangesWithBatchSize
    case historyTokenExpired
    case duplicateConfiguration
    case configurationSchemaNotFoundInContainerSchema
    case configurationFileNameTooLong
    case configurationFileNameContainsInvalidCharacters
    case backwardMigration

    public static func ~= (lhs: SwiftDataError, rhs: SwiftDataError) -> Bool {
        return lhs == rhs
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .unsupportedPredicate: hasher.combine("unsupportedPredicate")
        case .unsupportedSortDescriptor: hasher.combine("unsupportedSortDescriptor")
        case .unsupportedKeyPath: hasher.combine("unsupportedKeyPath")
        case .unknownSchema: hasher.combine("unknownSchema")
        case .sortingPendingChangesWithIdentifiers: hasher.combine("sortingPendingChangesWithIdentifiers")
        case .modelValidationFailure: hasher.combine("modelValidationFailure")
        case .missingModelContext: hasher.combine("missingModelContext")
        case .loadIssueModelContainer: hasher.combine("loadIssueModelContainer")
        case .invalidTransactionFetchRequest: hasher.combine("invalidTransactionFetchRequest")
        case .includePendingChangesWithBatchSize: hasher.combine("includePendingChangesWithBatchSize")
        case .historyTokenExpired: hasher.combine("historyTokenExpired")
        case .duplicateConfiguration: hasher.combine("duplicateConfiguration")
        case .configurationSchemaNotFoundInContainerSchema: hasher.combine("configurationSchemaNotFoundInContainerSchema")
        case .configurationFileNameTooLong: hasher.combine("configurationFileNameTooLong")
        case .configurationFileNameContainsInvalidCharacters: hasher.combine("configurationFileNameContainsInvalidCharacters")
        case .backwardMigration: hasher.combine("backwardMigration")
        }
    }

    public static func == (lhs: SwiftDataError, rhs: SwiftDataError) -> Bool {
        switch (lhs, rhs) {
        case (.unsupportedPredicate, .unsupportedPredicate): return true
        case (.unsupportedSortDescriptor, .unsupportedSortDescriptor): return true
        case (.unsupportedKeyPath, .unsupportedKeyPath): return true
        case (.unknownSchema, .unknownSchema): return true
        case (.sortingPendingChangesWithIdentifiers, .sortingPendingChangesWithIdentifiers): return true
        case (.modelValidationFailure, .modelValidationFailure): return true
        case (.missingModelContext, .missingModelContext): return true
        case (.loadIssueModelContainer, .loadIssueModelContainer): return true
        case (.invalidTransactionFetchRequest, .invalidTransactionFetchRequest): return true
        case (.includePendingChangesWithBatchSize, .includePendingChangesWithBatchSize): return true
        case (.historyTokenExpired, .historyTokenExpired): return true
        case (.duplicateConfiguration, .duplicateConfiguration): return true
        case (.configurationSchemaNotFoundInContainerSchema, .configurationSchemaNotFoundInContainerSchema): return true
        case (.configurationFileNameTooLong, .configurationFileNameTooLong): return true
        case (.configurationFileNameContainsInvalidCharacters, .configurationFileNameContainsInvalidCharacters): return true
        case (.backwardMigration, .backwardMigration): return true
        default: return false
        }
    }
}

// Property wrappers for AppStorage/SceneStorage
@propertyWrapper
public struct AppStorage<Value>: DynamicProperty {
    public var wrappedValue: Value { fatalError("Requires SwiftUI") }
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {}
    public init(_ key: String, store: UserDefaults? = nil) where Value: ExpressibleByNilLiteral {}
}

@propertyWrapper
public struct SceneStorage<Value>: DynamicProperty {
    public var wrappedValue: Value { fatalError("Requires SwiftUI") }
    public init(wrappedValue: Value, _ key: String) {}
    public init(_ key: String) where Value: ExpressibleByNilLiteral {}
}

@propertyWrapper
public struct Model<Content: PersistentModel>: DynamicProperty {
    public var wrappedValue: Content { fatalError("Requires SwiftUI") }
    public init() {}
}

public protocol DynamicProperty {}

// Environment values
public struct EnvironmentValues {
    public var modelContext: ModelContext? { nil }
}

// SwiftUI integration stubs - these are absents, not stubs
// They compile but require SwiftUI to be useful

public protocol View {}

public struct EmptyView: View {}

public extension View {
    func modelContext(_ context: ModelContext) -> EmptyView { fatalError("Requires SwiftUI") }
    func modelContainer(for type: any PersistentModel.Type, inMemory: Bool = false, isAutosaveEnabled: Bool = true, isUndoEnabled: Bool = true, onSetup: ((ModelContainer) -> Void)? = nil) -> EmptyView { fatalError("Requires SwiftUI") }
    func modelContainer(_ container: ModelContainer) -> EmptyView { fatalError("Requires SwiftUI") }
}

public protocol Scene {}

public extension Scene {
    func modelContext(_ context: ModelContext) -> EmptyView { fatalError("Requires SwiftUI") }
    func modelContainer(for type: any PersistentModel.Type, inMemory: Bool = false, isAutosaveEnabled: Bool = true, isUndoEnabled: Bool = true, onSetup: ((ModelContainer) -> Void)? = nil) -> EmptyView { fatalError("Requires SwiftUI") }
    func modelContainer(_ container: ModelContainer) -> EmptyView { fatalError("Requires SwiftUI") }
}

public struct Animation {
    public static let `default` = Animation()
    public static let easeInOut = Animation()
    public static let linear = Animation()
}

// Query property wrapper - requires SwiftUI
@propertyWrapper
public struct QueryProperty<Content: PersistentModel>: DynamicProperty {
    public var wrappedValue: [Content] { fatalError("Query requires SwiftUI") }
    public var modelContext: ModelContext? { nil }
    public var fetchError: Error? { nil }
    public init(filter: Predicate<Content>? = nil, sort: [SortDescriptor<Content>] = [], transaction: TransactionAuthor? = nil, animation: Animation? = nil) {}
    public mutating func update() {}
}

public func query<Content>(filter: Predicate<Content>? = nil, sort: [SortDescriptor<Content>] = [], transaction: TransactionAuthor? = nil, animation: Animation? = nil) -> EmptyView where Content: PersistentModel {
    fatalError("Query is a property wrapper for SwiftUI")
}

// DocumentGroup for document-based apps
public struct DocumentGroup<Content: View>: Scene {
    public init(viewing: any PersistentModel.Type, migrationPlan: (any SchemaMigrationPlan)? = nil, viewer: @escaping (ModelContainer) -> Content) {}
    public init(viewing: any PersistentModel.Type, contentType: UTType, viewer: @escaping (ModelContainer) -> Content) {}
    public init(editing: any PersistentModel.Type, migrationPlan: (any SchemaMigrationPlan)? = nil, editor: @escaping (ModelContainer) -> Content, prepareDocument: @escaping (ModelContainer) throws -> Void) {}
    public init(editing: any PersistentModel.Type, contentType: UTType, editor: @escaping (ModelContainer) -> Content, prepareDocument: @escaping (ModelContainer) throws -> Void) {}
    public var body: EmptyView { fatalError("Requires SwiftUI") }
}

public struct UTType {
    public init(_ identifier: String) {}
}