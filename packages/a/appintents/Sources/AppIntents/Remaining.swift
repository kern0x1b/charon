// The rest of the surface: the macros that declare an intent, an entity or an enum from a schema, the
// property wrappers of a deferred or computed property, the parameters a caller is asked about, and
// the errors a parameter reports.
//
// The macros are declared as the framework declares them. Expanding one needs the framework's own
// macro plugin, which is not on these releases, so a port writes the conformance out - the macro's
// job is to attach `AppEntity` and `AssistantEntity` to the type it is written on, and the type is
// written either way. `facts/AppIntents/Macros.md` says so.

import Foundation

// MARK: - The macros that declare a type from a schema

/// Declares an app entity of a system entity's schema.
@attached(memberAttribute)
@attached(extension, conformances: AppIntents.AppEntity, AppIntents.AssistantSchemaEntity,
          names: named(__assistantSchemaEntity))
public macro AppEntity<T>(schema: T) = #externalMacro(module: "AppIntentsMacros", type: "AppEntityMacros")
    where T: AssistantSchemas.Entity

/// Declares an app intent of a system intent's schema.
@attached(memberAttribute)
@attached(extension, conformances: AppIntents.AppIntent, AppIntents.AssistantSchemaIntent)
public macro AppIntent<T>(schema: T) = #externalMacro(module: "AppIntentsMacros", type: "AppIntentMacros")
    where T: AssistantSchemas.Intent

/// Declares an app enum of a system enum's schema.
@attached(memberAttribute)
@attached(extension, conformances: AppIntents.AppEnum, AppIntents.AssistantSchemaEnum)
public macro AppEnum<T>(schema: T) = #externalMacro(module: "AppIntentsMacros", type: "AppEnumMacros")
    where T: AssistantSchemas.Enum

/// Declares an assistant-only entity of a system entity's schema.
@attached(memberAttribute)
@attached(extension, conformances: AppIntents.AppEntity, AppIntents.AssistantSchemaEntity,
          names: named(__assistantSchemaEntity))
public macro AssistantEntity<T>(schema: T) = #externalMacro(module: "AppIntentsMacros", type: "AssistantEntityMacros")
    where T: AssistantSchemas.Entity

/// Declares an assistant-only intent of a system intent's schema.
@attached(memberAttribute)
@attached(extension, conformances: AppIntents.AppIntent, AppIntents.AssistantSchemaIntent)
public macro AssistantIntent<T>(schema: T) = #externalMacro(module: "AppIntentsMacros", type: "AssistantIntentMacros")
    where T: AssistantSchemas.Intent

/// Declares an assistant-only enum of a system enum's schema.
@attached(memberAttribute)
@attached(extension, conformances: AppIntents.AppEnum, AppIntents.AssistantSchemaEnum)
public macro AssistantEnum<T>(schema: T) = #externalMacro(module: "AppIntentsMacros", type: "AssistantEnumMacros")
    where T: AssistantSchemas.Enum

/// A property the framework computes when it is asked for, rather than one the app fills in.
@attached(peer)
public macro ComputedProperty(title: String) = #externalMacro(module: "AppIntentsMacros", type: "ComputedPropertyMacro")

@attached(peer)
public macro ComputedProperty(title: String, indexingKey: String)
    = #externalMacro(module: "AppIntentsMacros", type: "ComputedPropertyMacro")

@attached(peer)
public macro ComputedProperty(title: String, customIndexingKey: String)
    = #externalMacro(module: "AppIntentsMacros", type: "ComputedPropertyMacro")

@attached(peer)
public macro ComputedProperty(indexingKey: String)
    = #externalMacro(module: "AppIntentsMacros", type: "ComputedPropertyMacro")

@attached(peer)
public macro ComputedProperty(customIndexingKey: String)
    = #externalMacro(module: "AppIntentsMacros", type: "ComputedPropertyMacro")

@attached(peer)
public macro ComputedProperty()
    = #externalMacro(module: "AppIntentsMacros", type: "ComputedPropertyMacro")

/// A property the framework reads from the app only when it is asked for, which is what a value too
/// large to index with the entity needs.
@attached(peer)
public macro DeferredProperty(title: String) = #externalMacro(module: "AppIntentsMacros", type: "DeferredPropertyMacro")

@attached(peer)
public macro DeferredProperty() = #externalMacro(module: "AppIntentsMacros", type: "DeferredPropertyMacro")

