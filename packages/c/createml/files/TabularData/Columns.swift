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
    /// `[Element?]`, not `[Element]`: the SDK's `Column<WrappedElement>` is itself
    /// `OptionalColumnProtocol`, and the missing cell is expressed by the *type* rather than by a
    /// separate optional column. A column therefore has to be able to hold a nil while reporting its
    /// element type as the value's own type, and `[Element]` cannot hold one at all.
    var values: [Element?]

    init(_ values: [Element?]) { self.values = values }
}

/// A column of a frame, holding values of one type.
public struct Column<Element>: ColumnProtocol {
    public var name: String
    /// The column's values, in the box every view of this column shares. `storage` is `internal` and
    /// the views are in this file, so nothing outside can reach past the value semantics.
    internal let storage: ColumnStorage<Element>
    /// The column's cells, each of which may be missing. `Element` is the *value* type, so a nil
    /// here is a cell with no value and a `.some(nil)` a value that is itself an optional - the
    /// distinction the SDK keeps and this column now keeps with it.
    public var values: [Element?] {
        get { storage.values }
        set { storage.values = newValue }
    }

    /// The cells that hold a value, with the missing ones dropped. What most callers of a column
    /// want, and the port's own readers used to get it from `values` before the missing cell became
    /// expressible.
    public var presentValues: [Element] { storage.values.compactMap { $0 } }

    /// Every initialiser assigns the **box** first and `name` second: `values` goes through the box,
    /// so writing `self.values` before the box exists reads `self` uninitialised. That is a real
    /// Swift restriction and not a style choice, and it is why the order is the same in all of them.
    public init(name: String = "") {
        self.storage = ColumnStorage<Element>([])
        self.name = name
    }

    public init(name: String = "", _ values: [Element]) {
        self.storage = ColumnStorage<Element>(values.map { $0 })
        self.name = name
    }

    /// The SDK's two `contents:` initialisers, verbatim in their constraints.
    ///
    ///     public init<S>(name: String, contents: S) where S: Sequence, S.Element == WrappedElement?
    ///     public init<S>(name: String, contents: S) where WrappedElement == S.Element, S: Sequence
    ///
    /// The first is the ordinary form: the cells are `Element?` and a `nil` in them is a missing
    /// cell by the type. The second is the present form: the cells are `Element` and cannot be
    /// missing. The port could not write the first before, because `Column<Int>(name:_:)` took
    /// `[Int]` and `nil` did not fit - so a column that is missing a cell had no spelling at all.
    public init<S>(name: String, contents: S) where S: Sequence, S.Element == Element? {
        self.storage = ColumnStorage<Element>(Array(contents))
        self.name = name
    }

    public init<S>(name: String, contents: S) where Element == S.Element, S: Sequence {
        self.storage = ColumnStorage<Element>(contents.map { $0 })
        self.name = name
    }

    public init<S: Sequence>(_ source: S, name: String = "") where S.Element == Element {
        self.storage = ColumnStorage<Element>(source.map { $0 })
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
        self.storage = ColumnStorage<Element>(column.storage.values)
        self.name = name ?? column.name
    }

    public init(repeating value: Element, count: Int, name: String = "") {
        self.storage = ColumnStorage<Element>([Element?](repeating: value, count: count))
        self.name = name
    }


    /// How many cells, missing ones included. A plain member rather than a `Collection` one: the
    /// column is not a `Collection` (Apple's is not either, and an optional subscript cannot be one)
    /// and the count of its cells is asked for constantly.
    public var count: Int { values.count }
    public var isEmpty: Bool { values.isEmpty }
    public var startIndex: Int { 0 }
    public var endIndex: Int { values.count }
    public func index(after i: Int) -> Int { i + 1 }
    public func index(before i: Int) -> Int { i - 1 }

