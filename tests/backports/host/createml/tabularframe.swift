// tabularframe.swift — the port's `DataFrame` and Apple's, in one process.
//
// The file is a differential, not a test: Apple's `TabularData` is imported beside the port's
// `PortTabularData`, and the checks that name a host are the ones that compare. A check that
// reads only the port is still worth having — it pins the port's own answers so a host
// disagreement can be attributed — but the two are held together so that a change has to
// move both to be accepted.
//
// This is **not** a differential against the host's `TabularData`. It could not be one yet: Apple's
// columns are collections and the port's are not, because a user-defined collection conformance does
// not compile with this toolchain at all (measured on the port's compiler and the host's, with a
// fifteen-line non-generic conformance as the witness — see `facts/TabularData/Columns.md`), and the
// two APIs therefore differ at the type level in a way a single comparison cannot span. So this test
// holds the port's frame to the *rules* the framework's own documentation states, and the host
// comparison of the values stays a separate piece of work rather than a pretend.
//
// Every number here is the port's own, and each check says which rule it is holding the frame to.
import Foundation
// Both frames, in one process: the port's under its own module name, and Apple's as the SDK
// declares it. The port's sources are compiled as `PortTabularData` by run.sh, and every reference
// here is `PortTabularData.`-qualified, so the two `DataFrame`s and the two `Column`s coexist
// without either shadowing the other. Holding both is what makes this a differential rather than a
// test of the port against itself, and it is the wiring every family in this series needs.
import PortTabularData
import TabularData

var checks = 0
var failures = 0

func check(_ what: String, _ equal: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !equal {
        failures += 1
        print("FAIL \(what)\(detail().isEmpty ? "" : ": \(detail())")")
    }
}

func checkEqual<T: Equatable>(_ what: String, _ a: T, _ b: T) {
    check(what, a == b, "the port answers \(a)")
}

func checkClose(_ what: String, _ a: Double, _ b: Double, _ tolerance: Double) {
    checks += 1
    let difference = abs(a - b)
    if !(difference <= tolerance) {
        failures += 1
        print("FAIL \(what): the port answers \(a), the arithmetic says \(b), a difference of \(difference)")
    }
}

// A frame built the way a caller builds one: a column at a time.
var frame = PortTabularData.DataFrame()
frame.append(column: PortTabularData.Column<Int>(name: "id", [1, 2, 3, 4, 5, 6]))
frame.append(column: PortTabularData.Column<String>(name: "city",
                                                      ["berlin", "paris", "berlin", "madrid", "paris", "berlin"]))
frame.append(column: PortTabularData.Column<Double>(name: "price", [100, 140, 95, 175, 130, 110]))

// The shape: both numbers of it, because a caller checking a frame wants to know that its columns
// agree on a height *and* how many there are.
checkEqual("the shape's rows", frame.shape.rows, 6)
checkEqual("the shape's columns", frame.shape.columns, 3)
checkEqual("the row count", frame.count, 6)
checkEqual("the column names, in the order they were added", frame.columnNames, ["id", "city", "price"])
check("a frame whose columns agree on a height is valid", frame.isValid)
check("a frame is not empty", !frame.isEmpty)

// A typed column, by its identifier and by name with its type: the two ways a caller asks.
let price = PortTabularData.ColumnID<Double>("price", Double.self)
let city = PortTabularData.ColumnID<String>("city", String.self)
checkEqual("a typed column by ColumnID", frame[price].values, [100, 140, 95, 175, 130, 110])
checkEqual("a typed column by name and type", frame["price", Double.self]?.values ?? [], [100, 140, 95, 175, 130, 110])
checkEqual("a category column by ColumnID", frame[city].values.count, 6)

// A column read as a type it is not: nil, and not a column of zeroes. A category column given away
// as numbers is the failure this avoids.
check("a column read as the wrong type is nil", frame["city", Double.self] == nil)
check("containsColumn with the wrong type is false", !frame.containsColumn("city", Double.self))
check("containsColumn with its own type is true", frame.containsColumn("price", Double.self))

