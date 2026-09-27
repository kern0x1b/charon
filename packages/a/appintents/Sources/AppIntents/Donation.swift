// The donation of a run, the prediction of a run, and the relevant-intent list a widget is built
// from: the three things an app tells the framework about a run it has already done.
//
// A donation is a record of a run: what the intent was, which of its parameters were filled, and what
// it returned. The system side - Siri's and Spotlight's index of what the app has done - is a service
// these releases do not run, so the port keeps the donations in its own store under Application
// Support, answers queries against it, and is what a later in-process call reads back. See
// `facts/AppIntents/Services.md`.

import Foundation

/// The identifier of a donation: the run's own identifier and the time it happened.
public struct IntentDonationIdentifier: Hashable, Codable, Sendable {
    /// The framework's own identifier of the donation.
    public let identifier: String
    /// The intent the donation is of.
    public let intentType: String
    /// The identifiers of the entities the donation names.
    public let entityIdentifiers: [String]

    public init(identifier: String = UUID().uuidString, intentType: String = "",
                entityIdentifiers: [String] = []) {
        self.identifier = identifier
        self.intentType = intentType
        self.entityIdentifiers = entityIdentifiers
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.identifier = try container.decode(String.self, forKey: .identifier)
        self.intentType = try container.decode(String.self, forKey: .intentType)
        self.entityIdentifiers = try container.decodeIfPresent([String].self, forKey: .entityIdentifiers) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(intentType, forKey: .intentType)
        try container.encode(entityIdentifiers, forKey: .entityIdentifiers)
    }

    private enum CodingKeys: String, CodingKey {
        case identifier
        case intentType
        case entityIdentifiers
    }

    public static func == (a: IntentDonationIdentifier, b: IntentDonationIdentifier) -> Bool {
        return a.identifier == b.identifier && a.intentType == b.intentType
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
        hasher.combine(intentType)
    }
}

/// What a donation is matched against when a donation is deleted.
public struct IntentDonationMatchingPredicate {
    enum Kind {
        case donationIdentifier(IntentDonationIdentifier)
        case entityIdentifier(EntityIdentifier)
        case intentType(String, EntityIdentifier?)
    }

    let kind: Kind

    /// A donation of one run.
    public static func donationIdentifier(_ identifier: IntentDonationIdentifier) -> IntentDonationMatchingPredicate {
        return IntentDonationMatchingPredicate(kind: .donationIdentifier(identifier))
    }

    /// A donation that names an entity.
    public static func entityIdentifier(_ identifier: EntityIdentifier) -> IntentDonationMatchingPredicate {
        return IntentDonationMatchingPredicate(kind: .entityIdentifier(identifier))
    }

    /// A donation of an intent that names an entity.
    public static func intentType(_ intentType: String,
                                  entityIdentifier: EntityIdentifier? = nil) -> IntentDonationMatchingPredicate {
        return IntentDonationMatchingPredicate(kind: .intentType(intentType, entityIdentifier))
    }
}

/// One donation, as the store keeps it.
public struct IntentDonation: Codable, Sendable {
    public let identifier: IntentDonationIdentifier
    public let timestamp: Date
    /// The value the run returned, written the way the value writes itself.
    public let value: String?

    public init(identifier: IntentDonationIdentifier, timestamp: Date, value: String?) {
        self.identifier = identifier
        self.timestamp = timestamp
        self.value = value
    }
}

/// The manager an app hands its donations to.
public final class IntentDonationManager {
    /// The one the framework's own extension methods use.
    public static let shared = IntentDonationManager()

    private let store: IntentDonationStore
    private let lock = NSLock()

    public init() {
        store = IntentDonationStore()
    }

    /// Donate a run with what it returned.
    @discardableResult
    public func donate<Intent: AppIntent>(intent: Intent, result: some IntentResult) -> IntentDonationIdentifier {
        let identifier = IntentDonationIdentifier(intentType: Intent.persistentIdentifier)
        let value = CharonIntentResultText.write(result)
        lock.lock()
        store.add(IntentDonation(identifier: identifier, timestamp: Date(), value: value))
        lock.unlock()
        return identifier
    }