    /// A cell, which may be missing. `Element?` is what makes a column that is missing a cell
    /// possible, and it is the SDK's own subscript type.
    public subscript(position: Int) -> Element? {
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

    /// The cells, transformed. A missing cell stays missing: the transform sees the present values
    /// and the gap is carried through, so `map` over a column that is missing a cell does not
    /// invent one and does not lose the place.
    public func map<T>(_ transform: (Element) throws -> T) rethrows -> Column<T> {
        Column<T>(name: name, contents: try values.map { $0.map(transform) })
    }

    /// The cells, transformed, with the results that are nil dropped **and** the missing cells
    /// dropped: both are absent, which is what `compactMap` has always meant.
    public func compactMap<T>(_ transform: (Element) throws -> T?) rethrows -> Column<T> {
        Column<T>(name: name, try values.compactMap { try $0?.map(transform) })
    }

    /// The cells the predicate keeps. A missing cell is not a value to ask about, so it is dropped
    /// rather than passed to the predicate: a predicate over `Element` cannot be given a cell that
    /// has none.
    public func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> Column<Element> {
        Column<Element>(name: name, contents: try values.compactMap { try $0.map(isIncluded) })
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

    /// The type the column's elements have, recorded when the column was made and with any
    /// optional layer taken off.
    ///
    /// This is Apple's `wrappedElementType`, and it is the whole reason this type is a box rather
    /// than a wrapper around `[Any]`. Inferred from the values it would be three different answers:
    /// `nil` for an empty column, `nil` for one that mixes types, and `Optional<T>` rather than `T`
    /// for a column of optionals — and the last of those is not an edge case here, because a `Row`
    /// builds its own column out of `[Any?]`. So the type is recorded, and `wrapped` is what the
    /// word means: a `Column<Any?>` reports `Any`.
    public let wrappedElementType: Any.Type

    /// The values, erased but not destroyed. `nil` survives as a nil, which is the only thing that
    /// makes `missingCount` and `isNil(at:)` answerable at all.
    private let storage: [Any?]

    /// Builds the typed column back, under whatever name the box currently has.
    ///
    /// This is the box's inside. It is a closure rather than a stored `Column<T>` because Swift
    /// cannot hold a `Column` of an unknown `T` in a non-generic type, and the alternative - dropping
    /// the type and rebuilding the column from the erased values - is the failure this change exists
    /// to remove: a rebuilt `Column<T>` would be a column of zeros and it would compile. The closure
    /// takes the name so renaming the box renames the typed column it hands back.
    private let makeTyped: (String) -> Any

    public init<T>(_ column: Column<T>) {
        self.name = column.name
        self.wrappedElementType = _wrappedType(of: T.self)
        // An element that is already optional keeps its own nil and is not wrapped a second time.
        // `Row` builds its column from `[Any?]`, so without this the row's values arrive as
        // `Optional(Optional("berlin"))` and every row read describes as an optional of the value.
        self.storage = column.values.map { _withoutOptionalLayer($0 as Any) }
        self.makeTyped = { renamed in
            var copy = column
            copy.name = renamed
            return copy
        }
    }

    public init<T>(_ slice: ColumnSlice<T>) {
        self.init(Column(slice.base, name: slice.base.name)[slice.range])
    }

    public init<T>(_ slice: DiscontiguousColumnSlice<T>) {
        // A discontiguous slice's values are a copy of the columns it names, in that order, so the box
        // holds a column of them. The indices are not kept: an `AnyColumn` is contiguous, which is why
        // a caller that needs the positions asks the slice rather than the column.
        self.init(Column(name: slice.name, slice.values))
    }

    public var count: Int { storage.count }

    /// How many of the elements are nil, counted by asking each position rather than kept as a
    /// tally: a tally would be a second answer to the same question, and a differential would only
    /// ever compare the tally with itself.
    public var missingCount: Int {
        var missing = 0
        for index in storage.indices where storage[index] == nil { missing += 1 }
        return missing
    }

    /// Whether the element at a position is nil. A position outside the column is nil, so an index
    /// past the end reads as missing rather than trapping.
    public func isNil(at index: Int) -> Bool {
        guard storage.indices.contains(index) else { return true }
        return storage[index] == nil
    }

    /// The column as a `Column<T>`, or `nil` when the box does not hold a `T`.
    ///
    /// Apple's signature is non-optional, so a wrong `T` on Apple's type traps. The port answers nil
    /// instead, for two reasons that are the same reason: a trap cannot be tested, and the port's box
    /// is a value a caller can build, so the wrong `T` is reachable. A frame that handed out a
    /// `Column<T>` of anything but `T` is the failure this guards, and the differential checks the
    /// values that come back, not the type that came back.
    public func assumingType<T>(_ type: T.Type) -> Column<T>? {
        guard wrappedElementType == T.self else { return nil }
        return makeTyped(name) as? Column<T>
    }

    /// The values as `[Any]`, which is what a row lookup and a frame's own column-copying read. The
    /// column is erased on purpose — a frame holds `AnyColumn`s and a caller that knows the type
    /// asks for it through `values(as:)`, which answers nil for a column of another type rather than
    /// a value of the wrong one.
    /// The values as the frame stores them, and the payload of each rather than the box.
    ///
    /// `storage` is `[Any?]` so a nil element survives. Handing that back as `[Any]` goes through an
    /// implicit `Any?` -> `Any` conversion that *boxes* the optional rather than taking it off, so
    /// "berlin" arrives as `Optional(Optional("berlin"))` and a row that reads through here describes
    /// as an optional of the value. The optional is taken off here, by hand, and a missing cell stays
    /// a nil instead of becoming a value.
    public var erasedValues: [Any] {
        storage.map { element -> Any in
            guard let element = element else { return Optional<Any>.none as Any }
            return element
        }
    }

    public subscript(position index: Int) -> Any {
        guard index >= 0 && index < storage.count else { return Optional<Any>.none as Any }
        guard let element = storage[index] else { return Optional<Any>.none as Any }
        return element
    }

    /// The values as the type the caller names, or nil when the column is not of that type — which is
    /// the answer a caller needs, because a column of a different type read as this one is how a
    /// frame gives a category column away as a column of zeroes.
    /// The values as the type the caller names, with the missing cells dropped, or `nil` when the
    /// column is not of that type. Dropped rather than kept as `nil`s: a caller asking for the
    /// values of a column wants the values, and a column missing a cell asked this way says how many
    /// it has rather than pretending the cell is there. `values(as:)` is not Apple's accessor -
    /// Apple reaches the cells through the subscript, which is `Element?` - so it is the port's, and
    /// it drops the missing on purpose.
    public func values<T>(as type: T.Type = T.self) -> [T]? {
        var out = [T]()
        out.reserveCapacity(storage.count)
        for value in storage {
            guard let value = value else { continue }
            guard let typed = value as? T else { return nil }
            out.append(typed)
        }
        return out
    }

    /// The type every *present* value has, or nil when the present values disagree. The storage is
    /// `[Any?]` so a nil element survives, and the inference looks through the optional: a column that
    /// is half nils is a column of one type with gaps, not a column of `Optional<Any>`.
    public var elementType: Any.Type? {
        var found: Any.Type?
        for value in storage {
            guard let value = value else { continue }
            let type = Swift.type(of: value)
            if let found = found, found != type { return nil }
            found = type
        }
        return found
    }
}

/// The two questions the box has to ask about an element type, without a way to name the type itself.
private protocol _AlreadyOptional {
    /// The value with its optional taken off, so a `nil` arrives as a `nil` and not as a layer.
    var anyValue: Any? { get }
    /// The type underneath, which is what `wrappedElementType` reports.
    static var wrappedElementType: Any.Type { get }
}

/// The value with any optional layer taken off, or `nil` when the value *was* nil.
///
/// Structural, on purpose. The previous version asked `(value as Any) as? _AlreadyOptional` and took
/// the answer, and the answer was `nil` in the sense that the branch never ran: nothing in the port's
/// own 431 checks put a nil into a column, so a cast that cannot fail loudly looked exactly like a
/// cast that worked. A `Mirror` cannot be swallowed that way - a value that is not optional has
/// `displayStyle != .optional` and comes back untouched, `.some` unwraps to its child, and `.none` has
/// no child and answers `nil`.
private func _withoutOptionalLayer(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else { return value }
    return mirror.children.first?.value
}

/// The type underneath an optional, or the type itself when it is not one.
private func _wrappedType(of type: Any.Type) -> Any.Type {
    guard let optional = type as? _AlreadyOptional.Type else { return type }
    return optional.wrappedElementType
}

extension Optional: _AlreadyOptional {
    var anyValue: Any? {
        switch self {
        case .none: return nil
        case .some(let value): return value
        }
    }

    static var wrappedElementType: Any.Type { Wrapped.self }
}