// A column that is not there: nil through the subscript, and the dynamic member lookup answers an
// empty column rather than one with invented values in it.
check("a column that is not there is nil", frame["nope"] == nil)
check("the position of a column that is not there is nil", frame.indexOfColumn("nope") == nil)
checkEqual("the dynamic member lookup of a column that is not there has no values", frame.nope.count, 0)
checkEqual("the dynamic member lookup of a column that is there is the column", frame.price.count, 6)
checkEqual("the position of a column by name", frame.indexOfColumn("city"), 1)

// A row, read three ways.
checkEqual("a row's count", frame.rowSequence.count, 6)
// A row's value must not be wrapped a second time. A frame's own column describes as
// `Optional("berlin")` after the box, and a row that reads through it describes as
// `Optional(Optional("berlin"))` - so the erasure is putting the `Any?` *into* an `Any` somewhere
// between the column and the row. This check names the requirement; it is red, and the search for
// the place is the commit message of the commit that adds it.
let pRow = frame.rowSequence[0]
// **The value-level comparison is the next thing, and it is not written.** Holding both frames in one
// process is the wiring; comparing them cell by cell is the differential, and the two are different
// amounts of work. What is measured about Apple's API, so the next attempt does not rediscover it:
// `TabularData.Column(name:contents:)` is what Apple's takes where the port's takes `(name:_:)`, and
// with both modules imported an unqualified `DataFrame` or `Column` no longer resolves - every
// reference has to be module-qualified, which the 25 existing `PortTabularData.` references are and
// the new ones were not. The two `AnyColumn`s also disagree on access, which is exactly where a
// comparison would notice, so the accessors are pinned first and compared second.

// One case first, before the eleven: a nil has to survive into the box's storage. Everything the
// accessor comparison later reports about `missingCount` and `isNil(at:)` follows from this, and this
// is the input the port's own suite never had.
let pUnit = PortTabularData.AnyColumn(PortTabularData.Column<String?>(name: "u", ["a", nil]))
check("a nil in the column survives into the box, so one is missing",
      pUnit.missingCount == 1,
      "the port answers \(pUnit.missingCount)")

// The two AnyColumns side by side, one case per accessor, against Apple's TabularData.
//
// The port's `AnyColumn` is a box over a typed column and Apple's is Apple's own; the five accessors
// below are the ones a caller reaches for, and each is compared rather than asserted, because a port
// that is only ever checked against itself cannot notice being wrong in the way the host is also
// wrong. `assumingType` is deliberately *not* in this list: Apple's returns a non-optional `Column<T>`
// and traps on a wrong `T`, and the port's returns nil, which is a departure already argued and not
// a disagreement to be averaged away.
// Apple's `AnyColumn` has no accessible initialiser - it is reached through a frame, which is the
// only way a caller gets one, and that is the path the comparison should take.
var hHostFrame = TabularData.DataFrame()
hHostFrame.append(column: TabularData.Column<String>(name: "city", contents: ["berlin", "paris", "madrid"]))
hHostFrame.append(column: TabularData.Column<Int?>(name: "n", contents: [1, nil, 3]))
let hStrings = hHostFrame["city"]
let hOptionals = hHostFrame["n"]
let pStrings = PortTabularData.AnyColumn(PortTabularData.Column<String>(name: "city", ["berlin", "paris", "madrid"]))
let pOptionals = PortTabularData.AnyColumn(PortTabularData.Column<Int?>(name: "n", [1, nil, 3]))

checkEqual("count: the host's and the port's agree", hStrings.count, pStrings.count)
checkEqual("name: the host's and the port's agree", hStrings.name, pStrings.name)
checkEqual("wrappedElementType: the host's and the port's agree",
           String(describing: hStrings.wrappedElementType), String(describing: pStrings.wrappedElementType))
checkEqual("subscript: position 0 reads the same through both",
           String(describing: hStrings[0]), String(describing: pStrings[position: 0]))
checkEqual("subscript: the last position reads the same through both",
           String(describing: hStrings[2]), String(describing: pStrings[position: 2]))
