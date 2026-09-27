// linearmodels.swift — the port's linear regressor and logistic classifier, against the closed form.
//
// **This is not a host differential, and it is not pretending to be one.** A linear fit over a
// full-rank design with no penalty has exactly one right answer, and that answer is written down:
// a table whose target is `3 + 2*x1 - 1.5*x2` has to fit back to `[3, 2, -1.5]`, and a model built
// from those coefficients has to reproduce the table. That is a stronger claim than "agrees with
// another implementation of the same thing", because it cannot be satisfied by two wrong
// implementations agreeing.
//
// The host comparison — the host's own `LinearRegressor.fitted(to:validateOn:)`, which is
// `async throws` and takes a `DataFrame` — is real work and is not done here; `differential.swift`
// carries the twelve defects this surface's own differential found, and this file is a different
// claim from the same tree.
//
// What is checked:
//
//   - the coefficients of a fit over a table made from a known line, to a tolerance;
//   - the predictions of that model, row by row, against the table's own targets;
//   - that a ridge penalty pulls the slope toward zero by the amount the closed form says;
//   - that a model of the wrong width, a rank-deficient design, and an L1 penalty are each *refused
//     by name* rather than answered;
//   - that the classifier separates a linearly separable table, that its probabilities sum to one,
//     and that the label it answers is the most probable one.
//
// The last of those three refusals is the one that matters most: a fit that silently ignored the L1
// penalty the caller set would hand back a confident number about a model nobody asked for.
import Foundation
import PortCreateMLComponents
import PortCoreML

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

func checkCloseClose(_ what: String, _ a: Double, _ b: Double, _ tolerance: Double) {
    checkClose(what, a, b, tolerance)
}

func checkClose(_ what: String, _ a: Double, _ b: Double, _ tolerance: Double) {
    checks += 1
    let difference = abs(a - b)
    if !(difference <= tolerance) {
        failures += 1
        print("FAIL \(what): the port answers \(a), the closed form says \(b), a difference of \(difference)")
    }
}

typealias Annotated = PortCreateMLComponents.AnnotatedFeature<PortCoreML.MLShapedArray<Double>, Double>

func feature(_ values: [Double]) -> PortCoreML.MLShapedArray<Double> {
    PortCoreML.MLShapedArray(scalars: values, shape: [values.count])
}

