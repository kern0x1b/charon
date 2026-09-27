# The Core ML model format, read from the specification, and the interpreter over it

Apple's model format is open. coremltools (BSD-3-Clause, Apple Inc.) ships the protobuf
specification a `.mlmodel` container is written in, as one generated module per `.proto` file
under `coremltools/proto/`, and the same specification is published as protobuf. Everything
below is read from that specification rather than transcribed: `tools/coreml/gen-schema.py`
reads every message's field number, wire type, type and oneof out of the descriptors
themselves and writes them as a C table, 354 messages and 1059 fields, so a change of
coremltools is a diff a reviewer reads rather than a silent regeneration.

The model kind, the description, the two names a classifier answers under, the class labels
and every weight are read through that table. A field the specification does not name is
stepped over by the wire type its bytes really have, so a container written by a later version
still reads.

## What is measured, and how

Two checks, both run on this host and both recorded under `.agent-work/runs/`:

- `tools/coreml/check-reader.sh` — nine containers written by coremltools' own writer are read
  and the tree printed is compared with the one protobuf's own reflection prints from the same
  file: **five of five identical, and four malformed containers refused** rather than half-read.
  This is a fidelity check on the reader only.
- `tools/coreml/check-predict.sh` — the same containers are run over fixed inputs and the
  answers compared with coremltools' own runtime on this host: **eight models agree to 1e-5 on
  every answer**, and one has a difference written down and checked (below).

## What the arithmetic turned out to be, where the names read otherwise

Three things the obvious reading gets wrong, each measured against coremltools' own runtime
rather than assumed:

- **The scaler is `(x + shift) * scale`,** not `x * scale + shift`. Four inputs through a
  two-feature model: `(2.0 - 1.5) * 0.25 = 0.125` is what comes out, and `2.0 * 0.25 - 1.5`
  is not. The field is named `shiftValue` and reads the other way round.
- **A tree leaf's values name the class they apply to.** A leaf of a two-class tree carries
  two `evaluationInfo` entries, each with an `evaluationIndex`; they are not one vector per
  leaf. The base prediction is one value per class for the same reason, and only the leaves a
  walk down from the tree's root reaches count -- a node some other node names as a child is
  not a root.
- **An L2 normalisation divides the whole value by one length,** not each channel by its own.
  On a two-channel input the per-channel reading gives `(1, -1)`; the runtime gives
  `(0.9915, -0.1302)`, which is the single norm of the two together.

Two more, found by the check and fixed:

- **An embedding's table is laid out per output channel,** the whole row of the table for that
  channel across every index. With the index as the outer dimension the values came out of
  the wrong channel.
- **A GLM classifier in the reference-class encoding has no weight vector for the reference
  class:** it scores zero, the vectors fill the classes after it in order, and the answer is a
  softmax over the whole set. Measured over four inputs of a two-vector, three-class model,
  `softmax(0, w0.x + o0, w1.x + o1)` is that runtime's answer to the last digit. It is *not*
  the per-class logistic the post-evaluation transform names: on these inputs that would give
  `(0.5, 0.525, 0.475)`, which does not sum to one. The encoding's own first case is
  ReferenceClass and a field set to it is not written at all, so absent and ReferenceClass are
  the same value here.

## A divergence, and what is not known about it

`nn_image`, a convolution, a ReLU and a global pool, does not match the host. What has been
ruled out by measurement: the input with and without the network's own scale and per-channel
bias, the weight axes in all six orders with the output channel inner and outer, and both pool
kinds after a ReLU. None reproduces the host's four numbers, whose second is exactly zero. The
port's own values are in `nn_image.actual` beside the host's. The check prints this as a
recorded divergence and **fails if the two ever come to agree**, so a stale explanation is
caught.

## Carried but not measured

Each of these is refused with a line naming the layer, not approximated:

- **`loadConstant`.** coremltools 9.0's runtime wants a constant in the five dimensions of the
  rank-five array mapping, refuses a rank-5 network input as well, and so will not run a network
  carrying a constant at all.
- **A concat, a permute, a copy, a softmax on a rank-3 value, and a two-input add on values of
  one and two dimensions** are each refused by that runtime ("Unsupported layer type"), so no
  model carrying them can be compared against it. A softmax is measured on the dense
  classifier instead, where it is the last layer.
- **The recurrent layers** (`simpleRecurrent`, `gru`, the LSTMs). A recurrent layer takes a
  *sequence*, which the specification types as a dictionary of indices to vectors, and the
  runtime refuses every multiArray shape for it. This port does not carry a sequence value
  yet, so the simple recurrent layer is carried but has never been run against anything.
- **Batch normalisation, the padding layer and the rank-five array mapping.** The model that
  would measure them is written (`build_nn_layers_image` in `tools/coreml/make-models.py`) and
  is not in the set, because the runtime refuses a rank-3 input to a convolution ("expects
  rank at least 4") and a rank-5 one as a network input.

## What the port does not do at all

- **A compiled `.mlmodelc` bundle.** The bundle's `coremldata.bin` is Apple's compiled storage
  container, not the specification's own protobuf message: it does not parse as a `Model` and
  the format is private. A `.mlmodel` file is read and run; a bundle whose `coremldata.bin` is
  a bare `Model` message is read and run; a bundle in the compiled storage form fails the
  load with a line saying so.
- **The kinds of model that are not the neural network, the tree ensemble, the GLM and the
  preprocessing models**: support vector machines, k-nearest neighbours, item similarity,
  nearest neighbours, the `mlProgram` (MIL text) models, and the linked-model and custom-model
  forms. Each is refused by name.

## Files

| File | Holds |
| --- | --- |
| `CharonMLSchema.h`, `CharonMLSchema.c`, `CharonMLSchema.inc` | the specification as a table, and the lookup over it |
| `CharonMLProto.h`, `CharonMLProto.c` | the wire format, and the document it builds |
| `CharonMLValue.h`, `CharonMLValue.c` | a feature's value: a number, a string, an array, a dictionary |
| `CharonMLTensor.h`, `CharonMLTensor.c` | a float tensor and the shape arithmetic the layers need |
| `CharonMLModel.h`, `CharonMLModel.c` | the model: its kind, its description, its class labels, its loading |
| `CharonMLLayers.h`, `CharonMLLayers.c`, `CharonMLLayerKinds.h`, `CharonMLLayerKinds.c` | the layers, dispatched by the field number of the specification's layer oneof |
| `CharonMLPredict.h`, `CharonMLPredict.c` | the run: pipelines, networks, trees, GLMs, preprocessing, and the answers |
| `tools/coreml/gen-schema.py` | the generator for the table |
| `tools/coreml/make-models.py` | the containers, and the host's own answers for them |
| `tools/coreml/ml-dump.c`, `tools/coreml/predict-main.c` | the two harnesses the checks drive |
| `tools/coreml/check-reader.sh`, `tools/coreml/check-predict.sh` | the two checks |
