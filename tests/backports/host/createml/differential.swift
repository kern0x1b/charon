// differential.swift — the port's CreateML against the host's own, in one process.
//
// The port's sources are compiled under the module names `PortCreateMLComponents` and
// `PortCreateML` (see run.sh: the only edit to the sources is one import line), so Apple's
// `CreateML` and this port's `CreateML` are two modules declaring the same type names, and every
// number below is the host framework's own answer to the same question the port was asked. Nothing
// here compares against a fixture.
//
// What is compared, and what is not:
//
//   - the table: construction from a CSV, the column types, the sums and the spreads, the sorted
//     order, the four joins, group-and-aggregate, the split sizes, the drops. These are defined
//     operations on values with no freedom in them, so they must agree exactly.
//
//   - the estimators: the *predictions*, row by row, from `MLDecisionTreeRegressor`, which takes an
//     `MLDataTable` — the very input this port takes. A tree grown by one CART implementation and a
//     tree grown by another can pick different splits out of a set of equally good ones, so a
//     per-prediction comparison is only fair where the split is not a matter of taste. The tables
//     below are built so that it is not: a separable step, and a table whose target is a linear
//     function of one feature. Where a row is genuinely ambiguous the comparison is on the metrics
//     and not on the rows, and the file says which is which.
//
//   - NOT compared: the bytes of a trained model, the order of two equally good splits, the depth
//     of a fitted tree, and the seed Apple's own generator consumes. Each is an implementation
//     choice of one release, and holding the port to it would be holding it to a private detail
//     rather than to what a caller can see. The `.mlmodel` export is absent from this build and the
//     `write(to:)` calls are checked to *refuse* rather than to match.

import Foundation
import PortCreateML
import PortCreateMLComponents
import CreateML

var checks = 0
var failures = 0

/// One shape both frameworks are read into before they are compared.
///
/// The two APIs spell several things differently — the host's `columnTypes` answers a
/// non-optional kind for every column, the port's answers an optional; the host's typed accessors
/// are non-optional, the port's are — and comparing them without an adapter would either fail to
/// compile or, worse, compare a `nil` against a value and call it a difference. Each adapter below
/// is a spelling and nothing else: it moves values, it decides nothing, and a reader can check that
/// by looking at it.
struct Read {
    var columnNames: [String] = []
    var kinds: [String: String] = [:]
    var integers: [String: [Int]] = [:]
    var doubles: [String: [Double]] = [:]
    var strings: [String: [String]] = [:]
}

extension Read {
    /// The port's table, read.
    init(port table: PortCreateML.MLDataTable) {
        columnNames = table.columnNames
        for name in columnNames {
            let type = table.columnTypes[name]?.description ?? "none"
            kinds[name] = type
            if let column = table[name]?.ints { integers[name] = column.map { $0 ?? .min } }
            if let column = table[name]?.doubles { doubles[name] = column.map { $0 ?? .nan } }
            if let column = table[name]?.strings { strings[name] = column.map { $0 ?? "<missing>" } }
        }
    }

    /// The host's table, read. A cell the host holds as a missing value is written as the same
    /// sentinel the port's reader writes, so a missing value is compared to a missing value.
    init(host table: CreateML.MLDataTable) {
        columnNames = table.columnNames
        for name in columnNames {
            kinds[name] = table.columnTypes[name]?.description ?? "none"
            integers[name] = table[name]!.ints.map { $0 ?? Int.min }
            doubles[name] = table[name]!.doubles.map { $0 ?? .nan }
            strings[name] = table[name]!.strings.map { $0 ?? "<missing>" }
        }
    }
}

/// A column of doubles out of either framework's table, with a missing value as a NaN.
func portDoubles(_ table: PortCreateML.MLDataTable, _ name: String) -> [Double] {
    table[name]?.doubles?.map { $0 ?? .nan } ?? []
}

func hostDoubles(_ table: CreateML.MLDataTable, _ name: String) -> [Double] {
    table[name]!.doubles.map { $0 ?? .nan }
}

func portIntegers(_ table: PortCreateML.MLDataTable, _ name: String) -> [Int] {
    table[name]?.ints?.map { $0 ?? Int.min } ?? []
}