/// A value that stands for either of the types it is written with.
@attached(extension, conformances: AppIntents._IntentValueRepresentable, names: arbitrary)
public macro UnionValue() = #externalMacro(module: "AppIntentsMacros", type: "_UnionValueMacro")

// MARK: - The assistant-only types

/// An intent the assistant offers on its own, with no app behind it.
public protocol AssistantIntent: AppIntent {}

/// An entity the assistant offers on its own, with no app behind it.
public protocol AssistantEntity: AppEntity {}

/// An enum the assistant offers on its own, with no app behind it.
public protocol AssistantEnum: AppEnum {}

/// An intent of a system schema, which the assistant offers without the app.
public protocol AssistantSchemaIntent: AssistantIntent {
    /// Whether the assistant offers the intent on its own, with no app behind it.
    static var isAssistantOnly: Bool { get }
}

extension AssistantSchemaIntent {
    public static var isAssistantOnly: Bool { return false }

    /// The title an assistant-only intent is shown with, which is the intent's own.
    public static var title: LocalizedStringResource { return CharonAssistantTitle.of(Self.self) }
}

/// The title an assistant-only intent is shown with, and the one an assistant-only entity and enum are
/// named by: the name of the type, which is what the framework's own default is.
public enum CharonAssistantTitle {
    public static func of(_ type: Any.Type) -> LocalizedStringResource {
        return LocalizedStringResource(String(describing: type))
    }
}

/// An entity of a system schema, which the assistant offers without the app.
public protocol AssistantSchemaEntity: AssistantEntity {
    /// Whether the assistant offers the entity on its own, with no app behind it.
    static var isAssistantOnly: Bool { get }
}

extension AssistantSchemaEntity {
    public static var isAssistantOnly: Bool { return false }

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: String(describing: Self.self))
    }
}

/// An enum of a system schema, which the assistant offers without the app.
public protocol AssistantSchemaEnum: AssistantEnum {
    /// Whether the assistant offers the enum on its own, with no app behind it.
    static var isAssistantOnly: Bool { get }
}

extension AssistantSchemaEnum {
    public static var isAssistantOnly: Bool { return false }

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: String(describing: Self.self))
    }
}

/// A value the system itself hands an intent, which is the system's own entities and enums.
public protocol _SystemIntentValue: DisplayRepresentable, PersistentlyIdentifiable, _IntentValue, Sendable {}

// MARK: - What a parameter asks of the caller

extension IntentParameterContext {
    /// The error the framework reports for a parameter the caller has not filled in.
    public func needsValueError(_ dialog: IntentDialog? = nil) -> AppIntentError {
        return AppIntentError(parameterTitle: title, dialog: dialog, optional: isOptional)
    }

    /// The error the framework reports for values that are not told apart.
    public func needsDisambiguationError(among itemsToDisambiguate: [Any],
                                         dialog: IntentDialog? = nil) -> AppIntentError {
        return AppIntentError(parameterTitle: title, dialog: dialog, optional: isOptional,
                              disambiguation: itemsToDisambiguate.count)
    }

    /// Ask the caller for the value of the parameter this context belongs to.
    public func requestValue(_ dialog: IntentDialog? = nil) async throws -> Any {
        throw needsValueError(dialog)
    }

    /// Ask the caller to choose between the values that are not told apart.
    public func requestDisambiguation(among itemsToDisambiguate: [Any],
                                      dialog: IntentDialog? = nil) async throws -> Any {
        throw needsDisambiguationError(among: itemsToDisambiguate, dialog: dialog)
    }

    /// Ask the caller to confirm one value before the intent acts on it.
    public func requestConfirmation(for itemToConfirm: Any, dialog: IntentDialog? = nil) async throws -> Bool {
        return true
    }
}

// MARK: - The system intents' own members

extension OpenIntent {
    /// An open intent brings the app it opens to the front, which is what `openAppWhenRun` says.
    public static var openAppWhenRun: Bool { return true }

    /// What an open intent does is run the app it names; the app behind the target is the app's own.
    public func perform() async throws -> IntentResultContainer<Never, Never, Never, Never> {
        return IntentResultContainer()
    }
}

extension WidgetConfigurationIntent {
    /// Configuring a widget sets the value the widget draws, which is the port's own store.
    public func perform() async throws -> IntentResultContainer<Never, Never, Never, Never> {
        return IntentResultContainer()
    }
}

