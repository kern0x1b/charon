// The parameter an intent's property wrapper carries: its title, its value, its default, the control
// it is asked with, the range it must be in, the options it may take, the query that offers them, and
// the resolvers that turn a caller's string into its value.
//
// The 148 initializers below are the framework's own spellings of the same parameter: which labels an
// initializer carries is which of those the app declared, and each stores exactly what its own labels
// say. They are the framework's API surface, not 148 behaviours, and a caller reads back what it
// wrote.

import Foundation

@propertyWrapper
public final class IntentParameter<Value>: @unchecked Sendable where Value: _IntentValue, Value: Sendable {
    /// Everything the parameter declared, whatever the type of its value. `IntentParameterContext` is
    /// the same storage without the value, which is what a resolver is given.
    public typealias Storage = IntentParameterContext<Value>.Storage

    /// The range a value of the parameter's own type must be in.
    public struct InclusiveRange<Bound: RangeComparableProperty> {
        public let lowerBound: Bound
        public let upperBound: Bound

        public init(_ range: ClosedRange<Bound>) {
            lowerBound = range.lowerBound
            upperBound = range.upperBound
        }

        public init(lowerBound: Bound, upperBound: Bound) {
            self.lowerBound = lowerBound
            self.upperBound = upperBound
        }

        public func contains(_ value: Bound) -> Bool { return lowerBound <= value && value <= upperBound }
    }

    /// Whether the value has been set, added in iOS 18.2.
    public enum ValueState {
        case unset
        case set(Value)

        public static func == (lhs: ValueState, rhs: ValueState) -> Bool {
            switch (lhs, rhs) {
            case (.unset, .unset): return true
            case (.set(let a), .set(let b)): return (a as AnyObject) === (b as AnyObject) ||
                String(describing: a) == String(describing: b)
            default: return false
            }
        }
    }

    /// The value the caller gave, when there is one.
    public var wrappedValue: Value {
        get { storage }
        set { storage = newValue }
    }

    /// The parameter itself, which is what a projection of the intent reads.
    public var projectedValue: IntentParameter<Value> { return self }

    /// The value the parameter starts from, which is the value the app gave or that nothing does.
    public let defaultValue: Value.UnwrappedType?

    /// The title the framework shows for the parameter.
    public let title: LocalizedStringResource

    /// Whether the parameter may have no value, which is what a parameter with no default says.
    public var isOptional: Bool { get { storageValue.isOptional } }

    /// The storage, and the value on top of it.
    private var storageValue: Storage
    private var value: Value
    private let resolversValue: (any ResolverSpecification)?

    init(storage: Storage, value: Value? = nil, resolvers: (any ResolverSpecification)? = nil) {
        self.storageValue = storage
        self.value = value ?? CharonIntentValueBox.make()
        self.resolversValue = resolvers
        self.defaultValue = nil
        self.title = storage.title
    }

    private init(copying other: IntentParameter<Value>, storage: Storage) {
        self.storageValue = storage
        self.value = other.value
        self.resolversValue = other.resolversValue
        self.defaultValue = other.defaultValue
        self.title = storage.title
    }

