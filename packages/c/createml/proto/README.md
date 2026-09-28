# The Core ML model schema, vendored

These are **Apple's**, from `coremltools/mlmodel/format/` on
<https://github.com/apple/coremltools> — `Model.proto`, `FeatureTypes.proto`, `Parameters.proto`,
`DataStructures.proto`, `TreeEnsemble.proto` and `NeuralNetwork.proto`, with `LICENSE.txt` beside
them (Apache-2.0, `Copyright © 2020-2023, Apple Inc.`).

They are here because a `.mlmodel` is a protobuf over this schema, and a port that writes one has to
write *this* schema, not a paraphrase of it. `Protobuf/Codec.swift` implements the **wire format**
and nothing else; every field number the model messages use is read out of these files, and the ones
the model writer emits are named after them.

Nothing is generated from them: this target has no protobuf compiler, and the messages a Core ML
model of these estimators needs are a small, fixed set. The schema is vendored so that a reader can
check every number against the definition it came from, and so that adding a field does not mean
guessing a number.