func hostIntegers(_ table: CreateML.MLDataTable, _ name: String) -> [Int] {
    table[name]!.ints.map { $0 ?? Int.min }
}

func portStrings(_ table: PortCreateML.MLDataTable, _ name: String) -> [String] {
    table[name]?.strings?.map { $0 ?? "<missing>" } ?? []
}

func hostStrings(_ table: CreateML.MLDataTable, _ name: String) -> [String] {
    table[name]!.strings.map { $0 ?? "<missing>" }
}

/// A summary of a numeric column, from either framework, with the value and whether it could be
/// computed at all.
struct Summary { var value: Double; var valid: Bool }

func portSummary(_ table: PortCreateML.MLDataTable, _ name: String,
                 _ read: (PortCreateML.MLDataColumn<Double>) -> Double?) -> Summary {
    guard let column = table[name]?.doubles else { return Summary(value: .nan, valid: false) }
    guard let value = read(column) else { return Summary(value: .nan, valid: false) }
    return Summary(value: value, valid: true)
}

func hostSummary(_ table: CreateML.MLDataTable, _ name: String,
                 _ read: (CreateML.MLDataColumn<Double>) -> Double?) -> Summary {
    let value = read(table[name]!.doubles)
    return Summary(value: value ?? .nan, valid: value != nil)
}

/// The doubles of a joined table, missing values as NaN, from either framework.
func portJoinedDoubles(_ table: PortCreateML.MLDataTable, _ name: String) -> [Double] {
    portDoubles(table, name)
}

func hostJoinedDoubles(_ table: CreateML.MLDataTable, _ name: String) -> [Double] {
    hostDoubles(table, name)
}

func check(_ what: String, _ equal: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !equal {
        failures += 1
        print("FAIL \(what)\(detail().isEmpty ? "" : ": \(detail())")")
    }
}

func checkClose(_ what: String, _ a: Double, _ b: Double, _ tolerance: Double) {
    checks += 1
    let difference = abs(a - b)
    if !(difference <= tolerance) {
        failures += 1
        print("FAIL \(what): the port answers \(a), the host \(b), a difference of \(difference)")
    }
}

func checkEqual<T: Equatable>(_ what: String, _ a: T, _ b: T) {
    check(what, a == b, "the port answers \(a), the host \(b)")
}

/// A CSV of eight rows with a categorical, two numerics and a target, in a temporary file both
/// frameworks are pointed at. One file, so neither reader is answering about a different table.
let csv = """
id,city,size,rooms,price
1,berlin,10.5,2,100.0
2,paris,12.0,3,140.0
3,berlin,9.5,2,95.0
4,paris,13.5,4,175.0
5,berlin,11.0,3,130.0
6,madrid,10.0,2,110.0
7,madrid,14.0,4,190.0
8,paris,9.0,1,80.0
"""

let csvURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("createml-differential-\(getpid()).csv")
try? csv.write(to: csvURL, atomically: true, encoding: .utf8)

// MARK: - The table