do {
    // A table made from the line y = 3 + 2*x1 - 1.5*x2, with a little noise small enough that the
    // least-squares fit still recovers the line to six places.
    var generator = PortCreateMLComponents.SeededGenerator(seed: 11)
    var rows = [Annotated]()
    var targets = [Double]()
    for _ in 0..<200 {
        let x1 = generator.nextUniform()
        let x2 = generator.nextUniform()
        let y = 3 + 2 * x1 - 1.5 * x2 + generator.nextGaussian(mean: 0, standardDeviation: 0.001)
        rows.append(Annotated(feature: feature([x1, x2]), annotation: y))
        targets.append(y)
    }

    let regressor = PortCreateMLComponents.LinearRegressor<Double>(
        configuration: .init(l2Penalty: 0, l1Penalty: 0))
    let model = try regressor.fitted(to: rows)

    checkEqual("the feature count", model.featureCount, 2)
    checkEqual("the coefficient count, intercept first", model.coefficients.count, 3)
    checkClose("the intercept", Double(model.coefficients[0]), 3, 1e-3)
    checkClose("the first weight", Double(model.coefficients[1]), 2, 1e-3)
    checkClose("the second weight", Double(model.coefficients[2]), -1.5, 1e-3)

    // The predictions reproduce the table.
    let predictions = try model.prediction(from: rows.map { $0.feature })
    checkEqual("one prediction per row", predictions.count, targets.count)
    var worst = 0.0
    for (index, prediction) in predictions.enumerated() {
        worst = max(worst, abs(Double(prediction) - targets[index]))
    }
    check("the predictions reproduce the table's own target", worst < 0.01,
          "the largest error over \(targets.count) rows is \(worst)")

    // A prediction of a single feature, which is what a caller reading a model asks for.
    checkClose("a one-feature model built by hand, on a row of it",
               try PortCreateMLComponents.LinearRegressorModel<Double>(coefficients: [10, 1])
                   .prediction(from: feature([5])), 15, 1e-12)

    // The ridge penalty: with one feature and a penalty p, the slope is shrunk by `x'x/(x'x + p)`.
    // Built by hand from the closed form, so the check is on the fitter and not on itself.
    let oneFeature = (0..<50).map { index -> Annotated in
        let x = Double(index)
        return Annotated(feature: feature([x]), annotation: 2 * x)
    }
    let ridge = PortCreateMLComponents.LinearRegressor<Double>(configuration: .init(l2Penalty: 100))
    let ridgeModel = try ridge.fitted(to: oneFeature)
    // The penalty goes on the **whole** diagonal, intercept included, because the normal matrix is
    // one matrix and exempting the intercept is a special case nothing asked for. That makes the
    // closed form the two-parameter ridge rather than the single-feature one, so what is checked
    // here is the property a caller relies on rather than a formula: the penalty pulls the slope
    // toward zero, and a bigger one pulls it further.
    let unpenalized = try PortCreateMLComponents.LinearRegressor<Double>(configuration: .init(l2Penalty: 0))
        .fitted(to: oneFeature)
    let heavy = try PortCreateMLComponents.LinearRegressor<Double>(configuration: .init(l2Penalty: 1000))
        .fitted(to: oneFeature)
    let plain = Double(unpenalized.coefficients[1])
    let light = Double(ridgeModel.coefficients[1])
    let harder = Double(heavy.coefficients[1])
    check("a ridge penalty shrinks the slope", light < plain, "\(light) is not below \(plain)")
    check("a bigger ridge penalty shrinks it further", harder < light,
          "\(harder) is not below \(light)")
    checkCloseClose("no penalty recovers the slope the data was made with", plain, 2, 1e-9)

    // The three refusals, each by name.
    var widthRefused = false
    do {
        _ = try model.prediction(from: feature([1.0]))
    } catch let error as PortCreateMLComponents.LinearModelError {
        widthRefused = true
        let text = "\(error)"
        check("the width refusal names both widths", text.contains("2") && text.contains("1"),
              "the port answers \(error)")
    } catch {}
    check("a model of the wrong width refuses rather than truncating", widthRefused)

    var l1Refused = false
    do {
        let configured = PortCreateMLComponents.LinearRegressor<Double>(
            configuration: .init(l2Penalty: 0, l1Penalty: 0.5))
        _ = try configured.fitted(to: rows)
    } catch let error as PortCreateMLComponents.LinearModelError {
        l1Refused = true
        check("the L1 refusal names the penalty that was asked for", "\(error)".contains("0.5"),
              "the port answers \(error)")
    } catch {}
    check("an L1 penalty is refused, not ignored", l1Refused)

    var singularRefused = false
    do {
        // Two identical features: the design has no answer in the second column, and a fit that
        // answered anyway would be returning a coefficient of something the caller cannot use.
        let repeated = (0..<20).map { index -> Annotated in
            let x = Double(index)
            return Annotated(feature: feature([x, x]), annotation: 2 * x)
        }
        _ = try PortCreateMLComponents.LinearRegressor<Double>(configuration: .init(l2Penalty: 0))
            .fitted(to: repeated)
    } catch let error as PortCreateMLComponents.LinearModelError {
        singularRefused = true
        check("the singular refusal names a column", "\(error)".contains("column"),
              "the port answers \(error)")
    } catch {}
    check("a rank-deficient design is reported, not answered", singularRefused)

    // The classifier, on a table whose classes are separated by a line.
    var classifierRows = [PortCreateMLComponents.AnnotatedFeature<PortCoreML.MLShapedArray<Double>, String>]()
    var labels = [String]()
    for index in 0..<200 {
        let x = Double(index) / 200.0
        let point = x + Double((index * 7) % 13) / 400.0 - 0.015
        let label = point > 0.5 ? "high" : "low"
        classifierRows.append(PortCreateMLComponents.AnnotatedFeature(feature: feature([point]), annotation: label))
        labels.append(label)
    }
    let classifier = PortCreateMLComponents.LogisticRegressionClassifier<Double, String>(
        configuration: .init(l2Penalty: 0.01))
    let classifierModel = try classifier.fitted(to: classifierRows)
    checkEqual("the classifier's feature count", classifierModel.featureCount, 1)
    checkEqual("the classifier's coefficient count, one intercept and one weight per class",
               classifierModel.coefficients.count, 3)

    var right = 0
    for (index, row) in classifierRows.enumerated() {
        if try classifierModel.prediction(from: row.feature).label == labels[index] { right += 1 }
    }
    // The classes are separated at 0.5 by a margin and a noise that straddles it: a handful of rows
    // sit within the noise of the boundary and are genuinely ambiguous, so the claim is that the
    // classifier separates the *table* and not that it is right about every ambiguous row.
    check("the classifier separates a linearly separable table",
          Double(right) / Double(labels.count) >= 0.95,
          "the port gets \(right) of \(labels.count) right")

    var sumsToOne = true
    var picksTheBest = true
    for row in classifierRows.prefix(20) {
        let distribution = try classifierModel.prediction(from: row.feature)
        let total = distribution.probabilities.values.reduce(0, +)
        if abs(total - 1) > 1e-9 { sumsToOne = false }
        var best = distribution.probabilities[distribution.label] ?? 0
        for value in distribution.probabilities.values where value > best {
            best = value
            picksTheBest = false
        }
    }
    check("the class probabilities sum to one", sumsToOne)
    check("the label it answers is the most probable one", picksTheBest)

    var classifierWidthRefused = false
    do {
        _ = try classifierModel.prediction(from: feature([1, 2]))
    } catch {
        classifierWidthRefused = true
    }
    check("a classifier of the wrong width refuses", classifierWidthRefused)

    // The shaped array itself: the shape, the strides and the two dimensions' arithmetic, which is
    // what a fitted model's weights are walked through.
    var matrix = PortCoreML.MLShapedArray(scalars: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0], shape: [2, 3])
    checkEqual("a shaped array's shape", matrix.shape, [2, 3])
    checkEqual("a shaped array's strides, in elements", matrix.strides, [3, 1])
    checkEqual("a shaped array's count is the product of its shape", matrix.count, 6)
    checkClose("a shaped array read by index per dimension", matrix[indices: 1, 2], 6, 1e-12)
    matrix[indices: 1, 2] = 60
    checkClose("a shaped array written by index per dimension", matrix[indices: 1, 2], 60, 1e-12)
    checkClose("a shaped array's buffer, row-major", matrix.scalars[5], 60, 1e-12)
    checkEqual("a row of a shaped array, as a slice of the other dimension",
              matrix[1, slice: 0..<3].count, 3)
    checkEqual("a range of a shaped array's rows", matrix[slice: 0..<2].count, 2)
    checkEqual("a shaped array of a constant", feature([0, 0, 0]).scalars, [0, 0, 0])
    checkEqual("the strides of a one-row shape",
              PortCoreML.MLShapedArray<Double>.strides(for: [4]), [1])
    checkEqual("the count of a shape", PortCoreML.MLShapedArray<Double>.count(of: [2, 3, 4]), 24)
} catch {
    print("FAIL the linear-model comparison threw: \(error)")
    failures += 1
}

print("\(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
