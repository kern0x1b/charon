// What the release's own value types are when a parameter carries one, and the builder that turns a
// list of resolvers into the specification a parameter carries.
//
// Each conformance is the real conversion, not a marker: `String`'s resolver is the identity, `Int`'s
// reads the string the release's own `Int.init` reads, `URL`'s is `URL(string:)`, and a parameter that
// asks for a value gets the value the release's type would give.

import Foundation

/// A resolver that hands a value through unchanged, which is what a type that is already its own
/// string form needs.
struct IdentityResolver: Resolver {
    func resolve(from input: String, context: IntentParameterContext<String>) async throws -> String? { return input }
    static func == (a: IdentityResolver, b: IdentityResolver) -> Bool { return true }
    func hash(into hasher: inout Hasher) {}
}

/// The specification of the resolvers of a parameter, built by `ResolverSpecificationBuilder` and
/// carrying the resolvers themselves, so that a query reading a parameter runs the same resolvers the
/// parameter was declared with.
@resultBuilder
public enum ResolverSpecificationBuilder<Property> where Property: _IntentValue {}

extension ResolverSpecificationBuilder {
    public static func buildExpression<ResolverType>(_ expression: ResolverType) -> ResolverType
        where Property == ResolverType.Output, ResolverType: Resolver {
        return expression
    }

    public static func buildBlock() -> some ResolverSpecification {
        return EmptyResolverSpecification<Property>()
    }

    public static func buildBlock<R0>(_ r0: R0) -> some ResolverSpecification where R0: Resolver {
        return Specification<Property, R0>([r0])
    }

    public static func buildBlock<R0, R1>(_ r0: R0, _ r1: R1) -> some ResolverSpecification
        where R0: Resolver, R1: Resolver {
        return Specification<Property, R0, R1>([r0, r1])
    }

    public static func buildBlock<R0, R1, R2>(_ r0: R0, _ r1: R1, _ r2: R2) -> some ResolverSpecification
        where R0: Resolver, R1: Resolver, R2: Resolver {
        return Specification<Property, R0, R1, R2>([r0, r1, r2])
    }

    public static func buildBlock<R0, R1, R2, R3>(_ r0: R0, _ r1: R1, _ r2: R2,
                                                   _ r3: R3) -> some ResolverSpecification
        where R0: Resolver, R1: Resolver, R2: Resolver, R3: Resolver {
        return Specification<Property, R0, R1, R2, R3>([r0, r1, r2, r3])
    }

    public static func buildBlock<R0, R1, R2, R3, R4>(_ r0: R0, _ r1: R1, _ r2: R2, _ r3: R3,
                                                       _ r4: R4) -> some ResolverSpecification
        where R0: Resolver, R1: Resolver, R2: Resolver, R3: Resolver, R4: Resolver {
        return Specification<Property, R0, R1, R2, R3, R4>([r0, r1, r2, r3, r4])
    }

    public static func buildBlock<R0, R1, R2, R3, R4, R5>(_ r0: R0, _ r1: R1, _ r2: R2, _ r3: R3, _ r4: R4,
                                                            _ r5: R5) -> some ResolverSpecification
        where R0: Resolver, R1: Resolver, R2: Resolver, R3: Resolver, R4: Resolver, R5: Resolver {
        return Specification<Property, R0, R1, R2, R3, R4, R5>([r0, r1, r2, r3, r4, r5])
    }

    public static func buildBlock<R0, R1, R2, R3, R4, R5, R6>(_ r0: R0, _ r1: R1, _ r2: R2, _ r3: R3, _ r4: R4,
                                                                _ r5: R5,
                                                                _ r6: R6) -> some ResolverSpecification
        where R0: Resolver, R1: Resolver, R2: Resolver, R3: Resolver, R4: Resolver, R5: Resolver, R6: Resolver {
        return Specification<Property, R0, R1, R2, R3, R4, R5, R6>([r0, r1, r2, r3, r4, r5, r6])
    }

    public static func buildBlock<R0, R1, R2, R3, R4, R5, R6, R7>(_ r0: R0, _ r1: R1, _ r2: R2, _ r3: R3, _ r4: R4,
                                                                    _ r5: R5, _ r6: R6,
                                                                    _ r7: R7) -> some ResolverSpecification
        where R0: Resolver, R1: Resolver, R2: Resolver, R3: Resolver, R4: Resolver, R5: Resolver, R6: Resolver,
              R7: Resolver {
        return Specification<Property, R0, R1, R2, R3, R4, R5, R6, R7>([r0, r1, r2, r3, r4, r5, r6, r7])
    }

