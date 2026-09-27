// transformers.swift — the port's feature transformers, against the arithmetic they are named for.
//
// Not a host differential, for the reason `linearmodels/main.swift` gives: the port's
// `CreateMLComponents` is a module of its own and the host's estimators are declared against a
// `DataFrame` and a shaped array spelled differently, and bridging that is its own work. What is
// checked here is that each transformer does the arithmetic its name says, on data whose answer is
// known by hand, and that the three things they must refuse — a category the fit never saw, a
// constant column, a column with nothing in it — are refused rather than papered over.
import Foundation
import PortCreateMLComponents

var checks = 0
var failures = 0

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
        print("FAIL \(what): the port answers \(a), the arithmetic says \(b), a difference of \(difference)")
    }
}

func checkEqual<T: Equatable>(_ what: String, _ a: T, _ b: T) {
    check(what, a == b, "the port answers \(a)")
}

func table(_ numeric: [(String, [Double?])], textual: [(String, [String])] = []) -> ColumnarTable {
    var built = ColumnarTable()
    for (name, values) in numeric { built.set(.doubles(values), named: name) }
    for (name, values) in textual { built.set(.strings(values.map { Optional($0) }), named: name) }
    return built
}

func column(_ table: ColumnarTable, _ name: String) -> [Double?] {
    table.column(name)?.numeric ?? []
}

