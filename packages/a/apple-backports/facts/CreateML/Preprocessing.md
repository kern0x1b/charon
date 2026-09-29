# The preprocessing pipelines: which of them fit their preprocessor, and how that is decided

The host was asked, one probe per type, with the host's own `LinearTransformer` as the instrument — a
*fitted* linear transformer has non-identity `scale` and `offset` while an unfitted one is the identity,
so "was it fitted" is two numbers read off the transformer's public `inner`. Nothing here is
transcribed from Apple's source; every value is read out of the running framework.

## The mechanism, and the check that constrains it

A pipeline's `Preprocessor` is a **`Transformer`**, and the `Transformer` protocol
(`CreateMLComponents.swiftinterface` line 1853) requires only `Input`, `Output` and
`applied(to:eventHandler:)` — there is no `fitted(to:)` on it. So the pipeline cannot fit its
preprocessor, and fitting is a separate step the *caller* performs.

**The check, with its command and count.** No type conforms to both protocols directly:

    $ grep -nE "struct [A-Za-z]+.*CreateMLComponents::Transformer.*CreateMLComponents::Estimator|\
                struct [A-Za-z]+.*CreateMLComponents::Estimator.*CreateMLComponents::Transformer" \
        arm64e-apple-ios-macabi.swiftinterface
    575:  public struct PreprocessingEstimator<Preprocessor, Estimator> : ...Estimator
              where Preprocessor : ...Transformer, Estimator : ...Estimator, ...
    5153: public struct TransformerToEstimatorAdaptor<Transformer> : ...Estimator
              where Transformer : ...Transformer

**Two hits, and neither is a type conforming to both.** Line 575 is a pipeline whose *generic parameter*
is named `Estimator` and whose `Preprocessor` is constrained *to* `Transformer` — the same shape as the
other 17 `Preprocessing*` types, which is why a naive grep for "Transformer" and "Estimator" on the
same line returns 18 and none of them is a type that is both.

**Line 5153 is the one that matters, and it corrects the rule.** `TransformerToEstimatorAdaptor`
conforms to `Estimator` and wraps a `Transformer` — it is the sanctioned route by which a
`Transformer` becomes fittable. So the accurate statement is:

- a `Transformer` has no `fitted(to:)` of its own, and a **pipeline never fits its preprocessor**;
- a caller who wants a fitted preprocessor wraps it in `TransformerToEstimatorAdaptor`, fits *that*, and
  passes the result to the pipeline.

"The host never fits the preprocessor" is a statement about the **pipeline**, and not a prohibition on
fitting a `Transformer` at all.

## One line per type

| type | the port | the host | evidence |
| --- | --- | --- | --- |
| `PreprocessingUpdatableSupervisedEstimator` | **does not fit** — `makeTransformer()` (line 168) hands the preprocessor to `ComposedTransformer.init` (line 33), which stores it as given | **does not fit** — `scale=1.0 offset=0.0` after `makeTransformer()`, after the first update and after the second | `tests/backports/host/createml/probe/preprocessing-updatable-host.swift` and its `.txt` |
| `PreprocessingEstimator` | **fits** — `transformed(_:)` line 57 and `fitted(on:)` line 62, both `preprocessor.fitted(on: training)` | **does not fit** — `scale=1.0 offset=0.0` after `fitted(to:)`, and `preprocessed(from:)` returns the raw `[1, 2, 3, 4, 5, 6, 7, 8]` | `tests/backports/host/createml/probe/preprocessing-estimator-host.swift` and its `.txt` |
| `PreprocessingUpdatableEstimator` | **fits** — `transformed(_:)` line 137 | **not yet measured** | a probe is owed; the mechanism above predicts it does not, and a prediction is not a measurement — the `-7` case was one |

## A divergence in the API surface, in the same family

The host's `PreprocessingEstimator` has **no `transformed(to:)`**: its members are `preprocessed(from:)`,
`fitted(to:)` and `fitted(toPreprocessed:)`. The port has `transformed(_:)` at `Preprocessing.swift:57`.
A member the framework does not have is a public name this port invented, and it belongs in the
invented-names table as its own entry.