extension URLRepresentableIntent {
    /// Running a URL-representable intent is the app's own run; the URL is how the caller named it,
    /// and the app behind the name is the app's own to run.
    public func perform() async throws -> IntentResultContainer<Never, Never, Never, Never> {
        return IntentResultContainer()
    }
}

extension IntentChoiceOption {
    /// The option that cancels, which is what a caller that does not choose gets.
    public static var cancel: IntentChoiceOption {
        return IntentChoiceOption(title: LocalizedStringResource("Cancel"), style: .cancel)
    }
}

extension IntentDonationManager {
    /// Donate a run, keeping the result for a caller that reads the store back.
    @discardableResult
    public func donate<Intent: AppIntent>(intent: Intent) -> IntentDonationIdentifier {
        return donate(intent: intent, result: CharonIntentResultText.empty)
    }
}

extension CharonIntentResultText {
    /// A result that is nothing, which is what a donation of a run that returned nothing keeps.
    static let empty = IntentResultContainer<Never, Never, Never, Never>()
}

extension ForegroundContinuableIntent {
}

extension CharonForeground {
    /// The continuation the framework hands an intent that asks to stay in the foreground: a value the
    /// run hands back to say whether it may carry on.
    public struct Continuation {
        /// Whether the run may carry on in the foreground.
        public var mayContinue: Bool

        public init(mayContinue: Bool = true) {
            self.mayContinue = mayContinue
        }
    }
}

extension CharonRun {
    /// Run a call from a caller that cannot wait for it and keep what it returned.
    public static func awaitBool(_ body: @escaping () async throws -> Bool) -> Bool {
        let finished = DispatchSemaphore(value: 0)
        var answer = false
        Task {
            answer = (try? await body()) ?? false
            finished.signal()
        }
        finished.wait()
        return answer
    }
}

// MARK: - The string forms of the release's own types

extension String {
    /// The entity identifier of a string, which is the string itself: a string is its own key.
    public static func entityIdentifier(for value: String) -> EntityIdentifier {
        return EntityIdentifier(for: value, identifier: value)
    }

    /// The string an entity identifier of this type is written as, which is the string itself.
    public static var entityIdentifierString: String { return "" }
}

extension IntentWidgetFamily {
    public func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }

    public var hashValue: Int { return rawValue.hashValue }
}

extension IntentPaymentMethod.PaymentType {
    public func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }

    public var hashValue: Int { return rawValue.hashValue }
}

extension IntentPerson.Handle.Label {
    public func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }

    public var hashValue: Int { return rawValue.hashValue }
}

extension IntentPerson.Handle.Value {
    public func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }

    public var hashValue: Int { return rawValue.hashValue }
}

extension IntentPerson.Identifier {
    public func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }

    public var hashValue: Int { return rawValue.hashValue }
}

extension SetFocusFilterIntentError {
    public func hash(into hasher: inout Hasher) { hasher.combine(CharonFocusError.ordinal(self)) }

    public var hashValue: Int { return CharonFocusError.ordinal(self) }
}

/// Which of the framework's own focus-filter errors one is, which is what the error hashes as.
public enum CharonFocusError {
    public static func ordinal(_ error: SetFocusFilterIntentError) -> Int {
        switch error {
        case .notFound: return 0
        case .missingParameterValue: return 1
        }
    }
}

extension StringSearchScope {
    /// A search scope read from the string a caller wrote, which is the scope's own raw value.
    public init?(rawValue: String) {
        self.init(rawValue: rawValue)
    }
}

extension VideoCategory {
    /// A video category read from the string a caller wrote, which is the category's own raw value.
    public init?(rawValue: String) {
        self.init(rawValue: rawValue)
    }
}

/// Whether a `Bool` parameter is shown as the words "Yes" and "No" or as the words the app wrote.
extension Bool {
    public struct IntentDisplayName {
        /// The name shown for `true`.
        public static var `true`: LocalizedStringResource { return LocalizedStringResource("Yes") }
        /// The name shown for `false`.
        public static var `false`: LocalizedStringResource { return LocalizedStringResource("No") }

        /// The name a value of this type is shown with.
        public func name(of value: Bool) -> LocalizedStringResource {
            return value ? IntentDisplayName.true : IntentDisplayName.false
        }
    }

    /// The display names a `Bool` parameter is shown with, the framework's own list.
    static var intentDisplayName: IntentDisplayName { return IntentDisplayName() }
}