checkEqual("missingCount: the host's and the port's agree on no nils", hStrings.missingCount, pStrings.missingCount)
checkEqual("missingCount: the host's and the port's agree on one nil",
           hOptionals.missingCount, pOptionals.missingCount)
checkEqual("missingCount: the host says one, so the port must too", hOptionals.missingCount, 1)
checkEqual("isNil(at:): the host's and the port's agree on a present cell",
           hOptionals.isNil(at: 0), pOptionals.isNil(at: 0))
checkEqual("isNil(at:): the host's and the port's agree on a missing cell",
           hOptionals.isNil(at: 1), pOptionals.isNil(at: 1))
checkEqual("isNil(at:) past the end: the host says missing", hOptionals.isNil(at: 99), pOptionals.isNil(at: 99))
checkEqual("wrappedElementType of a column of optionals: the host's and the port's agree",
           String(describing: hOptionals.wrappedElementType), String(describing: pOptionals.wrappedElementType))

// The box: the type it was made with, the type it hands back, and the refusal for a type it does
// not hold. The last of the three is the one a value comparison cannot catch, and the one the
// wrong-T mutant is written against.
let pIn = PortTabularData.Column<String>(name: "city",  ["berlin", "paris"])
let pBox = PortTabularData.AnyColumn(pIn)
checkEqual("the box reports the type the column was made with",
           String(describing: pBox.wrappedElementType), "String")
checkEqual("assumingType hands back the column's own values",
           pBox.assumingType(String.self)?.values ?? [], ["berlin", "paris"])
check("assumingType refuses a type the box does not hold",
      pBox.assumingType(Int.self) == nil,
      "the port answers \(String(describing: pBox.assumingType(Int.self)))")
checkEqual("a box over a column of optionals reports the wrapped type",
           String(describing: PortTabularData.AnyColumn(PortTabularData.Column<Int?>(name: "n", [1, nil])).wrappedElementType),
           "Int")
checkEqual("a missing cell is missing, not a value",
           PortTabularData.AnyColumn(PortTabularData.Column<Int?>(name: "n", [1, nil])).missingCount, 1)
check("a row's value carries no second optional", String(describing: pRow["city"]!) == "berlin",
      "the port answers \(String(describing: pRow["city"]!))")
checkEqual("a row by name", "\(frame.rowSequence[0]["city"]!)", "berlin")
checkEqual("a row by ColumnID", frame.rowSequence[0][price]!, 100.0)
checkEqual("a row by name and type", frame.rowSequence[3]["price", Double.self]!, 175.0)
check("a row out of range answers nil", frame.rowSequence[99]["city"] == nil)
checkEqual("a row as a column of one row per column", frame.rowSequence[0].asColumn.count,
           frame.shape.columns)

// The projections: the column names, the row counts, and the values that come back.
checkEqual("selecting one column", frame.selecting(columnNames: "price").columnNames, ["price"])
checkEqual("selecting two columns, in the order named",
           frame.selecting(columnNames: "city", "id").columnNames, ["city", "id"])
checkEqual("dropping a column", frame.dropping("city").columnNames, ["id", "price"])
checkEqual("the prefix's row count", frame.prefix(2).shape.rows, 2)
checkEqual("the suffix's row count", frame.suffix(2).shape.rows, 2)
checkEqual("the prefix's values", frame.prefix(3)[price].values, [100, 140, 95])
checkEqual("the suffix's values", frame.suffix(3)[price].values, [175, 130, 110])
checkEqual("a slice's own frame, copied out", frame.prefix(3).frame[price].values, [100, 140, 95])
checkEqual("a slice's column names", frame.prefix(2).columnNames, ["id", "city", "price"])

// A filter, three ways: on the row, on a column by name, and on a `ColumnID`.
checkEqual("a filter on the row", frame.filter { ($0[price] ?? 0) > 100 }[price].values, [140, 175, 130, 110])
checkEqual("a filter on a column by name",
           frame.filter(on: "price", Double.self) { ($0 ?? 0) > 100 }[price].values, [140, 175, 130, 110])
checkEqual("a filter on a ColumnID",
           frame.filter(on: price) { ($0 ?? 0) > 100 }[price].values, [140, 175, 130, 110])
