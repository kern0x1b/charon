// Columns.swift — the columns a `DataFrame` is made of.
//
// **A column here does not conform to a collection, and the reason is the toolchain.** A
// user-defined `RandomAccessCollection` conformance does not compile with the port's Swift 6.4 at
// all: the smallest possible one — a non-generic struct over `[Double]` with `startIndex`,
// `endIndex`, `index(after:)`, `index(before:)` and `subscript(position:)` — is rejected with
//
//     type 'Fixed' does not conform to protocol 'RandomAccessCollection'
//     unavailable subscript 'subscript(_:)' was used to satisfy a requirement of protocol
//
// on the *port's* compiler at `-target armv7-apple-ios6.0` as well as on the host's, and
// `Array` — which is in the same standard library — conforms without trouble. So this is the
// compiler and not the declarations, and it is measured on both targets and recorded in
// `facts/TabularData/Columns.md` and in the registry.
//
// What that costs, precisely: the conformance itself. Nothing else. A column still has `count`,
// `isEmpty`, `startIndex`, `endIndex`, `index(after:)`, `index(before:)`, `subscript(position:)` and
// `subscript(bounds:)`, spelled as the collection spells them, and those are the names the surface's
// rows are written against. What a caller loses is writing `for x in column`, which is a convenience
// over `for i in 0..<column.count` — and the alternative, declaring a conformance that does not
// compile, is not available.
//
// `ColumnProtocol` therefore declares its `Element` and its `name` and nothing else. It keeps the
// primary associated type the surface names, `ColumnProtocol<Element>`, which is what a caller writes
// to name a column and its type.

import Foundation

/// A column's name, and the type of its values: how a caller asks a frame for a column and gets a
/// typed one back.
public struct ColumnID<T>: Sendable {
    public var name: String

    public init(_ name: String, _ type: T.Type) {
        self.name = name
    }
}

extension ColumnID: CustomStringConvertible {
    public var description: String { name }
}

extension ColumnID: Equatable {
    public static func == (lhs: ColumnID, rhs: ColumnID) -> Bool { lhs.name == rhs.name }
}

extension ColumnID: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

/// A column of a frame: a name and a vector of values of one type.
public protocol ColumnProtocol<Element> {
    associatedtype Element
    /// How many values the column holds. Not `count` from a collection, because the column is not
    /// one — see the file's header — and the name the surface records is the one here.
    var count: Int { get }
    var isEmpty: Bool { get }
    var name: String { get set }
}

/// A column of a frame, holding values of one type.
public struct Column<Element>: ColumnProtocol {
    public var name: String
    public private(set) var values: [Element]

    public init(name: String = "") {
        self.name = name
        self.values = []
    }

    public init(name: String = "", _ values: [Element]) {
        self.name = name
        self.values = values
    }

    public init<S: Sequence>(_ source: S, name: String = "") where S.Element == Element {
        self.name = name
        self.values = Array(source)
    }

    public init(_ column: Column<Element>, name: String? = nil) {
        self.name = name ?? column.name
        self.values = column.values
    }

    public init(repeating value: Element, count: Int, name: String = "") {
        self.name = name
        self.values = [Element](repeating: value, count: count)
    }

    public var count: Int { values.count }
    public var isEmpty: Bool { values.isEmpty }
    public var startIndex: Int { 0 }
    public var endIndex: Int { values.count }
    public func index(after i: Int) -> Int { i + 1 }
    public func index(before i: Int) -> Int { i - 1 }

    public subscript(position index: Int) -> Element {
        get { values[index] }
        set { values[index] = newValue }
    }

    public subscript(bounds range: Range<Int>) -> ColumnSlice<Element> {
        ColumnSlice(base: self, range: range)
    }

    public var slice: ColumnSlice<Element> { ColumnSlice(base: self, range: 0..<count) }

    public mutating func append(_ value: Element) { values.append(value) }
    public mutating func append(contentsOf other: [Element]) { values.append(contentsOf: other) }
    public mutating func reserveCapacity(_ capacity: Int) { values.reserveCapacity(capacity) }

    public func map<T>(_ transform: (Element) throws -> T) rethrows -> Column<T> {
        Column<T>(name: name, try values.map(transform))
    }

    public func compactMap<T>(_ transform: (Element) throws -> T?) rethrows -> Column<T> {
        Column<T>(name: name, try values.compactMap(transform))
    }

    public func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> Column<Element> {
        Column<Element>(name: name, try values.filter(isIncluded))
    }
}

extension Column: Equatable where Element: Equatable {}
extension Column: Sendable where Element: Sendable {}

