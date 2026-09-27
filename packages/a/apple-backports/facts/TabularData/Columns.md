# `DataFrame`, its columns, and the one conformance this toolchain will not compile

## The measurement, and what it decides

A user-defined collection conformance does not compile with the port's Swift 6.4. The witness is
fifteen lines and has nothing to do with CreateML:

```swift
public struct Fixed: RandomAccessCollection {
    public var values: [Double]
    public typealias Index = Int
    public typealias Indices = Range<Int>
    public init(_ v: [Double]) { values = v }
    public var startIndex: Int { 0 }
    public var endIndex: Int { values.count }
    public func index(after i: Int) -> Int { i + 1 }
    public func index(before i: Int) -> Int { i - 1 }
    public subscript(position i: Int) -> Double { values[i] }
}
```

and it is rejected with

```
type 'Fixed' does not conform to protocol 'RandomAccessCollection'
type 'Fixed' does not conform to protocol 'BidirectionalCollection'
```

**Measured on both compilers**: the port's own, at `-target armv7-apple-ios6.0` with its own
resource directory (`Apple Swift version 6.4 (swift-6.4-RELEASE)`), and the host's. `Array`, in the
same standard library, conforms without trouble. So this is the compiler and not the declarations.

It was reached by four shapes, all of which fail identically: Apple's own spelling (the struct's
generic parameter also named `Element`, `typealias Element = Element`), a different parameter name,
`RandomAccessCollection` instead of `BidirectionalCollection`, and an explicit
`subscript(bounds: Range<Int>) -> SubSequence` with `SubSequence` and `Indices` both named. The
compiler's own note names the likely cause — `Column<E>.SubSequence` (aka `ColumnSlice<E>`) — and
naming it does not help: the slice conforming as a `BidirectionalCollection` in the same file
changes nothing.

## What the port does, and what it therefore cannot

`ColumnProtocol<Element>` is declared with its primary associated type and its `name`, and **without**
the `BidirectionalCollection` inheritance:

```swift
public protocol ColumnProtocol<Element> {
    associatedtype Element
    var count: Int { get }
    var isEmpty: Bool { get }
    var name: String { get set }
}
```

The concrete column types — `Column<Element>`, `ColumnSlice<Element>`,
`DiscontiguousColumnSlice<Element>` — carry the collection's members as **members**: `count`,
`isEmpty`, `startIndex`, `endIndex`, `index(after:)`, `index(before:)`, `subscript(position:)` and
`subscript(bounds:)`, spelled with the labels the collection requirement has. Those labels are kept
deliberately: they are the names the surface's rows are written against, so a row that says
`ColumnSlice.subscript(index:)` is placed by a declaration that says `subscript(position:)`.

**The cost is the conformance and nothing else.** A caller cannot write `for value in column`; they
write `for index in 0..<column.count`. Everything else — a typed column by `ColumnID<T>`, a row by
name, a filter, a projection, a slice — is here and is exercised by
`tests/backports/host/createml/tabularframe.swift`.

**What is not here, and is absent rather than stubbed**: the CSV and JSON readers and writers
(`readCSV`, `writeCSV`, `readJSON`, `writeJSON`), the summaries (`NumericSummary`,
`CategoricalSummary`, `GroupSummaries`, `SummaryColumnIDs`), the `RowGrouping` family, the
grouping and aggregation, `SFrameReadingOptions`, `ShapedData`, and the `DataFrameProtocol`
conformance. Each is a body of its own. `CreateML.MLDataTable`'s reader and writer *are* carried and
are the way in on this port today.

## What a frame is, and the two rules it keeps

A frame is a list of named columns and a row count, keyed by name: adding a column of a name that is
already there **replaces** it, because two columns of one name is a frame with a column no caller
can choose. And a frame whose columns disagree on a height is **invalid**, and says which heights —
it does not pad the short column, because a padded column is a table of invented data and every
summary over it would be a summary of the invention. Both are checked, and the ragged case names the
heights in its `error`.

An erased column read as a type it is not answers `nil` and not a column of zeroes: a category column
given away as numbers is the failure that avoids.

## What is *not* compared against the host, and why

`tests/backports/host/createml/tabularframe.swift` holds this frame to the framework's own documented
rules and prints the port's own numbers. It is deliberately **not** a differential against the
host's `TabularData`, because the two types cannot be compared across: Apple's columns are
collections and these are not, and the divergence is at the type level, not in a value. A differential
that has to bridge that is a differential of the bridge. The host comparison of the *values* — a
frame's shape, its column names, the typed column's contents, the projections, the filter, the two
failures — is real work and is not done; it is the next thing on this surface.