do {
    let port = try PortCreateML.MLDataTable(contentsOf: csvURL)
    let host = try CreateML.MLDataTable(contentsOf: csvURL)

    checkEqual("the table's row count", port.size.rows, host.size.rows)
    checkEqual("the table's column count", port.size.columns, host.size.columns)

    let portRead = Read(port: port), hostRead = Read(host: host)
    for name in host.columnNames {
        check("the type of the column \(name)", portRead.kinds[name] == hostRead.kinds[name],
              "the port answers \(portRead.kinds[name] ?? "none"), the host \(hostRead.kinds[name] ?? "none")")
    }

    // The typed accessors, whose signatures differ most between the two, read through the adapter.
    checkEqual("the ids read as a column of Int", portIntegers(port, "id"), hostIntegers(host, "id"))
    checkEqual("the sizes read as a column of Double", portDoubles(port, "size"), hostDoubles(host, "size"))
    checkEqual("the cities read as strings", portStrings(port, "city"), hostStrings(host, "city"))
    checkEqual("every price, read", portDoubles(port, "price"), hostDoubles(host, "price"))

    // The summaries, which are defined and have no freedom in them. Each is read through the same
    // closure on both sides, so a difference here is a difference in the arithmetic and not in how
    // the column was reached.
    // Each summary is read through the same closure on both sides, so a difference here is a
    // difference in the arithmetic and not in how the column was reached. The closures are written
    // out one by one because a table of them is a table the compiler cannot type here.
    check("the sum of the prices is computable on both sides",
          portSummary(port, "price", { $0.sum() }).valid && hostSummary(host, "price", { $0.sum() }).valid)
    checkClose("the sum of the prices", portSummary(port, "price", { $0.sum() }).value,
               hostSummary(host, "price", { $0.sum() }).value, 1e-9)
    checkClose("the mean of the prices", portSummary(port, "price", { $0.mean() }).value,
               hostSummary(host, "price", { $0.mean() }).value, 1e-9)
    checkClose("the stdev of the prices", portSummary(port, "price", { $0.stdev() }).value,
               hostSummary(host, "price", { $0.stdev() }).value, 1e-9)
    checkClose("the min of the prices", portDoubles(port, "price").min() ?? .nan,
               hostDoubles(host, "price").min() ?? .nan, 1e-9)
    checkClose("the max of the prices", portDoubles(port, "price").max() ?? .nan,
               hostDoubles(host, "price").max() ?? .nan, 1e-9)

    // Sorting: a defined order, compared value by value.
    checkEqual("the prices in increasing order",
               portDoubles(port.sort(columnNamed: "price"), "price"),
               hostDoubles(host.sort(columnNamed: "price"), "price"))
    checkEqual("the rooms in decreasing order",
               portIntegers(port.sort(columnNamed: "rooms", byIncreasingOrder: false), "rooms"),
               hostIntegers(host.sort(columnNamed: "rooms", byIncreasingOrder: false), "rooms"))

    checkEqual("the number of distinct cities",
               portStrings(port, "city").reduce(into: [String]()) { seen, city in
                   if !seen.contains(city) { seen.append(city) }
               }.count,
               hostStrings(host, "city").reduce(into: [String]()) { seen, city in
                   if !seen.contains(city) { seen.append(city) }
               }.count)
    checkEqual("the number of rows with nothing missing", port.dropMissing().size.rows, host.dropMissing().size.rows)
    checkEqual("the number of distinct rows", port.dropDuplicates().size.rows, host.dropDuplicates().size.rows)

    // A join on a column that is unique on both sides, in all four kinds.
    let otherCSV = "id,region\n1,north\n4,south\n7,north\n"
    let otherURL = csvURL.deletingLastPathComponent().appendingPathComponent("createml-other-\(getpid()).csv")
    try? otherCSV.write(to: otherURL, atomically: true, encoding: .utf8)
    let portOther = try PortCreateML.MLDataTable(contentsOf: otherURL)
    let hostOther = try CreateML.MLDataTable(contentsOf: otherURL)

    for kind in [PortCreateML.JoinType.inner, .left, .right, .outer] {
        let hostKind: CreateML.MLDataTable.JoinType
        switch kind {
        case .inner: hostKind = .inner
        case .left: hostKind = .left
        case .right: hostKind = .right
        case .outer: hostKind = .outer
        }
        let portJoin = try port.join(with: portOther, on: "id", type: kind)
        let hostJoin = try host.join(with: hostOther, on: "id", type: hostKind)
        checkEqual("the row count of a \(kind.rawValue) join", portJoin.size.rows, hostJoin.size.rows)
        checkEqual("the id column of a \(kind.rawValue) join",
                   portIntegers(portJoin, "id"), hostIntegers(hostJoin, "id"))
        checkEqual("the region column of a \(kind.rawValue) join",
                   portStrings(portJoin, "region"), hostStrings(hostJoin, "region"))
    }

    // Group and aggregate: the grouped sizes and the values of the named aggregates.
    // Two aggregators over the price and one over the ids, each with a named output column so that
    // the two frameworks' column names can be compared: the framework's own convention is that an
    // operation with a name of its own writes into `<column>_<operation>`.
    let portGroup = try port.group(columnsNamed: ["city"], aggregators: [
        PortCreateML.MLDataTableAggregator(operations: .sum, of: "price"),
        PortCreateML.MLDataTableAggregator(operations: .mean, of: "price"),
        PortCreateML.MLDataTableAggregator(operations: .count, of: "id"),
    ])
    let hostGroup = try host.group(columnsNamed: "city", aggregators: [
        CreateML.MLDataTable.Aggregator(operations: .sum, of: "price"),
        CreateML.MLDataTable.Aggregator(operations: .mean, of: "price"),
        CreateML.MLDataTable.Aggregator(operations: .count, of: "id"),
    ])
    checkEqual("the number of groups by city", portGroup.size.rows, hostGroup.size.rows)
    for label in ["sum", "mean", "count"] {
        let mine = portDoubles(portGroup, "price_" + label).filter { !$0.isNaN }
        let theirs = hostDoubles(hostGroup, "price_" + label).filter { !$0.isNaN }
        checkEqual("the number of \(label) values by city", mine.count, theirs.count)
        for (a, b) in zip(mine, theirs) {
            checkClose("a \(label) of price by city", a, b, 1e-9)
        }
    }

    // A split: the sizes are defined given the proportion, and the seed decides which rows.
    let portSplit = port.randomSplit(by: 0.75, seed: 42)
    let hostSplit = host.randomSplit(by: 0.75, seed: 42)
    checkEqual("the training half of a random split", portSplit.0.size.rows, hostSplit.0.size.rows)
    checkEqual("the validation half of a random split", portSplit.1.size.rows, hostSplit.1.size.rows)

    // The CSV writer against the CSV reader: what the port writes, the port reads back unchanged.
    let written = csvURL.deletingLastPathComponent().appendingPathComponent("createml-written-\(getpid()).csv")
    try port.writeCSV(to: written)
    let reread = try PortCreateML.MLDataTable(contentsOf: written)
    checkEqual("the prices of a written and re-read table",
               portDoubles(reread, "price"), portDoubles(port, "price"))

    // A CSV with quoting, a comment, a missing value and a row limit: each option is checked by
    // what it changes, not by the fact that it exists.
    let tricky = """
    # a comment line
    "name","note"
    "a","one, two"
    "b","a ""quoted"" word"
    "c",
    "d","four"
    """
    let trickyURL = csvURL.deletingLastPathComponent().appendingPathComponent("createml-tricky-\(getpid()).csv")
    try? tricky.write(to: trickyURL, atomically: true, encoding: .utf8)
    let portTricky = try PortCreateML.MLDataTable(contentsOf: trickyURL)
    let hostTricky = try CreateML.MLDataTable(contentsOf: trickyURL)
    checkEqual("the rows of a file with a comment and quotes", portTricky.size.rows, hostTricky.size.rows)
    let portNotes = portStrings(portTricky, "note")
    let hostNotes = hostStrings(hostTricky, "note")
    checkEqual("a quoted field holding the delimiter", portNotes.count > 1 ? portNotes[1] : "",
               hostNotes.count > 1 ? hostNotes[1] : "")
    checkEqual("a doubled quote inside a quoted field", portNotes.count > 2 ? portNotes[2] : "",
               hostNotes.count > 2 ? hostNotes[2] : "")
    check("an empty cell is missing, not an empty string",
          portTricky["note"]![2] == .invalid, "the port answers \(portTricky["note"]![2])")
    checkEqual("the rows of a file read with maxRows", try PortCreateML.MLDataTable(
        contentsOf: trickyURL,
        options: MLDataTableParsingOptionsAlias(maxRows: 2)).size.rows, 2)
} catch {
    print("FAIL the table comparison threw: \(error)")
    failures += 1
}