    /// The donations the store holds, newest first, which is what a caller reads back in process.
    public func donations() -> [IntentDonation] {
        lock.lock()
        defer { lock.unlock() }
        return store.all()
    }

    /// Delete the donations a predicate matches.
    public func deleteDonations(matching predicate: IntentDonationMatchingPredicate) {
        lock.lock()
        defer { lock.unlock() }
        switch predicate.kind {
        case .donationIdentifier(let wanted):
            store.remove(where: { $0.identifier == wanted })
        case .entityIdentifier(let wanted):
            store.remove(where: { $0.identifier.entityIdentifiers.contains(wanted.identifier) })
        case .intentType(let intentType, let entity):
            store.remove(where: { donation in
                guard donation.identifier.intentType == intentType else { return false }
                guard let entity = entity else { return true }
                return donation.identifier.entityIdentifiers.contains(entity.identifier)
            })
        }
    }
}

/// The port's own store of donations, under Application Support: a plist the process writes and reads
/// back. The system donation index the framework writes to is a service these releases do not run.
final class IntentDonationStore {
    private let path: String

    init() {
        let support = (NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)
            .first ?? NSTemporaryDirectory())
        let folder = (support as NSString).appendingPathComponent("charon-appintents")
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        path = (folder as NSString).appendingPathComponent("donations.plist")
    }

    func all() -> [IntentDonation] {
        guard let data = FileManager.default.contents(atPath: path) else { return [] }
        guard let list = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { entry in
            guard let identifier = entry["identifier"] as? String,
                  let intentType = entry["intentType"] as? String else { return nil }
            return IntentDonation(identifier: IntentDonationIdentifier(identifier: identifier, intentType: intentType),
                                  timestamp: Date(timeIntervalSince1970: entry["timestamp"] as? Double ?? 0),
                                  value: entry["value"] as? String)
        }.sorted { $0.timestamp > $1.timestamp }
    }

    func add(_ donation: IntentDonation) {
        var list = all()
        list.insert(donation, at: 0)
        write(list)
    }

    func remove(where predicate: (IntentDonation) -> Bool) {
        write(all().filter { !predicate($0) })
    }

    private func write(_ list: [IntentDonation]) {
        let entries: [[String: Any]] = list.map { donation in
            return ["identifier": donation.identifier.identifier, "intentType": donation.identifier.intentType,
                    "timestamp": donation.timestamp.timeIntervalSince1970, "value": donation.value ?? ""]
        }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0) else {
            return
        }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

/// Writing what a result returned as the string a caller reads it back as, which is what a donation
/// keeps of a run.
enum CharonIntentResultText {
    static func write(_ result: some IntentResult) -> String? {
        if let dialog = result as? IntentResultContainer<Never, Never, Never, IntentDialog> {
            return dialog.dialog?.full.localizedString()
        }
        return nil
    }
}

// MARK: - Predictions

/// A prediction: what the framework may do next, and what an intent's parameters are predicted to be.
public struct IntentPrediction<Intent: AppIntent, T> {
    public let displayRepresentation: DisplayRepresentation
    public let parameters: Intent?

    public init(displayRepresentation: DisplayRepresentation) {
        self.displayRepresentation = displayRepresentation
        self.parameters = nil
    }

    public init(parameters: Intent?, displayRepresentation: DisplayRepresentation) {
        self.parameters = parameters
        self.displayRepresentation = displayRepresentation
    }
}

/// The predictions of a tuple of intents, which is what an app declares with `IntentPrediction`.
public struct TupleIntentPrediction<Intent: AppIntent, T>: IntentPredictionConfiguration {
    public let intent: Intent.Type
    public let displayRepresentation: DisplayRepresentation
    public let parameters: Intent?

    public init(displayRepresentation: DisplayRepresentation) {
        self.intent = Intent.self
        self.displayRepresentation = displayRepresentation
        self.parameters = nil
    }

