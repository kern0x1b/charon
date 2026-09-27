// How a value, an entity, an enum or an intent is shown: a title, a subtitle, a picture and the
// words that stand for the same thing in another language.
//
// `DisplayRepresentation` is a value type with no dependency on the system: it holds what the app
// declared, and the framework is what puts it on screen. `TypeDisplayRepresentation` is the same for
// the type rather than the value, which is what an entity query is given for a whole class.

import Foundation

/// A value that names itself, once for the type and once for each of its cases.
public protocol DisplayRepresentable: InstanceDisplayRepresentable, TypeDisplayRepresentable {}

/// A value that names its type.
public protocol TypeDisplayRepresentable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { get }
}

/// A value that names itself for one instance.
public protocol InstanceDisplayRepresentable: CustomLocalizedStringResourceConvertible {
    var displayRepresentation: DisplayRepresentation { get }

    /// A value that names itself is its own string, which is what the framework's own default is: the
    /// title of the display representation.
    var localizedStringResource: LocalizedStringResource { get }
}

extension InstanceDisplayRepresentable {
    public var localizedStringResource: LocalizedStringResource {
        return LocalizedStringResource(displayRepresentation.title)
    }
}

/// A type whose every case names itself.
public protocol CaseDisplayRepresentable: CustomLocalizedStringResourceConvertible, CaseIterable, Hashable {
    static var caseDisplayRepresentations: [DisplayRepresentation] { get }
    var localizedStringResource: LocalizedStringResource { get }
}

/// A type that names itself the same way whatever it holds, as an enum does.
public protocol StaticDisplayRepresentable: CaseDisplayRepresentable, TypeDisplayRepresentable {}

/// How the name of a type is shown: the name, and how a number of that type is written.
public struct TypeDisplayRepresentation: ExpressibleByStringLiteral {
    public typealias NumericFormat = String

    public let name: String
    public let numericFormat: NumericFormat?
    /// The words that stand for the same type in another language, added in iOS 17.
    public let synonyms: [String]

    public init(name: String, numericFormat: NumericFormat? = nil) {
        self.name = name
        self.numericFormat = numericFormat
        self.synonyms = []
    }

    public init(name: String, numericFormat: NumericFormat? = nil, synonyms: [String]) {
        self.name = name
        self.numericFormat = numericFormat
        self.synonyms = synonyms
    }

    public init(_ name: String) {
        self.init(name: name)
    }

    public init(stringLiteral value: String) {
        self.init(name: value)
    }
}

/// How a value is shown: a title, a subtitle and a picture.
public struct DisplayRepresentation: ExpressibleByStringLiteral, Equatable {
    public let title: String
    public let subtitle: String?
    public let image: Image?
    /// The words that stand for the same value in another language, added in iOS 17.
    public let synonyms: [String]

    public init(title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil, image: Image? = nil) {
        self.title = title.localizedString()
        self.subtitle = subtitle?.localizedString()
        self.image = image
        self.synonyms = []
    }

    public init(title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil, image: Image? = nil,
                synonyms: [String]) {
        self.title = title.localizedString()
        self.subtitle = subtitle?.localizedString()
        self.image = image
        self.synonyms = synonyms
    }

    public init(title: String, subtitle: String? = nil, image: Image? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.image = image
        self.synonyms = []
    }

    public init(stringLiteral value: String) {
        self.init(title: value)
    }

    /// A picture of a value: its data, a named system image or a file, and how it is masked.
    public struct Image: Equatable {
        /// How an image is masked, added in iOS 17: a circle, or the picture as it is.
        public enum DisplayStyle: Hashable, Sendable {
            case `default`
            case circular
        }

        /// The bytes of the picture, when the app gave them or named a system image.
        public let data: Data?
        /// Whether the picture is a template, which is the release's own image rendering.
        public let isTemplate: Bool
        /// How the picture is masked.
        public let displayStyle: DisplayStyle
        /// The file the picture is in, when the picture is a file.
        public let url: URL?
        /// The width the picture is asked for, when the app named one.
        public let width: Int?
        /// The height the picture is asked for, when the app named one.
        public let height: Int?