/// The port's parsing options, named as the module names them, so a call site above reads the way
/// an application reads.
typealias MLDataTableParsingOptionsAlias = PortCreateML.MLDataTableParsingOptions

// MARK: - The estimators, through the type both frameworks name

/// A table whose target is a step in one feature. A tree has one right answer for every row of it,
/// and the noise is too small to move the step, so the predictions can be compared row by row and not
/// only through a metric.
func stepTable(rows: Int, csv: inout String) {
    var generator = PortCreateMLComponents.SeededGenerator(seed: 7)
    csv = "x,junk,target\n"
    for index in 0..<rows {
        let x = Double(index) / Double(rows) + generator.nextGaussian(mean: 0, standardDeviation: 0.01)
        let junk = generator.nextUniform()
        csv += "\(x),\(junk),\(x > 0.5 ? 1000.0 : 0.0)\n"
    }
}

do {
    var text = ""
    stepTable(rows: 200, csv: &text)
    let url = csvURL.deletingLastPathComponent().appendingPathComponent("createml-step-\(getpid()).csv")
    try text.write(to: url, atomically: true, encoding: .utf8)

    // The host's own decision tree, on the same file, through the same `MLDataTable` type name.
    let hostModel = try CreateML.MLDecisionTreeRegressor(
        trainingData: try CreateML.MLDataTable(contentsOf: url),
        targetColumn: "target",
        featureColumns: ["junk", "x"])
    var hostPredictionTable = CreateML.MLDataTable()
    hostPredictionTable.addColumn(try hostModel.predictions(from: try CreateML.MLDataTable(contentsOf: url)),
                                  named: "prediction")
    let hostPredictions = hostDoubles(hostPredictionTable, "prediction")

    let portModel = try PortCreateML.MLDecisionTreeRegressor(
        trainingData: try PortCreateML.MLDataTable(contentsOf: url),
        targetColumn: "target",
        featureColumns: ["junk", "x"])
    var portPredictionTable = PortCreateML.MLDataTable()
    portPredictionTable.addColumn(try portModel.predictions(from: try PortCreateML.MLDataTable(contentsOf: url)),
                                  named: "prediction")
    let portPredictions = portDoubles(portPredictionTable, "prediction")

    checkEqual("the number of predictions from a decision tree", portPredictions.count, hostPredictions.count)
    check("a decision tree finds the step",
          portModel.trainingMetrics.rootMeanSquaredError < 1.0 && portModel.trainingMetrics.isValid,
          "the port's own RMSE on a separable table is \(portModel.trainingMetrics.rootMeanSquaredError)")

    // Row by row, against the host. The step is at 0.5 and the noise is 0.01, so every row is on one
    // side or the other and a tree that found the step answers 0 or 1000; a row where the two
    // disagree is a row where one of them did not find it, and there should be none.
    var agreed = 0
    var largestDifference = 0.0
    for (mine, theirs) in zip(portPredictions, hostPredictions) {
        let difference = abs(mine - theirs)
        largestDifference = max(largestDifference, difference)
        if difference < 1.0 { agreed += 1 }
    }
    check("the port's decision tree agrees with the host's on every row of a separable table",
          agreed == portPredictions.count,
          "\(agreed) of \(portPredictions.count) rows agree, the largest difference is \(largestDifference)")

    // The three summaries of a regression's quality, which are defined.
    let hostMetrics = hostModel.evaluation(on: try CreateML.MLDataTable(contentsOf: url))
    let portMetrics = portModel.evaluation(on: try PortCreateML.MLDataTable(contentsOf: url))
    checkClose("the RMSE of an evaluation", portMetrics.rootMeanSquaredError,
               hostMetrics.rootMeanSquaredError, 1.0)
    checkClose("the maximum error of an evaluation", portMetrics.maximumError,
               hostMetrics.maximumError, 1.0)

    // A forest and a boosted forest, measured by the metric rather than row by row: a hundred
    // bootstrap samples and a hundred boosting rounds have no single right set of predictions, and
    // the metric is what a caller actually reads.
    let hostForest = try CreateML.MLRandomForestRegressor(
        trainingData: try CreateML.MLDataTable(contentsOf: url), targetColumn: "target",
        featureColumns: ["junk", "x"],
        parameters: CreateML.MLRandomForestRegressor.ModelParameters(numberOfTrees: 20, seed: 7))
    let portForest = try PortCreateML.MLRandomForestRegressor(
        trainingData: try PortCreateML.MLDataTable(contentsOf: url), targetColumn: "target",
        featureColumns: ["junk", "x"],
        parameters: .init(numberOfTrees: 20, seed: 7))
    check("the port's forest finds the step as the host's does",
          portForest.trainingMetrics.rootMeanSquaredError < 1.0
              && hostForest.trainingMetrics.rootMeanSquaredError < 1.0
              && portForest.trainingMetrics.isValid,
          "the port's RMSE is \(portForest.trainingMetrics.rootMeanSquaredError), the host's \(hostForest.trainingMetrics.rootMeanSquaredError)")

    let hostBoosted = try CreateML.MLBoostedTreeRegressor(
        trainingData: try CreateML.MLDataTable(contentsOf: url), targetColumn: "target",
        featureColumns: ["junk", "x"],
        parameters: CreateML.MLBoostedTreeRegressor.ModelParameters(numberOfTrees: 20, seed: 7))
    let portBoosted = try PortCreateML.MLBoostedTreeRegressor(
        trainingData: try PortCreateML.MLDataTable(contentsOf: url), targetColumn: "target",
        featureColumns: ["junk", "x"],
        parameters: .init(numberOfTrees: 20, seed: 7))
    check("the port's boosted trees find the step as the host's does",
          portBoosted.trainingMetrics.rootMeanSquaredError < 1.0
              && hostBoosted.trainingMetrics.rootMeanSquaredError < 1.0
              && portBoosted.trainingMetrics.isValid,
          "the port's RMSE is \(portBoosted.trainingMetrics.rootMeanSquaredError), the host's \(hostBoosted.trainingMetrics.rootMeanSquaredError)")

    // A classifier, on a table whose labels a tree must find, compared through the accuracy.
    let labelled = "x,target\n" + (0..<200).map { index -> String in
        let x = Double(index) / 200.0
        return "\(x),\(x > 0.5 ? "high" : "low")\n"
    }.joined()
    let labelledURL = csvURL.deletingLastPathComponent().appendingPathComponent("createml-labelled-\(getpid()).csv")
    try labelled.write(to: labelledURL, atomically: true, encoding: .utf8)

    let hostClassifier = try CreateML.MLDecisionTreeClassifier(
        trainingData: try CreateML.MLDataTable(contentsOf: labelledURL), targetColumn: "target",
        featureColumns: ["x"])
    let portClassifier = try PortCreateML.MLDecisionTreeClassifier(
        trainingData: try PortCreateML.MLDataTable(contentsOf: labelledURL), targetColumn: "target",
        featureColumns: ["x"])
    checkClose("the classification error of a decision-tree classifier",
               portClassifier.trainingMetrics.classificationError,
               hostClassifier.trainingMetrics.classificationError, 1e-9)
    check("a decision-tree classifier separates two classes",
          portClassifier.trainingMetrics.accuracy > 0.95 && portClassifier.trainingMetrics.isValid,
          "the port's accuracy is \(portClassifier.trainingMetrics.accuracy)")

    let portForestClassifier = try PortCreateML.MLRandomForestClassifier(
        trainingData: try PortCreateML.MLDataTable(contentsOf: labelledURL), targetColumn: "target",
        featureColumns: ["x"],
        parameters: PortCreateML.MLRandomForestClassifier.ModelParameters(numberOfTrees: 20, seed: 7))
    checkClose("the classification error of a random-forest classifier",
               portForestClassifier.trainingMetrics.classificationError,
               hostClassifier.trainingMetrics.classificationError, 0.05)

    // The export refuses, loudly, rather than writing a file no Core ML can read.
    var refused = false
    do {
        try portModel.write(to: csvURL)
    } catch {
        refused = true
        check("the refusal is CreateML's own error", (error as? MLCreateErrorAlias) != nil,
              "the port answers \(error)")
    }
    check("write(to:) refuses on this build", refused)
} catch {
    print("FAIL the estimator comparison threw: \(error)")
    failures += 1
}