    public static func buildBlock<R0, R1, R2, R3, R4, R5, R6, R7, R8>(_ r0: R0, _ r1: R1, _ r2: R2, _ r3: R3,
                                                                        _ r4: R4, _ r5: R5, _ r6: R6, _ r7: R7,
                                                                        _ r8: R8) -> some ResolverSpecification
        where R0: Resolver, R1: Resolver, R2: Resolver, R3: Resolver, R4: Resolver, R5: Resolver, R6: Resolver,
              R7: Resolver, R8: Resolver {
        return Specification<Property, R0, R1, R2, R3, R4, R5, R6, R7, R8>([r0, r1, r2, r3, r4, r5, r6, r7, r8])
    }

    public static func buildBlock<R0, R1, R2, R3, R4, R5, R6, R7, R8, R9>(_ r0: R0, _ r1: R1, _ r2: R2, _ r3: R3,
                                                                            _ r4: R4, _ r5: R5, _ r6: R6, _ r7: R7,
                                                                            _ r8: R8,
                                                                            _ r9: R9) -> some ResolverSpecification
        where R0: Resolver, R1: Resolver, R2: Resolver, R3: Resolver, R4: Resolver, R5: Resolver, R6: Resolver,
              R7: Resolver, R8: Resolver, R9: Resolver {
        return Specification<Property, R0, R1, R2, R3, R4, R5, R6, R7, R8, R9>([r0, r1, r2, r3, r4, r5, r6, r7, r8, r9])
    }

    public static func buildBlock<R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10>(_ r0: R0, _ r1: R1, _ r2: R2, _ r3: R3,
                                                                                 _ r4: R4, _ r5: R5, _ r6: R6, _ r7: R7,
                                                                                 _ r8: R8, _ r9: R9,
                                                                                 _ r10: R10) -> some ResolverSpecification
        where R0: Resolver, R1: Resolver, R2: Resolver, R3: Resolver, R4: Resolver, R5: Resolver, R6: Resolver,
              R7: Resolver, R8: Resolver, R9: Resolver, R10: Resolver {
        return Specification<Property, R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10>(
            [r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10])
    }

    public static func buildBlock<R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11>(
        _ r0: R0, _ r1: R1, _ r2: R2, _ r3: R3, _ r4: R4, _ r5: R5, _ r6: R6, _ r7: R7, _ r8: R8, _ r9: R9, _ r10: R10,
        _ r11: R11) -> some ResolverSpecification
        where R0: Resolver, R1: Resolver, R2: Resolver, R3: Resolver, R4: Resolver, R5: Resolver, R6: Resolver,
              R7: Resolver, R8: Resolver, R9: Resolver, R10: Resolver, R11: Resolver {
        return Specification<Property, R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11>(
            [r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11])
    }

    public static func buildBlock<R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12>(
        _ r0: R0, _ r1: R1, _ r2: R2, _ r3: R3, _ r4: R4, _ r5: R5, _ r6: R6, _ r7: R7, _ r8: R8, _ r9: R9, _ r10: R10,
        _ r11: R11, _ r12: R12) -> some ResolverSpecification
        where R0: Resolver, R1: Resolver, R2: Resolver, R3: Resolver, R4: Resolver, R5: Resolver, R6: Resolver,
              R7: Resolver, R8: Resolver, R9: Resolver, R10: Resolver, R11: Resolver, R12: Resolver {
        return Specification<Property, R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12>(
            [r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12])
    }

    public static func buildBlock<R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R13>(
        _ r0: R0, _ r1: R1, _ r2: R2, _ r3: R3, _ r4: R4, _ r5: R5, _ r6: R6, _ r7: R7, _ r8: R8, _ r9: R9, _ r10: R10,
        _ r11: R11, _ r12: R12, _ r13: R13) -> some ResolverSpecification
        where R0: Resolver, R1: Resolver, R2: Resolver, R3: Resolver, R4: Resolver, R5: Resolver, R6: Resolver,
              R7: Resolver, R8: Resolver, R9: Resolver, R10: Resolver, R11: Resolver, R12: Resolver, R13: Resolver {
        return Specification<Property, R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R13>(
            [r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13])
    }

