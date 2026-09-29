import CreateMLComponents
import Foundation

// The preprocessor: a `Transformer` whose answer depends on its own fit, so that "was it fitted" is
// visible in what it does to a value rather than in a statistic nobody reads. Fitted, it centres on the
// mean of what it saw; unfitted, it answers the value unchanged.
struct FittablePreprocessor: Transformer, Hashable {
    var centre: Double?
    func applied(to input: Double) -> Double { centre.map { input - $0 } ?? input }
    func applied<S>(to input: S) -> [Double] where S: Sequence, S.Element == Double { input.map { applied(to: $0) } }
    var seen: [Double] = []
    func fitted<S>(to input: S) throws -> Self where S: Sequence, S.Element == Double {
        var copy = self
        let values = Array(input)
        copy.seen = values
        copy.centre = values.reduce(0, +) / Double(max(values.count, 1))
        return copy
    }
    // A pipeline hands the *fitted* preprocessor on, so this is the reading that matters.
    func whatItDoes(to value: Double) -> Double { applied(to: value) }
}

// The estimator: records the first feature it is handed, so "what the estimator sees" and "what the
// transformer's preprocessor does" are two readings of one question.
struct Recorder: UpdatableSupervisedEstimator {
    struct Transformer: Equatable {
        var updates: Int = 0
        var firstFeatureSeen: Double?
    }
    func makeTransformer() -> Transformer { Transformer() }
    func fitted(on input: [AnnotatedFeature<Double, Double>]) throws -> Transformer { Transformer() }
    func update(_ t: inout Transformer, with input: [AnnotatedFeature<Double, Double>]) async throws {
        t.updates += 1
        if t.firstFeatureSeen == nil { t.firstFeatureSeen = input.first?.feature }
    }
    func encodeWithOptimizer(_ t: Transformer, to e: inout any EstimatorEncoder) throws {}
    func decodeWithOptimizer(from d: inout any EstimatorDecoder) throws -> Transformer { Transformer() }
}

let pipeline = PreprocessingUpdatableSupervisedEstimator(FittablePreprocessor(), Recorder())
var transformer = pipeline.makeTransformer()
print("after makeTransformer(): preprocessor centre = \(String(describing: transformer.preprocessor.centre))")
print("   1.0 would mean it is unfitted; 0.0 would mean it is fitted and centred on the mean.")
let batch = (1...8).map { AnnotatedFeature(feature: Double($0), annotation: 0.0) }
try await pipeline.update(&transformer, with: batch)
print("after the first update(): the estimator saw \(String(describing: transformer.firstFeatureSeen))")
print("   and the transformer's preprocessor centre is \(String(describing: transformer.preprocessor.centre))")