do {
    // 1, 2, 3, 4: mean 2.5, unbiased standard deviation sqrt(5/3) = 1.29099, min 1, max 4.
    let numbers = table([("x", [1, 2, 3, 4]), ("y", [10, 20, 30, 40])])

    // The standard scaler.
    let standard = try StandardScaler().fitted(on: numbers)
    let standardX = column(standard.transformed(numbers), "x")
    let spread = (5.0 / 3.0).squareRoot()
    checkClose("a standard scaler puts the mean at zero",
               (standardX[0]! + standardX[1]! + standardX[2]! + standardX[3]!) / 4, 0, 1e-12)
    // Three units of the original column are (3 / spread) apart after standardising, and the
    // standardised values are (3 / spread) apart for the same reason.
    checkClose("a standard scaler divides by the unbiased standard deviation",
               (standardX[3]! - standardX[0]!) / 3, 1 / spread, 1e-12)

    // The min-max scaler, into the default 0...1.
    let minmax = try MinMaxScaler().fitted(on: numbers)
    let minmaxX = column(minmax.transformed(numbers), "x")
    checkClose("a min-max scaler puts the smallest value at the range's start", minmaxX[0]!, 0, 1e-12)
    checkClose("a min-max scaler puts the largest value at the range's end", minmaxX[3]!, 1, 1e-12)
    checkClose("a min-max scaler is linear in between", minmaxX[1]!, 1.0 / 3.0, 1e-12)
    let narrowed = try MinMaxScaler(range: -1...1).fitted(keepingRangeOn: numbers)
    let narrowedX = column(narrowed.transformed(numbers), "x")
    checkClose("a min-max scaler into another range", narrowedX[0]!, -1, 1e-12)
    checkClose("a min-max scaler into another range, at the end", narrowedX[3]!, 1, 1e-12)

    // The max-abs scaler: the largest magnitude is 40 in `y` and 4 in `x`.
    let maxabs = try MaxAbsScaler().fitted(on: numbers)
    let maxabsY = column(maxabs.transformed(numbers), "y")
    checkClose("a max-abs scaler divides by the largest magnitude", maxabsY[3]!, 1, 1e-12)
    checkClose("a max-abs scaler keeps the sign", maxabsY[0]!, 0.25, 1e-12)

    // The robust scaler, on data one extreme value cannot move.
    // 1, 2, 3, 4, 100: the median is 3 and the median absolute deviation is 1, so the scale is
    // 1.4826 and the column is centred on 3 — while a standard scaler's mean is 22 and its
    // standard deviation 43.9, which is the whole difference between the two.
    let skewed = table([("x", [1, 2, 3, 4, 100])])
    let robust = try RobustScaler().fitted(on: skewed)
    let robustX = column(robust.transformed(skewed), "x")
    let standardSkewed = try StandardScaler().fitted(on: skewed)
    let standardSkewedX = column(standardSkewed.transformed(skewed), "x")
    checkClose("a robust scaler centres on the median", robustX[2]!, 0, 1e-12)
    // The comparison is the spread the *ordinary* values get: a robust scaler keeps them apart and
    // lets the extreme one be an outlier, while a standard scaler's mean and deviation are dragged
    // by it and the whole column compresses.
    let robustSpread = abs(robustX[1]! - robustX[0]!)
    let standardSpread = abs(standardSkewedX[1]! - standardSkewedX[0]!)
    check("a robust scaler keeps the ordinary values apart where a standard one does not",
          robustSpread > 2 * standardSpread,
          "the robust spread is " + String(robustSpread) + " and the standard one is "
          + String(standardSpread))
    checkEqual("the median of an even count is the mean of the two middle values",
               RobustScaler.median([1, 2, 3, 4]), 2.5)
    checkEqual("the median of an odd count is the middle value", RobustScaler.median([3, 1, 2]), 2)

    // A constant column: no spread to divide by, and it must be passed through rather than turned
    // into a NaN that would poison every coefficient fitted after it.
    let constant = table([("x", [7, 7, 7, 7]), ("y", [1, 2, 3, 4])])
    let constantStandard = column(try StandardScaler().fitted(on: constant).transformed(constant), "x")
    checkEqual("a constant column is centred on zero, not divided by a zero",
               constantStandard, [0, 0, 0, 0])
    let constantMinmax = column(try MinMaxScaler().fitted(on: constant).transformed(constant), "x")
    check("a constant column has no spread for a min-max scaler to divide by",
          constantMinmax == [0, 0, 0, 0] || constantMinmax == [7, 7, 7, 7],
          "the port answers \(constantMinmax)")
    let constantMaxabs = column(try MaxAbsScaler().fitted(on: constant).transformed(constant), "x")
    checkEqual("a constant column is scaled to the unit magnitude by the max-abs scaler",
               constantMaxabs, [1, 1, 1, 1])

    // The one-hot encoder: one column per category, and a category the fit never saw is an all-zero
    // row rather than a new column.
    let categories = table([("x", [1.0, 2.0, 3.0, 4.0])],
                          textual: [("city", ["berlin", "paris", "berlin", "madrid"])])
    let oneHot = try OneHotEncoder().fitted(on: categories)
    checkEqual("a one-hot encoder's categories, in the order the fit found them",
               oneHot.categories(of: "city"), ["berlin", "paris", "madrid"])
    let hot = oneHot.transformed(categories)
    checkEqual("a one-hot encoder makes one column per category", hot.columnNames, ["x", "city_berlin", "city_paris", "city_madrid"])
    checkEqual("a one-hot encoder sets the column of its own category",
               column(hot, "city_berlin"), [1, 0, 1, 0])
    checkEqual("a one-hot encoder leaves the others at zero",
               column(hot, "city_madrid"), [0, 0, 0, 1])
    let unseen = table([("x", [1.0, 2.0, 3.0, 4.0])],
                       textual: [("city", ["berlin", "paris", "berlin", "lyon"])])
    let unseenHot = oneHot.transformed(unseen)
    checkEqual("a category the fit never saw is an all-zero row, not a new column",
               column(unseenHot, "city_berlin"), [1, 0, 1, 0])
    checkEqual("and no column is added for it", unseenHot.columnNames.count, hot.columnNames.count)

    // The ordinal encoder: the category's rank, and an unseen category is **missing** rather than
    // the first rank — a rank of zero would put an unseen value in the first class.
    let ordinal = try OrdinalEncoder().fitted(on: categories)
    checkEqual("an ordinal encoder's order, as the fit found it",
               ordinal.order(of: "city"), ["berlin", "paris", "madrid"])
    let ranked = column(ordinal.transformed(categories), "city")
    checkEqual("an ordinal encoder writes the rank", ranked, [0, 1, 0, 2])
    let unseenRanked = column(ordinal.transformed(unseen), "city")
    checkEqual("an unseen category is missing, not the first rank",
               unseenRanked, [0, 1, 0, nil])
    check("and the missing one is missing, not a zero",
          unseenRanked[3] == nil, "the port answers \(String(describing: unseenRanked[3]))")

    // The imputer: the mean of the values that are there, and a column with nothing in it is filled
    // with zero *and named* on `imputedEverything`, because there is no mean of no values.
    let holed = table([("x", [1, nil, 3, 4])])
    let imputer = try NumericImputer().fitted(on: holed)
    checkClose("an imputer fills with the mean of the values that are there",
               imputer.value(of: "x")!, (1 + 3 + 4) / 3, 1e-12)
    // The gap is filled and the values that were there are left alone — an imputer that wrote its
    // value over a good cell would be destroying data, not filling gaps.
    checkEqual("an imputer fills the gap and leaves the values that were there",
               column(imputer.transformed(holed), "x"), [1, (1 + 3 + 4) / 3, 3, 4])
    let nothing = table([("x", [nil, nil, nil])])
    let nothingImputer = try NumericImputer().fitted(on: nothing)
    checkEqual("a column with nothing in it is named as such", nothingImputer.imputedEverything, ["x"])
    checkEqual("and is filled with zero", column(nothingImputer.transformed(nothing), "x"), [0, 0, 0])
    // The mean is over the three values that are there and not the four with the gap read as a
    // zero: 8/3 = 2.667 against 2 for the other reading, and the difference is a quarter.
    checkClose("a gap is not counted as a zero in the mean", imputer.value(of: "x")!, 8.0 / 3.0, 1e-12)

    // The linear transformer: `y = scale*x + offset`, the scale and offset kept so a prediction can
    // be reported in the column's own units.
    let linear = try LinearTransformer().fitted(on: numbers)
    let linearX = column(linear.transformed(numbers), "x")
    check("a linear transformer standardises what the standard scaler standardises",
          abs((linearX[0]! - standardX[0]!)) < 1e-12,
          "the linear one answers \\(linearX[0]!), the standard one \\(standardX[0]!)")
    checkClose("and its scale is the inverse of the spread", linear.scale(of: "x")!, 1 / spread, 1e-12)
    checkClose("and its offset is the negative mean over the spread",
               linear.offset(of: "x")!, -2.5 / spread, 1e-12)
    let linearHoled = column(try LinearTransformer().fitted(on: holed).transformed(holed), "x")
    check("a linear transformer leaves a missing value missing", linearHoled[1] == nil,
          "the port answers \(String(describing: linearHoled[1]))")
} catch {
    print("FAIL the transformer comparison threw: \(error)")
    failures += 1
}

print("\(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