    public static func buildBlock<R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R13, R14>(
        _ r0: R0, _ r1: R1, _ r2: R2, _ r3: R3, _ r4: R4, _ r5: R5, _ r6: R6, _ r7: R7, _ r8: R8, _ r9: R9, _ r10: R10,
        _ r11: R11, _ r12: R12, _ r13: R13, _ r14: R14) -> some ResolverSpecification
        where R0: Resolver, R1: Resolver, R2: Resolver, R3: Resolver, R4: Resolver, R5: Resolver, R6: Resolver,
              R7: Resolver, R8: Resolver, R9: Resolver, R10: Resolver, R11: Resolver, R12: Resolver, R13: Resolver,
              R14: Resolver {
        return Specification<Property, R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R13, R14>(
            [r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14])
    }

    /// The specification a set of resolvers makes, carrying them so that a query runs the same
    /// resolvers the parameter was declared with.
    public struct Specification<Output, repeat each R>: ResolverSpecification {
        public typealias Element = any Resolver

        let resolvers: [any Resolver]

        init(_ resolvers: [any Resolver]) {
            self.resolvers = resolvers
        }

        public func makeIterator() -> [any Resolver].Iterator { return resolvers.makeIterator() }

        public static func == (lhs: Specification<Output, repeat each R>, rhs: Specification<Output, repeat each R>) -> Bool {
            return lhs.resolvers.count == rhs.resolvers.count
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(resolvers.count)
        }
    }
}

extension ResolverSpecificationBuilder {
    public static func buildPartialBlock<R>(first: R) -> ResolverSpecificationBuilder<Property>.Specification<Property, R>
        where R: Resolver {
        return Specification<Property, R>([first])
    }

    public static func buildPartialBlock<each Accumulated, R>(accumulated: ResolverSpecificationBuilder<Property>
        .Specification<Property, repeat each Accumulated>,
                                                              next: R) -> ResolverSpecificationBuilder<Property>
        .Specification<Property, repeat each Accumulated, R> where repeat each Accumulated: Resolver, R: Resolver {
        let before = Array(accumulated)
        return Specification<Property, repeat each Accumulated, R>(before + [next])
    }
}

// MARK: - The values a parameter can carry

extension String: _IntentValue {
    public typealias ValueType = String
    public typealias UnwrappedType = String
    public typealias Specification = ResolverSpecificationBuilder<String>.Specification<String, IdentityResolver>

    public static var defaultResolverSpecification: Specification {
        return Specification([IdentityResolver()])
    }

    /// The string a shortcut writes a string parameter as, which is the string itself.
    public var urlRepresentationParameter: String { return self }
}

extension Int: _IntentValue, RangeComparableProperty {
    public typealias ValueType = Int
    public typealias UnwrappedType = Int
    public typealias Specification = ResolverSpecificationBuilder<Int>.Specification<Int, IntResolver>

    public static var defaultResolverSpecification: Specification {
        return Specification([IntResolver()])
    }

    /// The string a shortcut writes an integer parameter as, which is the release's own number.
    public var urlRepresentationParameter: Int { return self }
    /// The string an entity identifier of this type is written as, which is the release's own number.
    public static var entityIdentifierString: String { return String(0) }
    /// The entity identifier of a value of this type, which is the value written as a string.
    public static func entityIdentifier(for value: Int) -> EntityIdentifier {
        return EntityIdentifier(for: value, identifier: String(value))
    }
}

extension Float: _IntentValue {
    public typealias ValueType = Float
    public typealias UnwrappedType = Float
    public typealias Specification = ResolverSpecificationBuilder<Float>.Specification<Float, FloatResolver>

    public static var defaultResolverSpecification: Specification {
        return Specification([FloatResolver()])
    }

    /// The string an entity identifier of this type is written as, which is the release's own number.
    public static var entityIdentifierString: String { return String(Float(0)) }
    /// The entity identifier of a value of this type, which is the value written as a string.
    public static func entityIdentifier(for value: Float) -> EntityIdentifier {
        return EntityIdentifier(for: value, identifier: String(value))
    }
}

extension Double: _IntentValue, RangeComparableProperty {
    public typealias ValueType = Double
    public typealias UnwrappedType = Double
    public typealias Specification = ResolverSpecificationBuilder<Double>.Specification<Double, DoubleResolver>

    public static var defaultResolverSpecification: Specification {
        return Specification([DoubleResolver()])
    }
}

extension Bool: _IntentValue {
    public typealias ValueType = Bool
    public typealias UnwrappedType = Bool
    public typealias Specification = ResolverSpecificationBuilder<Bool>.Specification<Bool, BoolFromStringResolver>

    public static var defaultResolverSpecification: Specification {
        return Specification([BoolFromStringResolver()])
    }
}

extension URL: _IntentValue {
    public typealias ValueType = URL
    public typealias UnwrappedType = URL
    public typealias Specification = ResolverSpecificationBuilder<URL>.Specification<URL, URLFromStringResolver>