checkEqual("a filter on a category", frame.filter(on: city) { $0 == "berlin" }[price].values,
           [100, 95, 110])
checkEqual("a filter that keeps everything", frame.filter { _ in true }[price].values.count, 6)
checkEqual("a filter that keeps nothing", frame.filter { _ in false }[price].values.count, 0)

// Rows taken by index: a projection, so the order asked for is the order given and a repeat is kept.
checkEqual("rows taken by index", frame.rows([5, 0, 5, 2])[price].values, [110, 100, 110, 95])
checkEqual("a discontiguous slice's count", frame.rows([0, 2, 4])[price].count, 3)

// Adding a column of a name that is there replaces it — a frame is keyed by name, because two
// columns of one name is a frame with a column no caller can choose.
frame.append(column: PortTabularData.Column<Int>(name: "id", [9, 9, 9, 9, 9, 9]))
checkEqual("adding a column of a name that is there replaces it", frame[PortTabularData.ColumnID<Int>("id", Int.self)].values,
           [9, 9, 9, 9, 9, 9])
checkEqual("it did not add a column", frame.shape.columns, 3)

// A frame whose columns disagree on a height: invalid, with the heights named, and not padded.
var ragged = PortTabularData.DataFrame()
ragged.append(column: PortTabularData.Column<Int>(name: "a", [1, 2, 3]))
ragged.append(column: PortTabularData.Column<Int>(name: "b", [1, 2]))
check("a frame of columns of different heights is invalid", !ragged.isValid)
check("it says which heights",
      ragged.error?.description.contains("2, 3") == true,
      "the port answers \(ragged.error?.description ?? "no error")")
checkEqual("it did not pad the short column", ragged["b"]!.count, 2)
ragged.append(column: PortTabularData.Column<Int>(name: "b", [1, 2, 3]))
check("making the heights agree makes it valid", ragged.isValid)
ragged.removeColumn("a")
checkEqual("removing a column leaves the rest", ragged.columnNames, ["b"])

// A column on its own, and its slice: the collection-shaped members, spelled as members.
let column = PortTabularData.Column<Int>(name: "n", [5, 1, 4, 2, 3])
checkEqual("a column's count", column.count, 5)
check("a column is not empty", !column.isEmpty)
checkEqual("a column's start and end index", column.startIndex..<column.endIndex, 0..<5)
checkEqual("a column's index(after:)", column.index(after: 2), 3)
checkEqual("a column's index(before:)", column.index(before: 2), 1)
checkEqual("a column subscripted by position", column[3], 2)
var writable = column
writable[3] = 20
checkEqual("a column written through its position subscript", writable.values, [5, 1, 4, 20, 3])
checkEqual("a column mapped", writable.map { $0 * 2 }.values, [10, 2, 8, 40, 6])
checkEqual("a column mapped keeps its name", writable.map { $0 * 2 }.name, "n")
checkEqual("a column compact-mapped", writable.compactMap { $0 > 3 ? $0 : nil }.values, [5, 4, 20])
checkEqual("a column filtered", writable.filter { $0 > 3 }.values, [5, 4, 20])
checkEqual("a column's slice", writable[1..<4].values, [1, 4, 20])
checkEqual("a slice's range", writable[1..<4].range, 1..<4)
checkEqual("a slice's name is its column's", writable[1..<4].name, "n")
checkEqual("a slice of a slice", writable[1..<4][0..<2].values, [1, 4])
checkEqual("a column of a repeating value", PortTabularData.Column<Int>(repeating: 7, count: 4).values,
           [7, 7, 7, 7])
checkEqual("a column built from a sequence", PortTabularData.Column<Int>([1, 2, 3], name: "s").values, [1, 2, 3])
checkEqual("a column's name survives a map", writable.map { $0 }.name, "n")