    public init(parameters: Intent?, displayRepresentation: DisplayRepresentation) {
        self.intent = Intent.self
        self.displayRepresentation = displayRepresentation
        self.parameters = parameters
    }
}

/// What an intent is predicted to do, which is a display representation and, for a `PredictableIntent`,
/// the intent itself.
public protocol IntentPredictionConfiguration {
    var displayRepresentation: DisplayRepresentation { get }
}

/// An intent the framework may run on the app's behalf, which the app predicts.
public protocol PredictableIntent: AppIntent {}

/// The builder of a list of predictions.
@resultBuilder
public enum IntentPredictionsBuilder {
    public static func buildBlock(_ a: some IntentPredictionConfiguration) -> [any IntentPredictionConfiguration] {
        return [a]
    }

    public static func buildBlock(_ a: some IntentPredictionConfiguration,
                                  _ b: some IntentPredictionConfiguration) -> [any IntentPredictionConfiguration] {
        return [a, b]
    }

    public static func buildBlock(_ a: some IntentPredictionConfiguration, _ b: some IntentPredictionConfiguration,
                                  _ c: some IntentPredictionConfiguration) -> [any IntentPredictionConfiguration] {
        return [a, b, c]
    }

    public static func buildBlock(_ a: some IntentPredictionConfiguration, _ b: some IntentPredictionConfiguration,
                                  _ c: some IntentPredictionConfiguration,
                                  _ d: some IntentPredictionConfiguration) -> [any IntentPredictionConfiguration] {
        return [a, b, c, d]
    }

    public static func buildBlock(_ a: some IntentPredictionConfiguration, _ b: some IntentPredictionConfiguration,
                                  _ c: some IntentPredictionConfiguration, _ d: some IntentPredictionConfiguration,
                                  _ e: some IntentPredictionConfiguration) -> [any IntentPredictionConfiguration] {
        return [a, b, c, d, e]
    }

    public static func buildBlock(_ a: some IntentPredictionConfiguration, _ b: some IntentPredictionConfiguration,
                                  _ c: some IntentPredictionConfiguration, _ d: some IntentPredictionConfiguration,
                                  _ e: some IntentPredictionConfiguration,
                                  _ f: some IntentPredictionConfiguration) -> [any IntentPredictionConfiguration] {
        return [a, b, c, d, e, f]
    }

    public static func buildBlock(_ a: some IntentPredictionConfiguration, _ b: some IntentPredictionConfiguration,
                                  _ c: some IntentPredictionConfiguration, _ d: some IntentPredictionConfiguration,
                                  _ e: some IntentPredictionConfiguration, _ f: some IntentPredictionConfiguration,
                                  _ g: some IntentPredictionConfiguration) -> [any IntentPredictionConfiguration] {
        return [a, b, c, d, e, f, g]
    }

    public static func buildBlock(_ a: some IntentPredictionConfiguration, _ b: some IntentPredictionCompletion,
                                  _ c: some IntentPredictionConfiguration,
                                  _ d: some IntentPredictionConfiguration,
                                  _ e: some IntentPredictionCompletion,
                                  _ f: some IntentPredictionConfiguration,
                                  _ g: some IntentPredictionCompletion) -> [any IntentPredictionConfiguration] {
        return [a, b, c, d, e, f, g]
    }

    public static func buildBlock(_ a: some IntentPredictionConfiguration, _ b: some IntentPredictionConfiguration,
                                  _ c: some IntentPredictionCompletion,
                                  _ d: some IntentPredictionCompletion,
                                  _ e: some IntentPredictionCompletion, _ f: some IntentPredictionCompletion,
                                  _ g: some IntentPredictionCompletion) -> [any IntentPredictionConfiguration] {
        return [a, b, c, d, e, f, g]
    }