/// A contiguous run of a column's rows: the column and a range into it.
public struct ColumnSlice<Element> {
    /// The column the slice is a run of. A copy: a slice that wrote through it would write into the
    /// copy and the frame would keep the old value.
    public let base: Column<Element>
    public let range: Range<Int>
    public var name: String { base.name }

    public init(base: Column<Element>, range: Range<Int>) {
        self.base = base
        self.range = range
    }

    public init(name: String = "", _ values: [Element]) {
        self.base = Column<Element>(name: name, values)
        self.range = 0..<values.count
    }

    public var count: Int { range.count }
    public var isEmpty: Bool { range.isEmpty }
    public var startIndex: Int { 0 }
    public var endIndex: Int { range.count }
    public func index(after i: Int) -> Int { i + 1 }
    public func index(before i: Int) -> Int { i - 1 }

    /// Read-only. A slice holds its base by value, so a write through it would land in that copy
    /// and the frame would keep the old value: a subscript a caller can write and that does nothing
    /// is worse than one they cannot write.
    public subscript(position index: Int) -> Element {
        base[position: range.lowerBound + index]
    }

    public subscript(bounds slice: Range<Int>) -> ColumnSlice<Element> {
        ColumnSlice(base: base,
                    range: range.lowerBound + slice.lowerBound ..< range.lowerBound + slice.upperBound)
    }

    /// The slice as a column of its own, which is a copy: a slice knows its base and its range, and
    /// a column knows neither.
    public var column: Column<Element> { Column<Element>(name: name, values) }

    /// The values, which is what a caller iterating a slice needs and what the copy is for.
    public var values: [Element] {
        var out = [Element]()
        out.reserveCapacity(count)
        for index in 0..<count { out.append(self[position: index]) }
        return out
    }
}

extension ColumnSlice: Equatable where Element: Equatable {}

/// Rows taken from more than one place — a filtered frame, a sorted one, rows named by index — which
/// is what a caller has after anything but a straight range.
public struct DiscontiguousColumnSlice<Element> {
    public let base: Column<Element>
    private let indices: [Int]
    public var name: String { base.name }

    public init(name: String = "", base: Column<Element>, indices: [Int]) {
        self.base = base
        self.indices = indices
    }

    public var count: Int { indices.count }
    public var isEmpty: Bool { indices.isEmpty }
    public var startIndex: Int { 0 }
    public var endIndex: Int { indices.count }
    public func index(after i: Int) -> Int { i + 1 }
    public func index(before i: Int) -> Int { i - 1 }

    public subscript(position index: Int) -> Element { base[position: indices[index]] }

    public var values: [Element] {
        var out = [Element]()
        out.reserveCapacity(count)
        for index in 0..<count { out.append(self[position: index]) }
        return out
    }

    public var column: Column<Element> { Column<Element>(name: name, values) }
}

extension DiscontiguousColumnSlice: Equatable where Element: Equatable {}

/// A column of a frame whose element type the frame does not commit to: what `frame["price"]` gives
/// when the caller has not asked for a type.
public struct AnyColumn: @unchecked Sendable {
    public var name: String
    private let storage: [Any]

    public init<T>(_ column: Column<T>) {
        self.name = column.name
        self.storage = column.values.map { $0 as Any }
    }

    public init<T>(_ slice: ColumnSlice<T>) {
        self.name = slice.name
        self.storage = slice.values.map { $0 as Any }
    }

    public init<T>(_ slice: DiscontiguousColumnSlice<T>) {
        self.name = slice.name
        self.storage = slice.values.map { $0 as Any }
    }

    public var count: Int { storage.count }

    /// The values as `[Any]`, which is what a row lookup and a frame's own column-copying read. The
    /// column is erased on purpose — a frame holds `AnyColumn`s and a caller that knows the type
    /// asks for it through `values(as:)`, which answers nil for a column of another type rather than
    /// a value of the wrong one.
    public var erasedValues: [Any] { storage }

    public subscript(position index: Int) -> Any { storage[index] }

    /// The values as the type the caller names, or nil when the column is not of that type — which is
    /// the answer a caller needs, because a column of a different type read as this one is how a
    /// frame gives a category column away as a column of zeroes.
    public func values<T>(as type: T.Type = T.self) -> [T]? {
        var out = [T]()
        out.reserveCapacity(storage.count)
        for value in storage {
            guard let typed = value as? T else { return nil }
            out.append(typed)
        }
        return out
    }

    /// The column's own type, when every value in it is of one type. A column that mixes types has
    /// none, and answers nil rather than the first kind it found.
    public var elementType: Any.Type? {
        var found: Any.Type?
        for value in storage {
            let type = Swift.type(of: value)
            if let found = found, found != type { return nil }
            found = type
        }
        return found
    }
}