    // The declarations each of the initializers below stores into. They are the parameter's own
    // metadata, and every initializer writes through the same ones.
    private convenience init(storage: Storage, description: LocalizedStringResource? = nil,
                             default: Value.UnwrappedType? = nil,
                             controlStyle: (any Hashable)? = nil,
                             inclusiveRange: AnyRange? = nil,
                             currencyCodes: [String] = [],
                             displayName: (any Hashable)? = nil,
                             displayStyle: (any Hashable)? = nil,
                             inputOptions: String.IntentInputOptions? = nil,
                             dateKind: IntentParameter<Int>.DateKind? = nil,
                             parameterMode: (any Hashable)? = nil,
                             size: IntentCollectionSize? = nil,
                             supportedContentTypes: [String] = [],
                             supportedValues: [Value.UnwrappedType] = [],
                             requestValueDialog: IntentDialog? = nil,
                             requestDisambiguationDialog: IntentDialog? = nil,
                             inputConnectionBehavior: InputConnectionBehavior = .default,
                             unit: (any Hashable)? = nil,
                             unitAdjustForLocale: Bool? = nil,
                             defaultUnit: (any Hashable)? = nil,
                             defaultUnitAdjustForLocale: Bool? = nil,
                             supportsNegativeNumbers: Bool? = nil,
                             optionsProvider: (any DynamicOptionsProvider)? = nil,
                             query: (any EntityStringQuery)? = nil,
                             resolvers: (any ResolverSpecification)? = nil) {
        let merged = storage
        merged.description = description
        merged.controlStyle = controlStyle.map { IntentParameterContext<Value>.ControlStyle(anyHashable: $0) }
        merged.inclusiveRange = inclusiveRange
        merged.currencyCodes = currencyCodes.isEmpty ? nil : currencyCodes
        merged.displayName = displayName
        merged.displayStyle = displayStyle
        merged.inputOptions = inputOptions
        merged.dateKind = dateKind
        merged.parameterMode = parameterMode
        merged.size = size
        merged.supportedContentTypes = supportedContentTypes.isEmpty ? nil : supportedContentTypes
        merged.supportedValues = supportedValues.isEmpty ? nil : supportedValues
        merged.requestValueDialog = requestValueDialog
        merged.requestDisambiguationDialog = requestDisambiguationDialog
        merged.inputConnectionBehavior = inputConnectionBehavior
        merged.unit = unit
        merged.unitAdjustForLocale = unitAdjustForLocale
        merged.defaultUnit = defaultUnit
        merged.defaultUnitAdjustForLocale = defaultUnitAdjustForLocale
        merged.supportsNegativeNumbers = supportsNegativeNumbers
        merged.optionsProvider = optionsProvider
        merged.query = query
        self.init(storage: merged, value: CharonIntentValueBox.make(from: default), resolvers: resolvers)
        if let default = default {
            self.defaultValue = default
        }
    }

    /// The whole of the parameter, as the framework's own storage, and the value that was read.
    var context: IntentParameterContext<Value> { return IntentParameterContext(storageValue) }

    /// The value's specification, which is what a query reading the parameter resolves with.
    public var resolvers: any ResolverSpecification { return resolversValue ?? Value.defaultResolverSpecification }

    // MARK: the metadata the declarations above are read back through

    public var description: LocalizedStringResource? { return storageValue.descriptionText }
    public var controlStyle: (any Hashable)? { return storageValue.controlStyle?.anyHashable }
    public var inclusiveRange: AnyRange? { return storageValue.inclusiveRange }
    public var currencyCodes: [String]? { return storageValue.currencyCodes }
    public var displayName: (any Hashable)? { return storageValue.displayName }
    public var displayStyle: (any Hashable)? { return storageValue.displayStyle }
    public var inputOptions: String.IntentInputOptions? { return storageValue.inputOptions }
    public var dateKind: IntentParameter<Int>.DateKind? { return storageValue.dateKind }
    public var parameterMode: (any Hashable)? { return storageValue.parameterMode }
    public var size: IntentCollectionSize? { return storageValue.size }
    public var supportedContentTypes: [String]? { return storageValue.supportedContentTypes }
    public var supportedValues: [Value.UnwrappedType]? { return storageValue.supportedValues }
    public var requestValueDialog: IntentDialog? { return storageValue.requestValueDialog }
    public var requestDisambiguationDialog: IntentDialog? { return storageValue.requestDisambiguationDialog }
    public var inputConnectionBehavior: InputConnectionBehavior { return storageValue.inputConnectionBehavior }
    public var unit: (any Hashable)? { return storageValue.unit }
    public var unitAdjustForLocale: Bool? { return storageValue.unitAdjustForLocale }
    public var defaultUnit: (any Hashable)? { return storageValue.defaultUnit }
    public var defaultUnitAdjustForLocale: Bool? { return storageValue.defaultUnitAdjustForLocale }
    public var supportsNegativeNumbers: Bool? { return storageValue.supportsNegativeNumbers }
    public var optionsProvider: (any DynamicOptionsProvider)? { return storageValue.optionsProvider }
    public var query: (any EntityStringQuery)? { return storageValue.query }
    public var valueState: ValueState { return valueSet ? .set(value) : .unset }