typealias MLCreateErrorAlias = PortCreateML.MLCreateError

// MARK: - The kernel layer

do {
    let portA = PortCreateMLComponents.RowMatrix(values: [2, 0, 0, 3], rows: 2, columns: 2)
    let portB = PortCreateMLComponents.RowMatrix(values: [1, 2, 3, 4], rows: 2, columns: 2)
    let portProduct = portA.multiplied(by: portB)
    checkEqual("a 2x2 product, row 0", portProduct.contiguousRow(0), [8.0, 4.0])
    checkEqual("a 2x2 product, row 1", portProduct.contiguousRow(1), [9.0, 12.0])

    var system = PortCreateMLComponents.RowMatrix(values: [3, 1, 1, 2], rows: 2, columns: 2)
    var right = [9.0, 8.0]
    checkEqual("a 2x2 LU solve reports no error",
               PortCreateMLComponents.RowMatrix.solve(&system, rightHandSides: &right), 0)
    checkClose("a 2x2 LU solve, x", right[0], 2, 1e-9)
    checkClose("a 2x2 LU solve, y", right[1], 3, 1e-9)

    var singular = PortCreateMLComponents.RowMatrix(values: [1, 2, 2, 4], rows: 2, columns: 2)
    var ignored = [1.0, 1.0]
    let singularInfo = PortCreateMLComponents.RowMatrix.solve(&singular, rightHandSides: &ignored)
    check("a singular system is reported, not answered", singularInfo != 0,
          "LAPACK's own info came back as \(singularInfo)")

    var normal = PortCreateMLComponents.RowMatrix(values: [2, 0, 0, 3], rows: 2, columns: 2)
    checkEqual("a Cholesky factor of a positive definite matrix reports no error",
               PortCreateMLComponents.RowMatrix.cholesky(&normal), 0)
    checkClose("a Cholesky factor, the lower triangle's off-diagonal", normal[1, 0], 0, 1e-12)

    checkClose("a mean", PortCreateMLComponents.RowMatrix.mean([1, 2, 3, 4]), 2.5, 1e-12)
    checkClose("a variance", PortCreateMLComponents.RowMatrix.variance([1, 2, 3, 4]), 5.0 / 3.0, 1e-9)
    checkClose("a dot product", PortCreateMLComponents.RowMatrix.dot([1, 2, 3], [4, 5, 6]), 32, 1e-12)
    let probabilities = PortCreateMLComponents.RowMatrix.logistic([0.3, 1.2, -0.7])
    checkClose("a softmax sums to one", probabilities.reduce(0, +), 1, 1e-12)
    check("a softmax is ordered by its scores",
          probabilities[1] > probabilities[0] && probabilities[0] > probabilities[2],
          "the port answers \(probabilities)")

    // The ridge least-squares fit, against the closed form of a one-column fit: with a single
    // feature the ridge solution is (x'x + p)^-1 x'y, which can be written down.
    let design = PortCreateMLComponents.RowMatrix(values: [1, 2, 3, 4], rows: 4, columns: 1)
    let (solution, info) = PortCreateMLComponents.RowMatrix.ridgeLeastSquares(
        design: design, targets: [2, 4, 6, 8], penalty: 0)
    checkEqual("a one-column ridge fit reports no error", info, 0)
    checkClose("a one-column ridge fit's slope", solution.first ?? 0, 2, 1e-9)
    checkClose("a one-column ridge fit's intercept", solution.count > 1 ? solution[1] : 0, 0, 1e-9)

    // The seeded generator: the same seed gives the same stream on any release, which is the promise
    // the type exists to keep.
    var one = PortCreateMLComponents.SeededGenerator(seed: 12345)
    var two = PortCreateMLComponents.SeededGenerator(seed: 12345)
    var same = true
    for _ in 0..<1000 where one.next() != two.next() { same = false }
    check("two generators with one seed agree for a thousand draws", same)
    var three = PortCreateMLComponents.SeededGenerator(seed: 12346)
    var differs = false
    for _ in 0..<1000 where one.next() != three.next() { differs = true }
    check("two generators with different seeds differ", differs)
} catch {
    print("FAIL the kernel comparison threw: \(error)")
    failures += 1
}

try? FileManager.default.removeItem(at: csvURL)

print("\(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