    public static var defaultResolverSpecification: Specification {
        return Specification([URLFromStringResolver()])
    }

    /// The string a shortcut writes a URL parameter as, from iOS 18, which is the URL's own string.
    public var urlRepresentationParameter: String { return absoluteString }
}

extension UUID: _IntentValue {
    public typealias ValueType = UUID
    public typealias UnwrappedType = UUID
    public typealias Specification = ResolverSpecificationBuilder<UUID>.Specification<UUID, UUIDResolver>

    public static var defaultResolverSpecification: Specification {
        return Specification([UUIDResolver()])
    }

    /// The string an entity identifier of this type is written as, which is the release's own
    /// `uuidString`.
    public static var entityIdentifierString: String { return UUID().uuidString }
    /// The entity identifier of a value of this type, which is the value's own `uuidString`.
    public static func entityIdentifier(for value: UUID) -> EntityIdentifier {
        return EntityIdentifier(for: value, identifier: value.uuidString)
    }
}

extension Date: _IntentValue, RangeComparableProperty {
    public typealias ValueType = Date
    public typealias UnwrappedType = Date
    public typealias Specification = ResolverSpecificationBuilder<Date>.Specification<Date, DateResolver>

    public static var defaultResolverSpecification: Specification {
        return Specification([DateResolver()])
    }
}

extension DateComponents: _IntentValue {
    public typealias ValueType = DateComponents
    public typealias UnwrappedType = DateComponents
    public typealias Specification = ResolverSpecificationBuilder<DateComponents>
        .Specification<DateComponents, DateComponentsResolver>

    public static var defaultResolverSpecification: Specification {
        return Specification([DateComponentsResolver()])
    }
}

/// Reads a `String` into a `UUID`, with the release's own `UUID(uuidString:)`.
struct UUIDResolver: Resolver {
    func resolve(from input: String, context: IntentParameterContext<UUID>) async throws -> UUID? {
        return UUID(uuidString: input)
    }

    static func == (a: UUIDResolver, b: UUIDResolver) -> Bool { return true }
    func hash(into hasher: inout Hasher) {}
}

/// Reads a `String` into a `Float`.
struct FloatResolver: Resolver {
    func resolve(from input: String, context: IntentParameterContext<Float>) async throws -> Float? {
        return Float(input)
    }

    static func == (a: FloatResolver, b: FloatResolver) -> Bool { return true }
    func hash(into hasher: inout Hasher) {}
}

/// Reads a `String` into a `Date`, with the spellings the release's own `Date` parsers take.
struct DateResolver: Resolver {
    func resolve(from input: String, context: IntentParameterContext<Date>) async throws -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: input) { return date }
        }
        return nil
    }

    static func == (a: DateResolver, b: DateResolver) -> Bool { return true }
    func hash(into hasher: inout Hasher) {}
}

/// Reads a `String` into `DateComponents`, by the same parsers `DateResolver` uses.
struct DateComponentsResolver: Resolver {
    func resolve(from input: String,
                 context: IntentParameterContext<DateComponents>) async throws -> DateComponents? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: input) {
                let calendar = Calendar(identifier: .gregorian)
                return calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            }
        }
        return nil
    }

    static func == (a: DateComponentsResolver, b: DateComponentsResolver) -> Bool { return true }
    func hash(into hasher: inout Hasher) {}
}

extension Optional: _IntentValue where Wrapped: _IntentValue {
    public typealias ValueType = Wrapped.ValueType
    public typealias UnwrappedType = Wrapped.UnwrappedType
    public typealias Specification = Wrapped.UnwrappedType.Specification

    public static var defaultResolverSpecification: Wrapped.UnwrappedType.Specification {
        return Wrapped.UnwrappedType.defaultResolverSpecification
    }
}

extension Array: _IntentValue where Element: _IntentValue {
    public typealias ValueType = [Element.ValueType]
    public typealias UnwrappedType = [Element.UnwrappedType]
    public typealias Specification = ResolverSpecificationBuilder<[Element.UnwrappedType]>
        .Specification<[Element.UnwrappedType], ElementResolver<Element.UnwrappedType>>
    public typealias UnderlyingSequence = [Element.ValueType]

    public static var defaultResolverSpecification: Specification {
        return Specification([ElementResolver<Element.UnwrappedType>()])
    }