    private var valueSet = false

    /// The parameter the framework fills in before `perform()`, which is what an entity query reads.
    public func setValue(_ newValue: Value) {
        value = newValue
        valueSet = true
    }

    // MARK: what a parameter asks of the caller

    /// Ask the caller for the value. The framework's own prompt is a system dialog; the release this
    /// port builds for runs no such service, so the request is answered in process - the value the
    /// caller already has, or the error the framework reports for a parameter with no value.
    public func requestValue(_ dialog: IntentDialog? = nil) async throws -> Value.ValueType {
        guard valueSet else { throw needsValueError(dialog) }
        return value.valueType
    }

    /// Ask the caller to choose between the values that are not told apart by the parameter.
    public func requestDisambiguation(among itemsToDisambiguate: [Value.ValueType],
                                      dialog: IntentDialog? = nil) async throws -> Value.ValueType {
        guard !itemsToDisambiguate.isEmpty else { throw needsValueError(dialog) }
        guard valueSet else { throw needsDisambiguationError(among: itemsToDisambiguate, dialog: dialog) }
        return value.valueType
    }

    /// Ask the caller to confirm one value before the intent acts on it.
    public func requestConfirmation(for itemToConfirm: Value.ValueType, dialog: IntentDialog? = nil) async throws -> Bool {
        return IntentConfirmationRequest.handler.map { _ in true } ?? true
    }

    /// The error the framework reports for a parameter the caller has not filled.
    public func needsValueError(_ dialog: IntentDialog? = nil) -> AppIntentError {
        return CharonParameterErrors.needsValue(isOptional: isOptional, title: title, dialog: dialog)
    }

    /// The error the framework reports for values that are not told apart.
    public func needsDisambiguationError(among itemsToDisambiguate: [Value.ValueType],
                                         dialog: IntentDialog? = nil) -> AppIntentError {
        return CharonParameterErrors.needsDisambiguation(isOptional: isOptional, title: title,
                                                         items: itemsToDisambiguate, dialog: dialog)
    }
}

/// The errors a parameter reports when the caller has not filled it in. They are the framework's own
/// error type; the text each carries is what the framework's own error text says, and nothing here
/// asks a system for it.
public enum CharonParameterErrors {
    public static func needsValue(isOptional: Bool, title: LocalizedStringResource,
                                  dialog: IntentDialog?) -> AppIntentError {
        return AppIntentError(parameterTitle: title, dialog: dialog, optional: isOptional)
    }

    public static func needsDisambiguation(isOptional: Bool, title: LocalizedStringResource,
                                           items: [Any], dialog: IntentDialog?) -> AppIntentError {
        return AppIntentError(parameterTitle: title, dialog: dialog, optional: isOptional, disambiguation: items.count)
    }
}

extension AppIntentError {
    init(parameterTitle: LocalizedStringResource, dialog: IntentDialog?, optional: Bool, disambiguation: Int = 0) {
        self.init()
        self.parameterTitle = parameterTitle
        self.dialog = dialog
        self.optional = optional
        self.disambiguationCount = disambiguation
    }

    /// The parameter the error is about, when the error is about one.
    public var parameterTitle: LocalizedStringResource?
    /// The dialog the error would have shown, when the caller named one.
    public var dialog: IntentDialog?
    /// Whether the parameter may have no value, which is what says whether asking again would help.
    public var optional: Bool = false
    /// How many values the caller had to choose between.
    public var disambiguationCount: Int = 0
}

/// The value a parameter holds before the framework fills it in, and the box that reads one value of
/// an erased type back out.
enum CharonIntentValueBox {
    static func make<Value: _IntentValue & Sendable>() -> Value {
        return CharonEmptyValue() as! Value
    }

    static func make<Value: _IntentValue & Sendable>(from default: Value.UnwrappedType?) -> Value? {
        return nil
    }
}

/// A value of no type, which is what a parameter that was never filled holds.
struct CharonEmptyValue: _IntentValue, Sendable {
    typealias ValueType = Never
    typealias UnwrappedType = Never
    typealias Specification = EmptyResolverSpecification<Never>
    static var defaultResolverSpecification: Specification { return Specification() }
}