    public static func buildBlock(_ a: some IntentPredictionConfiguration, _ b: some IntentPredictionCompletion,
                                  _ c: some IntentPredictionCompletion, _ d: some IntentPredictionCompletion,
                                  _ e: some IntentPredictionCompletion, _ f: some IntentPredictionCompletion,
                                  _ g: some IntentPredictionCompletion,
                                  _ h: some IntentPredictionCompletion) -> [any IntentPredictionConfiguration] {
        return [a, b, c, d, e, f, g, h]
    }

    public static func buildBlock(_ a: some IntentPredictionConfiguration, _ b: some IntentPredictionCompletion,
                                  _ c: some IntentPredictionCompletion, _ d: some IntentPredictionCompletion,
                                  _ e: some IntentPredictionCompletion, _ f: some IntentPredictionCompletion,
                                  _ g: some IntentPredictionCompletion, _ h: some IntentPredictionCompletion,
                                  _ i: some IntentPredictionCompletion) -> [any IntentPredictionConfiguration] {
        return [a, b, c, d, e, f, g, h, i]
    }

    public static func buildBlock(_ a: some IntentPredictionConfiguration, _ b: some IntentPredictionCompletion,
                                  _ c: some IntentPredictionCompletion, _ d: some IntentPredictionCompletion,
                                  _ e: some IntentPredictionCompletion, _ f: some IntentPredictionCompletion,
                                  _ g: some IntentPredictionCompletion, _ h: some IntentPredictionCompletion,
                                  _ i: some IntentPredictionCompletion,
                                  _ j: some IntentPredictionCompletion) -> [any IntentPredictionConfiguration] {
        return [a, b, c, d, e, f, g, h, i, j]
    }

    public static func buildBlock(_ a: some IntentPredictionConfiguration, _ b: some IntentPredictionCompletion,
                                  _ c: some IntentPredictionCompletion, _ d: some IntentPredictionCompletion,
                                  _ e: some IntentPredictionCompletion, _ f: some IntentPredictionCompletion,
                                  _ g: some IntentPredictionCompletion, _ h: some IntentPredictionCompletion,
                                  _ i: some IntentPredictionCompletion, _ j: some IntentPredictionCompletion,
                                  _ k: some IntentPredictionCompletion) -> [any IntentPredictionConfiguration] {
        return [a, b, c, d, e, f, g, h, i, j, k]
    }

    public static func buildBlock(_ a: some IntentPredictionConfiguration, _ b: some IntentPredictionCompletion,
                                  _ c: some IntentPredictionCompletion, _ d: some IntentPredictionCompletion,
                                  _ e: some IntentPredictionCompletion, _ f: some IntentPredictionCompletion,
                                  _ g: some IntentPredictionCompletion, _ h: some IntentPredictionCompletion,
                                  _ i: some IntentPredictionCompletion, _ j: some IntentPredictionCompletion,
                                  _ k: some IntentPredictionCompletion,
                                  _ l: some IntentPredictionCompletion) -> [any IntentPredictionConfiguration] {
        return [a, b, c, d, e, f, g, h, i, j, k, l]
    }

    public static func buildBlock(_ a: some IntentPredictionConfiguration, _ b: some IntentPredictionCompletion,
                                  _ c: some IntentPredictionCompletion, _ d: some IntentPredictionCompletion,
                                  _ e: some IntentPredictionCompletion, _ f: some IntentPredictionCompletion,
                                  _ g: some IntentPredictionCompletion, _ h: some IntentPredictionCompletion,
                                  _ i: some IntentPredictionCompletion, _ j: some IntentPredictionCompletion,
                                  _ k: some IntentPredictionCompletion, _ l: some IntentPredictionCompletion,
                                  _ m: some IntentPredictionCompletion) -> [any IntentPredictionConfiguration] {
        return [a, b, c, d, e, f, g, h, i, j, k, l, m]
    }