    /// The label a parameter of a list of values shows above the list, when the app gave none.
    public static var promptLabel: LocalizedStringResource? { return nil }
    /// Whether the list is shown with the section index of the release's own table view.
    public static var usesIndexedCollation: Bool { return false }
    /// A list with nothing in it, which is what a parameter with no default value starts from.
    public static var empty: [Element.ValueType] { return [] }
    /// The values a list carries when the app names none.
    public static var items: [Element.ValueType] { return [] }
}

extension Array: _SequenceIntentValue where Element: _IntentValue {
    public var sequence: [Element.ValueType] { return self }
}

/// Reads the elements of a list parameter out of the string the caller wrote, one element per line and
/// after a comma, which is how a Shortcuts list of values is written.
struct ElementResolver<Element: _IntentValue>: Resolver {
    func resolve(from input: String,
                 context: IntentParameterContext<[Element.UnwrappedType]>) async throws -> [Element.UnwrappedType]? {
        return input.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { CharonIntentValueParser.parse($0, as: Element.UnwrappedType.self) }
    }

    static func == (a: ElementResolver<Element>, b: ElementResolver<Element>) -> Bool { return true }
    func hash(into hasher: inout Hasher) {}
}

/// Writing a value of a type back as the string a caller would write for it, which is what the port's
/// own entity and enum identifiers and the resolvers' tests both go through.
public enum CharonIntentValueParser {
    public static func parse<T>(_ text: String, as type: T.Type) -> T? {
        switch type {
        case is String.Type: return text as? T
        case is Int.Type: return Int(text) as? T
        case is Double.Type: return Double(text) as? T
        case is Float.Type: return Float(text) as? T
        case is Bool.Type:
            return (BoolFromStringResolver().resolve(from: text, context: IntentParameterContext(title: ""))
                    as? T)
        case is URL.Type: return URL(string: text) as? T
        case is UUID.Type: return UUID(uuidString: text) as? T
        case is Date.Type:
            return CharonRun.await { try await DateResolver().resolve(from: text,
                                                                        context: IntentParameterContext(title: "")) } as? T
        default: return nil
        }
    }
}

extension Set: _IntentValue where Element: _IntentValue {
    public typealias ValueType = Set<Element.ValueType>
    public typealias UnwrappedType = Set<Element.UnwrappedType>
    public typealias Specification = ResolverSpecificationBuilder<Set<Element.UnwrappedType>>
        .Specification<Set<Element.UnwrappedType>, SetElementResolver<Element.UnwrappedType>>
    public typealias UnderlyingSequence = Set<Element.ValueType>

    public static var defaultResolverSpecification: Specification {
        return Specification([SetElementResolver<Element.UnwrappedType>()])
    }
}

/// Reads the elements of a set parameter, as `ElementResolver` reads a list's and without the
/// duplicates a set drops.
struct SetElementResolver<Element: _IntentValue>: Resolver {
    func resolve(from input: String,
                 context: IntentParameterContext<Set<Element.UnwrappedType>>) async throws -> Set<Element.UnwrappedType>? {
        guard let list: [Element.UnwrappedType] = await ElementResolver<Element>()
            .resolve(from: input, context: IntentParameterContext(title: "")) else { return nil }
        return Set(list)
    }

    static func == (a: SetElementResolver<Element>, b: SetElementResolver<Element>) -> Bool { return true }
    func hash(into hasher: inout Hasher) {}
}

/// `Never` is a value that is not there, which is what a result that returns nothing and a parameter
/// that was never filled both are. It is the framework's own default for the four of an intent
/// result's type arguments, so it is the value of a result whose app returned nothing.
extension Never: _IntentValue {
    public typealias ValueType = Never
    public typealias UnwrappedType = Never
    public typealias Specification = EmptyResolverSpecification<Never>
    public typealias Intent = Never
    public typealias Dialog = Never
    public typealias OpensAppIntent = Never
    public typealias Snippet = Never
    public typealias SummaryContent = Never
    public typealias Value = Never

    public static var defaultResolverSpecification: Specification { return Specification() }
    public static var title: LocalizedStringResource { return LocalizedStringResource("Never") }
    /// The value of a parameter of this type, added in iOS 17: there is none, and it is asked for as
    /// often as one is.
    public static var value: Never { fatalError("Never has no value") }
}

extension Never: AppIntent {
    public typealias PerformResult = IntentResultContainer<Never, Never, Never, Never>
    public typealias SummaryContent = IntentParameterSummary<Never>

    public init() {}
    public func perform() async throws -> Never { fatalError("Never does nothing") }
    public static var title: LocalizedStringResource { return LocalizedStringResource("Never") }
    public static var parameterSummary: some ParameterSummary { return Summary("") }
    public static var isDiscoverable: Bool { return false }
}
