# The `.mlmodel` export, and exactly how far it is verified

## What is written

A **linear** model, as a Core ML `NeuralNetworkRegressor` of one `innerProduct` layer, and that is not a
wrapper: for a row of features `x` the layer computes `bias + weights · x`, which *is* a linear model,
and Core ML executes it. Every field number is read out of the vendored schema in `packages/c/createml/proto/`:

| message | fields used |
| --- | --- |
| `Model` | `specificationVersion = 1`, `description = 2`, `neuralNetworkRegressor = 303` |
| `ModelDescription` | `input = 1`, `output = 10`, `metadata = 100` |
| `FeatureDescription` | `name = 1`, `type = 3` |
| `FeatureTypes` | oneof `{ doubleType = 2, multiArrayType = 5 }` |
| `ArrayFeatureType` | `shape = 1`, `dataType = 2` (FLOAT32 = `0x10000\|32` = 65568) |
| `NeuralNetworkRegressor` | `layers = 1` — **the layers are direct**, not a nested `NeuralNetwork` |
| `NeuralNetworkLayer` | `name = 1`, `input = 2`, `output = 3`, oneof `{ innerProduct = 140 }` |
| `InnerProductLayerParams` | `inputChannels = 1`, `outputChannels = 2`, `hasBias = 10`, `weights = 20`, `bias = 21` |
| `WeightParams` | `floatValue = 1` |

Two details a hand-written writer gets wrong first, and both are said so in `ModelWriter.swift`:
`NeuralNetworkRegressor` carries its layers **directly** (the older spelling nested a `NeuralNetwork`),
and `hasBias` must be set even when the bias is zero, because a layer with `hasBias` false and a bias
blob is a model the reader rejects.

## How far it is verified, and what is not verified

**Reached, and independently:** `coremltools 9.0` — a protobuf implementation written by neither this
port nor Swift's Core ML — parses the file and every field round-trips. The suite checks all of it:
the specification version, the oneof, the input and output names, the input shape `[1, n]`, the
`FLOAT32` data type, `inputChannels`, `outputChannels`, `hasBias`, the weights in order, and the
intercept. It also round-trips through the port's own reader, so a writer whose reader cannot read it
is caught before any other implementation is asked.

**Not reached: a load and a predict.** That is the only check that says the *arithmetic* is right and
not only the schema, and on this machine's CoreML Swift surface it is not reachable:

- `MLModel.prediction(fromFeatures:options:)` — `unavailable in macOS`;
- `MLModel.prediction(from:)` — takes `[String: MLTensor]` and is `async`, so it needs a top-level
  `await`, which is allowed only in a file named `main.swift`;
- `MLTensor(shape:scalars:)` — trips a compiler crash, `failed to produce diagnostic for expression`.

**So the differential compares predictions, not a loaded model, and no claim is made about the
arithmetic.** **`write(to:)` on all six estimators still throws `MLCreateErrorCode.cannotWriteModel`:** the writer
exists and is proven, and wiring it into the estimators' `write(to:)` is not done. That is the crutch.

## What is not written, and why it is refused rather than approximated

The forests and the boosted forests are `TreeEnsembleRegressor` (field 302) with a different layer
set, and the three classifiers are `NeuralNetworkClassifier` (403) with a string output. A model file
that said `NeuralNetworkRegressor` and carried a forest would be a model Core ML loads and answers with
**the wrong arithmetic**, which is the failure the rules name. So those five refuse, and their
`write(to:)` says which kind is missing.

## The mutation, and it dies

Writing the intercept into the `weights` field and the weights into `bias` — the classic transposition
in a linear model, and the one field order the read-back is there to hold:

```
FAIL and the weights in order: the port answered [3.0]
FAIL and the intercept: the port answered 2.0,-1.5,3.0
```

The check is every field read back by **an implementation that is not this port's**, with the weights
and the intercept compared *in order* — so a wrong field number, a transposed weight vector, and a
scalar where a vector belongs are all caught, by coremltools rather than by the port's own reader.

The writer's own round trip runs first, so a writer whose reader cannot read it is caught before any
other implementation is asked.