    public static func buildBlock(_ a: some IntentPredictionConfiguration, _ b: some IntentPredictionCompletion,
                                  _ c: some IntentPredictionCompletion, _ d: some IntentPredictionCompletion,
                                  _ e: some IntentPredictionCompletion, _ f: some IntentPredictionCompletion,
                                  _ g: some IntentPredictionCompletion, _ h: some IntentPredictionCompletion,
                                  _ i: some IntentPredictionCompletion, _ j: some IntentPredictionCompletion,
                                  _ k: some IntentPredictionCompletion, _ l: some IntentPredictionCompletion,
                                  _ m: some IntentPredictionCompletion,
                                  _ n: some IntentPredictionCompletion) -> [any IntentPredictionConfiguration] {
        return [a, b, c, d, e, f, g, h, i, j, k, l, m, n]
    }

    public static func buildBlock(_ a: some IntentPredictionConfiguration, _ b: some IntentPredictionCompletion,
                                  _ c: some IntentPredictionCompletion, _ d: some IntentPredictionCompletion,
                                  _ e: some IntentPredictionCompletion, _ f: some IntentPredictionCompletion,
                                  _ g: some IntentPredictionCompletion, _ h: some IntentPredictionCompletion,
                                  _ i: some IntentPredictionCompletion, _ j: some IntentPredictionCompletion,
                                  _ k: some IntentPredictionCompletion, _ l: some IntentPredictionCompletion,
                                  _ m: some IntentPredictionCompletion, _ n: some IntentPredictionCompletion,
                                  _ o: some IntentPredictionCompletion) -> [any IntentPredictionConfiguration] {
        return [a, b, c, d, e, f, g, h, i, j, k, l, m, n, o]
    }

    public static func buildExpression<S>(_ expression: S) -> S where S: IntentPredictionConfiguration { return expression }
}

/// A hole in a prediction, which the caller fills when the prediction is acted on.
public typealias IntentPredictionCompletion = Never

// MARK: - Relevant intents

/// One of the intents a widget shows, and how relevant it is.
public struct RelevantIntent {
    /// The kind of widget an intent is relevant to.
    public enum WidgetKind: Hashable {
        case accessoryCircular
        case accessoryCorner
        case accessoryInline
        case accessoryRectangular
        case systemLarge
        case systemMedium
        case systemSmall
    }

    public let intent: IntentPredictionConfiguration
    public let relevance: Double
    public let widgetKind: WidgetKind

    public init(_ intent: IntentPredictionConfiguration, widgetKind: WidgetKind, relevance: Double) {
        self.intent = intent
        self.widgetKind = widgetKind
        self.relevance = relevance
    }

    public var debugDescription: String { return "relevant: \(relevance)" }
}

/// The manager a widget's relevant intents are handed to.
public final class RelevantIntentManager {
    public static let shared = RelevantIntentManager()

    private let store = RelevantIntentStore()
    private let lock = NSLock()

    public init() {}

    public func updateRelevantIntents(_ intents: [RelevantIntent]) {
        lock.lock()
        defer { lock.unlock() }
        store.write(intents)
    }

    /// The intents the store holds, which is what a widget reads back in process.
    public func relevantIntents() -> [RelevantIntent] {
        lock.lock()
        defer { lock.unlock() }
        return store.read()
    }
}

/// The port's own record of a widget's relevant intents, under Application Support: a widget timeline
/// provider is a system service these releases do not run, so the list is kept in process.
final class RelevantIntentStore {
    private let path: String

    init() {
        let support = (NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)
            .first ?? NSTemporaryDirectory())
        let folder = (support as NSString).appendingPathComponent("charon-appintents")
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        path = (folder as NSString).appendingPathComponent("relevant-intents.plist")
    }

    func write(_ intents: [RelevantIntent]) {
        let entries: [[String: Any]] = intents.map { intent in
            return ["relevance": intent.relevance, "widgetKind": String(describing: intent.widgetKind),
                    "displayName": intent.intent.displayRepresentation.title]
        }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0) else {
            return
        }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    func read() -> [RelevantIntent] {
        guard let data = FileManager.default.contents(atPath: path) else { return [] }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]]) ?? []
    }
}