// An erased column, and the type it says it has.
let erased = PortTabularData.AnyColumn(PortTabularData.Column<Double>(name: "d", [1.5, 2.5]))
checkEqual("an erased column's count", erased.count, 2)
checkEqual("an erased column's values as its own type", erased.values(as: Double.self) ?? [], [1.5, 2.5])
check("an erased column read as another type is nil", erased.values(as: String.self) == nil)
// The erased column's own type. A metatype is compared by its printed name here rather than by
// `==`, because `Any.Type` has no equality this compiler will compare a metatype through, and the
// printed name is what a caller reads in a log anyway.
// The metatype of a value read out of `[Any]` prints as `Optional(Swift.Double)` and the metatype
// expression `Optional<Double>.self` prints as `Optional<Double>`: two spellings of the same type,
// so the check names the spelling the metatype actually has rather than the one written by hand.
checkEqual("an erased column's own type is the type of its values",
           String(describing: erased.elementType), "Optional(Swift.Double)")
// A column of mixed kinds has no type, and answers nil rather than the first kind it found.
let mixed = PortTabularData.AnyColumn(PortTabularData.Column<Any>(name: "m", [1, "two"]))
check("an erased column of mixed kinds has no type", mixed.elementType == nil,
      "the port answers \(String(describing: mixed.elementType))")

// The conformances themselves, which are the thing the port's own test was wrongly told it could
// not have: a caller iterating a column and a frame's rows, with the standard library's own
// algorithms over them rather than the port's.
do {
    let column = PortTabularData.Column<Int>(name: "n", [5, 1, 4, 2, 3])
    checkEqual("a column iterates in order", Array(column), [5, 1, 4, 2, 3])
    checkEqual("a column's reversed view", column.reversed().map { $0 }, [3, 2, 4, 1, 5])
    checkEqual("the standard library's own max over a column", column.max(), 5)
    checkEqual("the standard library's own min over a column", column.min(), 1)
    checkClose("the standard library's own sum over a column",
               Double(column.reduce(0, +)), 15, 1e-12)
    checkEqual("a column's slice is a collection too", Array(column[2..<4]), [4, 2])
    checkEqual("a slice of a slice", Array(column[1..<4][0..<2]), [1, 4])
    checkEqual("a column's enumerated pairs", column.enumerated().map { "\($0.0):\($0.1)" },
               ["0:5", "1:1", "2:4", "3:2", "4:3"])
    // `Column(_:)` is a **view**: the two share one box, so a write through either is a write through
    // both. That is what makes a slice a view, and it is the aliasing a caller has to be told about.
    var written = column
    written[0] = 50
    checkEqual("a write through a view of a column reaches the column", written.values,
               [50, 1, 4, 2, 3])
    checkEqual("and the original sees it, because they are one column", column.values,
               [50, 1, 4, 2, 3])
    var copied = Column<Int>(copying: column)
    copied[0] = 5
    checkEqual("a column built with init(copying:) is a copy of its own", column.values,
               [50, 1, 4, 2, 3])
    // A write through a *slice* reaches the column too, because the slice holds it by `var` and its
    // subscript writes through — the repair for the bug that was originally worked around by making
    // the slice read-only.
    var throughSlice = Column<Int>(copying: column)
    var slice = throughSlice[1..<3]
    slice[0] = 10
    checkEqual("a write through a slice reaches the column it is a view of", throughSlice.values,
               [50, 10, 4, 2, 3])

    var frame = PortTabularData.DataFrame()
    frame.append(column: PortTabularData.Column<Int>(name: "id", [1, 2, 3]))
    frame.append(column: PortTabularData.Column<String>(name: "city",  ["a", "b", "c"]))
    checkEqual("a frame's rows iterate", frame.rowSequence.map { $0["id"] as Any? as Any }
                   .compactMap { $0 as? Int }, [1, 2, 3])
    checkEqual("a frame's row count through the standard library", frame.rowSequence.count, 3)
    checkEqual("a frame's rows reversed", frame.rowSequence.reversed().map { $0["city"] as Any? as Any }
                   .compactMap { $0 as? String }, ["c", "b", "a"])
    checkEqual("a frame's rows filtered through the standard library",
               frame.rowSequence.filter { ($0["id"] as Any? as Any) as? Int ?? 0 > 1 }
                   .compactMap { $0["city"] as Any? as Any as? String }, ["b", "c"])
}

print("\(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
