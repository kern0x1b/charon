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
///
/// It does not refine a collection — see the file's header for the measurement — and the columns
/// conform to `BidirectionalCollection` themselves.
public protocol ColumnProtocol<Element> {
    associatedtype Element
    var name: String { get set }
}

/// A column's storage, in a box.
///
/// The box is what makes a slice a **view** rather than a copy. `Column` is a struct, so a
/// `ColumnSlice` holding it by value holds a *copy* of the column, and a write through the slice
/// would land in that copy while the frame kept the old value — the exact silent no-op the first
/// version of this file avoided by making the slice read-only, which cost every caller the ability to
/// write through a view. With the storage in a reference the slice and the column see the same values,
/// which is what the name says and what the framework's own slice does.
internal final class ColumnStorage<Element>: @unchecked Sendable {
    var values: [Element]

    init(_ values: [Element]) { self.values = values }
}

/// A column of a frame, holding values of one type.
public struct Column<Element>: ColumnProtocol, BidirectionalCollection {
    public var name: String
    /// The column's values, in the box every view of this column shares. `storage` is `internal` and
    /// the views are in this file, so nothing outside can reach past the value semantics.
    internal let storage: ColumnStorage<Element>
    public var values: [Element] {
        get { storage.values }
        set { storage.values = newValue }
    }

    /// Every initialiser assigns the **box** first and `name` second: `values` goes through the box,
    /// so writing `self.values` before the box exists reads `self` uninitialised. That is a real
    /// Swift restriction and not a style choice, and it is why the order is the same in all of them.
    public init(name: String = "") {
        self.storage = ColumnStorage<Element>([])
        self.name = name
    }

    public init(name: String = "", _ values: [Element]) {
        self.storage = ColumnStorage<Element>(values)
        self.name = name
    }

    public init<S: Sequence>(_ source: S, name: String = "") where S.Element == Element {
        self.storage = ColumnStorage<Element>(Array(source))
        self.name = name
    }

    /// A **view** of another column: the storage is shared, so a write through either is a write
    /// through both, which is what makes `ColumnSlice` a view rather than a copy. Only
    /// `init(copying:)` starts a column of its own over the same values.
    public init(_ column: Column<Element>, name: String? = nil) {
        self.storage = column.storage
        self.name = name ?? column.name
    }

    /// A column of its own over a copy of another one's values.
    public init(copying column: Column<Element>, name: String? = nil) {
        self.storage = ColumnStorage<Element>(column.values)
        self.name = name ?? column.name
    }

    public init(repeating value: Element, count: Int, name: String = "") {
        self.storage = ColumnStorage<Element>([Element](repeating: value, count: count))
        self.name = name
    }


    public typealias SubSequence = ColumnSlice<Element>

    public var startIndex: Int { 0 }
    public var endIndex: Int { values.count }
    public func index(after i: Int) -> Int { i + 1 }
    public func index(before i: Int) -> Int { i - 1 }

    public subscript(position: Int) -> Element {
        get { values[position] }
        set { values[position] = newValue }
    }

    public subscript(bounds: Range<Int>) -> ColumnSlice<Element> {
        ColumnSlice(base: self, range: bounds)
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

/// Equality is over the *values*, not over the boxes: two columns holding the same numbers are the
/// same column whatever boxes they are in, and a row projection that copies a column's values must
/// compare equal to the column it came from.
extension Column: Equatable where Element: Equatable {
    public static func == (lhs: Column, rhs: Column) -> Bool {
        lhs.name == rhs.name && lhs.values == rhs.values
    }
}

extension Column: Sendable where Element: Sendable {}

/// A contiguous run of a column's rows: the column and a range into it.
public struct ColumnSlice<Element>: ColumnProtocol, BidirectionalCollection {
    /// The column the slice is a run of. Held by value and **mutable**, so a write through the slice
    /// reaches the column.
    ///
    /// It used to be a `let` with a read-only subscript, on the reasoning that a slice holds its
    /// base by value so a write would land in a copy and the frame would keep the old value. That
    /// reasoning was right about the bug and wrong about the repair: the bug was a subscript spelled
    /// with a second parameter name (see the file's header), and the honest fix is to let the write
    /// through. A column's slice is a view of that column, and a view that cannot be written is a
    /// copy wearing a view's name.
    public var base: Column<Element>
    public let range: Range<Int>
    public var name: String {
        get { base.name }
        set { base.name = newValue }
    }

    public typealias SubSequence = ColumnSlice<Element>

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

    public subscript(position: Int) -> Element {
        get { base[range.lowerBound + position] }
        set { base[range.lowerBound + position] = newValue }
    }

    public subscript(bounds: Range<Int>) -> ColumnSlice<Element> {
        ColumnSlice(base: base,
                    range: range.lowerBound + bounds.lowerBound ..< range.lowerBound + bounds.upperBound)
    }

    /// The slice as a column of its own, which **is** a copy: a caller asking for a column of the
    /// slice's values gets values of their own, and `Column(_:)` with a name makes a view of it
    /// instead.
    public var column: Column<Element> { Column<Element>(name: name, values) }

    /// The values, which is what a caller reading a slice as a column needs and what the copy is for.
    public var values: [Element] { Array(self) }
}

extension ColumnSlice: Equatable where Element: Equatable {}

/// Rows taken from more than one place — a filtered frame, a sorted one, rows named by index — which
/// is what a caller has after anything but a straight range.
public struct DiscontiguousColumnSlice<Element>: ColumnProtocol, BidirectionalCollection {
    public var base: Column<Element>
    private let indices: [Int]
    public var name: String {
        get { base.name }
        set { base.name = newValue }
    }

    public typealias SubSequence = DiscontiguousColumnSlice<Element>

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

    public subscript(position: Int) -> Element {
        get { base[indices[position]] }
        set { base[indices[position]] = newValue }
    }

    public subscript(bounds: Range<Int>) -> DiscontiguousColumnSlice<Element> {
        DiscontiguousColumnSlice(base: base, indices: Array(indices[bounds]))
    }

    public var values: [Element] { Array(self) }

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