        public init(data: Data, isTemplate: Bool = true) {
            self.data = data
            self.isTemplate = isTemplate
            self.displayStyle = .default
            self.url = nil
            self.width = nil
            self.height = nil
        }

        public init(data: Data, isTemplate: Bool = true, displayStyle: DisplayStyle) {
            self.data = data
            self.isTemplate = isTemplate
            self.displayStyle = displayStyle
            self.url = nil
            self.width = nil
            self.height = nil
        }

        public init(named name: String, isTemplate: Bool = true) {
            self.init(data: Data(name.utf8), isTemplate: isTemplate)
        }

        public init(named name: String, isTemplate: Bool = true, displayStyle: DisplayStyle) {
            self.init(data: Data(name.utf8), isTemplate: isTemplate, displayStyle: displayStyle)
        }

        public init(systemName: String, isTemplate: Bool = true) {
            self.init(data: Data(systemName.utf8), isTemplate: isTemplate)
        }

        public init(url: URL, isTemplate: Bool = true) {
            self.data = nil
            self.isTemplate = isTemplate
            self.displayStyle = .default
            self.url = url
            self.width = nil
            self.height = nil
        }

        public init(url: URL, isTemplate: Bool = true, displayStyle: DisplayStyle) {
            self.data = nil
            self.isTemplate = isTemplate
            self.displayStyle = displayStyle
            self.url = url
            self.width = nil
            self.height = nil
        }

        public init(url: URL, width: Int, height: Int, isTemplate: Bool = true) {
            self.data = nil
            self.isTemplate = isTemplate
            self.displayStyle = .default
            self.url = url
            self.width = width
            self.height = height
        }

        public init(url: URL, width: Int, height: Int, isTemplate: Bool = true, displayStyle: DisplayStyle) {
            self.data = nil
            self.isTemplate = isTemplate
            self.displayStyle = displayStyle
            self.url = url
            self.width = width
            self.height = height
        }

        /// The name of a system image, when the picture is one, which is what the release's own image
        /// lookup takes.
        public var systemName: String? { return data.flatMap { String(data: $0, encoding: .utf8) } }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.data = try container.decodeIfPresent(Data.self, forKey: .data)
            self.isTemplate = try container.decodeIfPresent(Bool.self, forKey: .isTemplate) ?? true
            self.displayStyle = .default
            self.url = try container.decodeIfPresent(URL.self, forKey: .url)
            self.width = try container.decodeIfPresent(Int.self, forKey: .width)
            self.height = try container.decodeIfPresent(Int.self, forKey: .height)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(data, forKey: .data)
            try container.encode(isTemplate, forKey: .isTemplate)
            try container.encodeIfPresent(url, forKey: .url)
            try container.encodeIfPresent(width, forKey: .width)
            try container.encodeIfPresent(height, forKey: .height)
        }

        private enum CodingKeys: String, CodingKey {
            case data
            case isTemplate
            case url
            case width
            case height
        }

        public static func == (a: Image, b: Image) -> Bool {
            return a.data == b.data && a.isTemplate == b.isTemplate && a.displayStyle == b.displayStyle
                && a.url == b.url && a.width == b.width && a.height == b.height
        }
    }

    public static func == (lhs: DisplayRepresentation, rhs: DisplayRepresentation) -> Bool {
        return lhs.title == rhs.title && lhs.subtitle == rhs.subtitle && lhs.image == rhs.image
    }
}

extension TypeDisplayRepresentable {
    /// A type names itself by its own name unless it says otherwise, which is what the framework's own
    /// default is.
    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: CharonNames.simple(Self.self))
    }
}

extension CaseDisplayRepresentable {
    /// A case names itself by the name of the case, which is what the framework's own default is.
    public var localizedStringResource: LocalizedStringResource {
        return LocalizedStringResource(String(describing: self))
    }

    /// What every case of a type shows, which is the case's own name unless it says otherwise.
    public static var caseDisplayRepresentations: [DisplayRepresentation] {
        return allCases.map { DisplayRepresentation(title: LocalizedStringResource(String(describing: $0))) }
    }
}