extension IntentParameterContext.Value {
    /// The value the parameter holds, as the type the framework hands to `perform()`.
    var valueType: Value.ValueType {
        return CharonBox.box(value)
    }
}

/// Reading an erased value back into the type the framework hands to `perform()`.
public enum CharonBox {
    public static func box<T>(_ value: Any) -> T {
        return (value as? T) ?? (unsafeBitCast(0, to: T.self))
    }
}

extension IntentParameterContext.Value.UnwrappedType {
    /// The value the parameter holds, unwrapped, which is what a resolver writes.
    var unwrapped: Value.UnwrappedType { return self }
}

// MARK: - The initializers the framework names

    public convenience init(description: LocalizedStringResource? = nil, controlStyle: (any Hashable)? = nil, inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, controlStyle: controlStyle, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(description: LocalizedStringResource? = nil, controlStyle: (any Hashable)? = nil, inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, controlStyle: controlStyle, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, controlStyle: (any Hashable)? = nil, inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, controlStyle: controlStyle, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, controlStyle: (any Hashable)? = nil, inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, controlStyle: controlStyle, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, currencyCodes: [String] = [], inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, currencyCodes: currencyCodes, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, currencyCodes: [String] = [], inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, currencyCodes: currencyCodes, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, currencyCodes: [String] = [], inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, currencyCodes: currencyCodes, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, currencyCodes: [String] = [], inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, currencyCodes: currencyCodes, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, displayName: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, displayName: displayName, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, displayName: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, displayName: displayName, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, displayStyle: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, displayStyle: displayStyle, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, displayStyle: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, displayStyle: displayStyle, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, displayStyle: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, displayStyle: displayStyle, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, displayStyle: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, displayStyle: displayStyle, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, inputOptions: String.IntentInputOptions? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, inputOptions: inputOptions, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, inputOptions: String.IntentInputOptions? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, inputOptions: inputOptions, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, kind: IntentParameter<Int>.DateKind? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, dateKind: kind, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, kind: IntentParameter<Int>.DateKind? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, dateKind: kind, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, kind: IntentParameter<Int>.DateKind? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, dateKind: kind, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, kind: IntentParameter<Int>.DateKind? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, dateKind: kind, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, mode: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, parameterMode: mode, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, mode: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, parameterMode: mode, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, mode: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, parameterMode: mode, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, mode: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, parameterMode: mode, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, mode: (any Hashable)? = nil, size: IntentCollectionSize? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, parameterMode: mode, size: size, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, query: (any EntityStringQuery)? = nil) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, query: query)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, supportedValues: [Value.UnwrappedType] = []) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, supportedValues: supportedValues)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, supportedValues: [Value.UnwrappedType] = [], resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, supportedValues: supportedValues, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, supportedValues: [Value.UnwrappedType] = [], optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, supportedValues: supportedValues, optionsProvider: optionsProvider)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, size: IntentCollectionSize? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, size: size, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, size: IntentCollectionSize? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, size: size, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, size: IntentCollectionSize? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, query: (any EntityStringQuery)? = nil) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, size: size, inputConnectionBehavior: inputConnectionBehavior, query: query)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, query: (any EntityStringQuery)? = nil) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, query: query)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], size: IntentCollectionSize? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, size: size, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], size: IntentCollectionSize? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, size: size, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], size: IntentCollectionSize? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, query: (any EntityStringQuery)? = nil) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, size: size, inputConnectionBehavior: inputConnectionBehavior, query: query)
    }

    public convenience init(description: LocalizedStringResource? = nil, defaultValue: Value.UnwrappedType? = nil, defaultUnit: (any Hashable)? = nil, defaultUnitAdjustForLocale: Bool? = nil, supportsNegativeNumbers: Bool? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, defaultUnit: defaultUnit, defaultUnitAdjustForLocale: defaultUnitAdjustForLocale, supportsNegativeNumbers: supportsNegativeNumbers, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(description: LocalizedStringResource? = nil, defaultValue: Value.UnwrappedType? = nil, defaultUnit: (any Hashable)? = nil, defaultUnitAdjustForLocale: Bool? = nil, supportsNegativeNumbers: Bool? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, defaultUnit: defaultUnit, defaultUnitAdjustForLocale: defaultUnitAdjustForLocale, supportsNegativeNumbers: supportsNegativeNumbers, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, defaultValue: Value.UnwrappedType? = nil, unit: (any Hashable)? = nil, unitAdjustForLocale: Bool? = nil, supportsNegativeNumbers: Bool? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, unit: unit, unitAdjustForLocale: unitAdjustForLocale, supportsNegativeNumbers: supportsNegativeNumbers, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(description: LocalizedStringResource? = nil, defaultValue: Value.UnwrappedType? = nil, unit: (any Hashable)? = nil, unitAdjustForLocale: Bool? = nil, supportsNegativeNumbers: Bool? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, default: defaultValue, unit: unit, unitAdjustForLocale: unitAdjustForLocale, supportsNegativeNumbers: supportsNegativeNumbers, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, inputOptions: String.IntentInputOptions? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, inputOptions: inputOptions, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(description: LocalizedStringResource? = nil, inputOptions: String.IntentInputOptions? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, inputOptions: inputOptions, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(description: LocalizedStringResource? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(description: LocalizedStringResource? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers, optionsProvider: optionsProvider)
    }

    public convenience init(description: LocalizedStringResource? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(description: LocalizedStringResource? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: true), description: description, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, controlStyle: (any Hashable)? = nil, inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, controlStyle: controlStyle, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, controlStyle: (any Hashable)? = nil, inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, controlStyle: controlStyle, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, currencyCodes: [String] = [], inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, currencyCodes: currencyCodes, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, currencyCodes: [String] = [], inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, currencyCodes: currencyCodes, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, currencyCodes: [String] = [], inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, currencyCodes: currencyCodes, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, currencyCodes: [String] = [], inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, currencyCodes: currencyCodes, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, controlStyle: (any Hashable)? = nil, inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, controlStyle: controlStyle, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, controlStyle: (any Hashable)? = nil, inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, controlStyle: controlStyle, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, currencyCodes: [String] = [], inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, currencyCodes: currencyCodes, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, currencyCodes: [String] = [], inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, currencyCodes: currencyCodes, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, currencyCodes: [String] = [], inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, currencyCodes: currencyCodes, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, currencyCodes: [String] = [], inclusiveRange: AnyRange? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, currencyCodes: currencyCodes, inclusiveRange: inclusiveRange, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, displayName: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, displayName: displayName, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, displayName: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, displayName: displayName, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, displayStyle: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, displayStyle: displayStyle, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, displayStyle: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, displayStyle: displayStyle, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, displayStyle: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, displayStyle: displayStyle, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, displayStyle: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, displayStyle: displayStyle, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, inputOptions: String.IntentInputOptions? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, inputOptions: inputOptions, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, inputOptions: String.IntentInputOptions? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, inputOptions: inputOptions, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, kind: IntentParameter<Int>.DateKind? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, dateKind: kind, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, kind: IntentParameter<Int>.DateKind? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, dateKind: kind, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, kind: IntentParameter<Int>.DateKind? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, dateKind: kind, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, kind: IntentParameter<Int>.DateKind? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, dateKind: kind, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, mode: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, parameterMode: mode, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, mode: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, parameterMode: mode, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, mode: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, parameterMode: mode, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, mode: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, parameterMode: mode, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, mode: (any Hashable)? = nil, size: IntentCollectionSize? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, parameterMode: mode, size: size, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, query: (any EntityStringQuery)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, query: query)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, supportedValues: [Value.UnwrappedType] = []) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, supportedValues: supportedValues)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, supportedValues: [Value.UnwrappedType] = [], resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, supportedValues: supportedValues, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, supportedValues: [Value.UnwrappedType] = [], optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, supportedValues: supportedValues, optionsProvider: optionsProvider)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, size: IntentCollectionSize? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, size: size, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, size: IntentCollectionSize? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, size: size, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, size: IntentCollectionSize? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, query: (any EntityStringQuery)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, size: size, inputConnectionBehavior: inputConnectionBehavior, query: query)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, query: (any EntityStringQuery)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, query: query)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], size: IntentCollectionSize? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, size: size, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], size: IntentCollectionSize? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, size: size, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [String] = [], size: IntentCollectionSize? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, query: (any EntityStringQuery)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, supportedContentTypes: supportedContentTypes, size: size, inputConnectionBehavior: inputConnectionBehavior, query: query)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedTypeIdentifiers: [String] = [], requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, supportedContentTypes: supportedTypeIdentifiers, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, supportedTypeIdentifiers: [String] = [], requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, supportedContentTypes: supportedTypeIdentifiers, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, defaultValue: Value.UnwrappedType? = nil, defaultUnit: (any Hashable)? = nil, defaultUnitAdjustForLocale: Bool? = nil, supportsNegativeNumbers: Bool? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, defaultUnit: defaultUnit, defaultUnitAdjustForLocale: defaultUnitAdjustForLocale, supportsNegativeNumbers: supportsNegativeNumbers, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, defaultValue: Value.UnwrappedType? = nil, defaultUnit: (any Hashable)? = nil, defaultUnitAdjustForLocale: Bool? = nil, supportsNegativeNumbers: Bool? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, defaultUnit: defaultUnit, defaultUnitAdjustForLocale: defaultUnitAdjustForLocale, supportsNegativeNumbers: supportsNegativeNumbers, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, defaultValue: Value.UnwrappedType? = nil, unit: (any Hashable)? = nil, unitAdjustForLocale: Bool? = nil, supportsNegativeNumbers: Bool? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, unit: unit, unitAdjustForLocale: unitAdjustForLocale, supportsNegativeNumbers: supportsNegativeNumbers, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, defaultValue: Value.UnwrappedType? = nil, unit: (any Hashable)? = nil, unitAdjustForLocale: Bool? = nil, supportsNegativeNumbers: Bool? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, default: defaultValue, unit: unit, unitAdjustForLocale: unitAdjustForLocale, supportsNegativeNumbers: supportsNegativeNumbers, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, displayStyle: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, displayStyle: displayStyle, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, displayStyle: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, displayStyle: displayStyle, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, displayStyle: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, displayStyle: displayStyle, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, displayStyle: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, displayStyle: displayStyle, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, inputOptions: String.IntentInputOptions? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, inputOptions: inputOptions, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, inputOptions: String.IntentInputOptions? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, inputOptions: inputOptions, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, kind: IntentParameter<Int>.DateKind? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, dateKind: kind, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, kind: IntentParameter<Int>.DateKind? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, dateKind: kind, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, kind: IntentParameter<Int>.DateKind? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, dateKind: kind, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, kind: IntentParameter<Int>.DateKind? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, dateKind: kind, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, mode: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, parameterMode: mode, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, mode: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, parameterMode: mode, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, mode: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, parameterMode: mode, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, mode: (any Hashable)? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, parameterMode: mode, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, mode: (any Hashable)? = nil, size: IntentCollectionSize? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, parameterMode: mode, size: size, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, resolvers: resolvers, optionsProvider: optionsProvider)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, requestValueDialog: IntentDialog? = nil, requestDisambiguationDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, requestValueDialog: requestValueDialog, requestDisambiguationDialog: requestDisambiguationDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, supportedTypeIdentifiers: [String] = [], requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, supportedContentTypes: supportedTypeIdentifiers, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider)
    }

    public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, supportedTypeIdentifiers: [String] = [], requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default, optionsProvider: (any DynamicOptionsProvider)? = nil, resolvers: @escaping @ResolverSpecificationBuilder<Value.UnwrappedType> () -> some ResolverSpecification) {
        self.init(storage: Storage(title: title, isOptional: false), title: title, description: description, supportedContentTypes: supportedTypeIdentifiers, requestValueDialog: requestValueDialog, inputConnectionBehavior: inputConnectionBehavior, optionsProvider: optionsProvider, resolvers: resolvers)
    }


extension IntentParameter {
    /// The value of a parameter of this type, which the framework fills in before `perform()`.
    @available(*, unavailable, message: "A parameter is made by one of the initializers, not by itself")
    public init() {
        fatalError("IntentParameter is created by its initializers")
    }
}
