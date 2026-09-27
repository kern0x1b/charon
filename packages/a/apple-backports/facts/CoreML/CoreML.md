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

## What the host differential found, and what it changed

`tests/backports/host/coreml` records what a real Core ML answers for the same containers -- every
description, every constraint, `-isAllowedValue:` over a battery of values, the providers, the keys,
the options, the constants and a prediction per model -- and holds the port's own classes, compiled
under names of their own, to that record: **609 keys, none differing, five recorded divergences**,
and fifteen mutants of the port, none of which survives. Nine things the obvious reading gets wrong
came out of it, and each is now what the framework does:

- **A feature that fixes its shape has a shape constraint, of the *enumerated* kind.** Not none, and
  not a range: the enumerated kind with that one shape in it, and the size ranges filled in as well,
  one per dimension, each of length one. A caller therefore always gets a constraint, and a value of
  a shape that is not one of the shapes is refused rather than waved through.
- **`int64Value` of a double value is 0 and `doubleValue` of a whole number is 0.** The two are
  separate types and not two spellings of one; the accessors are how a caller tells which it has.
- **`stringValue` of a value that is not a string is nil, and so is `dictionaryValue` of one that is
  not a dictionary.** "Not an array" and "an array of no strings" are different facts.
- **An NSNumber is a whole number or a real by its own `objCType`:** `@3` is an Int64 value and
  `@3.0` is a Double value. A model that counts what it is given and one that multiplies it are told
  apart by that.
- **An NSArray handed to a feature provider becomes a sequence**, not a multi array: a sequence is
  what the specification types an input as when the model gives it no shape, and a bare array has
  none.
- **An object that cannot be a feature value at all -- an NSObject, an NSData, an NSURL -- becomes a
  value of the invalid type, and nothing is refused.** The provider is still made, and the caller can
  hand over the rest of its dictionary.
- **A dictionary handed to a feature provider may be nil, and the provider is made anyway**, with no
  names and no values.
- **`+featureValueWithDictionary:` keeps the objects it is given** rather than a copy of the numbers
  among them, and refuses nothing.
- **The metadata of a model that names none has all five keys**, the four named ones as empty strings
  and the creator-defined map as an empty dictionary. A caller can tell a model with no author from
  a model whose metadata is not there.
- **A sequence feature value is of the sequence type, not of its elements' type.** Measured: a value
  built over `+sequenceWithInt64Array:` reports 7 (Sequence) on a release with Core ML, and the
  sequence's own `type` is the kind of its elements, which is a different question.
- **`+[MLFeatureValue featureValueWithSequence:]` is the one constructor that was reporting the
  sequence's element type**, and so reported a value holding three numbers as an int64 value -- fixed,
  and the case that found it is in the differential.

Two more, from the same records:

- **The metadata, the class labels and the parameters of a model with none are empty, not nil** --
  except the two names a classifier answers under, which are nil when the model is not a classifier.
- **An answer takes the shape the model declared for it**, not the shape the layers happened to
  produce: a network whose layers leave a rank of one answers the 1x1x2 its description names, when
  the two hold the same number of elements.

And one that is a property of this host rather than of Core ML, which the check has to know about:
**this host's Core ML no longer reads an uncompiled `.mlmodel`** -- handed one it answers nil and says
to compile it. So the system run of the differential compiles each container with the framework's
own compiler and loads the bundle, and the port reads the same container uncompiled: two frameworks,
one model, in the two forms each of them reads.

## The archive round trip, and where it is better than the framework

`NSSecureCoding` is carried by MLFeatureValue, MLMultiArray and MLSequence, and the round trip is
a case in the differential: a value of every kind is archived, read back, and compared field by
field with what went in. **The review of the value types found the first version losing the value** --
the writer wrote the array and the string and the reader read the type alone -- and it is now
written and read whole, with the kind beside the type because a value of a real type that is
undefined and a value of that type that holds something are different facts.

One difference from the framework is recorded rather than matched, and it is a difference in the
port's favour. **Archiving a value over a multi array and reading it back with
`+[NSKeyedUnarchiver unarchiveObjectWithData:]` raises on Apple's Core ML** --
`NSInvalidUnarchiveOperationException: This method only supports secure coding` -- because
Core ML's own `MLMultiArray` archive is decoded through a non-secure collection path. This port's
`MLMultiArray` archive is secure-decodable, so the array comes back. Nothing is lost either way and
no application can depend on the raise, so the port does the round trip; the difference is named in
`tests/backports/host/coreml/run.sh` next to the check that prints it.

An **image** feature value does not round trip on either: a pixel buffer is not something a secure
archive carries, so the value comes back of the image type and undefined, and the facts say so.

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

## The Objective-C surface this group carries

Eight classes from the previous delivery, and what an application can do with them:

- **`MLMultiArray`** — a typed, strided array of numbers. Every element type the specification
  names, its three initialisers (a shape, a shape with strides, and a caller's buffer with the
  block that gives it back), the deprecated `dataPointer`, the two addressing forms the
  specification declares (a linear index and an array of numbers), `NSSecureCoding`, and
  `+multiArrayByConcatenatingMultiArrays:alongAxis:dataType:`.
- **`MLFeatureValue`** — one value of one feature: every constructor the specification declares
  that this port can build, every accessor, `isEqualToFeatureValue:`, `NSCopying` and
  `NSSecureCoding`.
- **`MLSequence`** — an ordered list of numbers or of strings, which is what a Core ML sequence
  is, with the three constructors and the two accessors the specification declares.

`MLFeatureValue`'s array is a window on the `MLMultiArray`'s own buffer rather than a copy, so
an application that writes through the array it handed over sees the change in the model, which
is what passing an `MLMultiArray` to a model means.

### The model surface, and the two protocols it needs

The second delivery carries the surface an application hands a model through: what the model says
about itself, what it takes, what it answers, and the two ways a caller gives it values.

- **`MLFeatureDescription`** and the eight constraints Core ML declares around it --
  `MLMultiArrayConstraint`, `MLMultiArrayShapeConstraint`, `MLImageConstraint`,
  `MLImageSizeConstraint`, `MLImageSize`, `MLDictionaryConstraint`, `MLSequenceConstraint` and
  `MLNumericConstraint`. Every one is built from the specification's own fields: a feature's name,
  kind, optionality, element type, shape, size range, the set of shapes or of sizes, and a
  sequence's element kind and count range. `-isAllowedValue:` is the model's own check, written out
  rule by rule above.
- **`MLDictionaryFeatureProvider`** and **`MLArrayBatchProvider`**, with the two protocols
  `MLFeatureProvider` and `MLBatchProvider` between them.
- **`MLModel`**, **`MLModelDescription`**, **`MLModelConfiguration`**, **`MLPredictionOptions`**
  and **`MLModelAsset`**: load from a URL or from bytes, predict from one provider or from a
  batch, answer the description, the metadata, the class labels and the parameters the container
  carries, take the options of one run, and compile.
- **`MLKey`**, **`MLParameterKey`**, **`MLMetricKey`** and **`MLParameterDescription`**: the keys
  a model's parameters and metrics are named by, and what one parameter is.
- **The eight exported strings**: `MLModelErrorDomain` and the five metadata keys, the two image
  option keys. Their values were read out of a real Core ML on this host, and the domain is
  `com.apple.CoreML` -- not the framework's name.

Four things in that surface are worth writing down, because the obvious reading of each is wrong:

- **The Core ML error codes are not consecutive.** `MLModelError` skips 2, and the numbers are
  `Generic` 0, `FeatureType` 1, `IO` 3, `CustomLayer` 4, `CustomModel` 5, `Update` 6,
  `Parameters` 7, `DecryptionKeyFetch` 8, `Decryption` 9, `ModelCollection` 10. The bridge's own
  defines were wrong until they were read out of a real framework: a load that fails is `IO`, a
  value of the wrong type for a feature is `FeatureType`, a parameter the model does not have is
  `Parameters`, and a model this port cannot run is `Generic`, because none of the others
  describes it.
- **A protocol has to be a definition, not a declaration.** A class that conforms to
  `MLFeatureProvider` names a protocol object at run time, and on a release with no Core ML there
  is nothing to define it but this port. A protocol the compiler has already seen declared is a
  *reference*, so `MLFeatureProvider.m` declares both protocols before it imports Core ML's
  header, and the conforming classes are in the same file because a protocol nothing in a
  translation unit uses is dropped from it. The objects are then hidden at the link, the way
  Apple's own frameworks keep theirs, since a program reaches a protocol by name and not by
  symbol.
- **`MLMultiArrayConstraint.dataType` is zero when the model names no element type.** Core ML's
  enumeration has no case for "none": every case of it is a real width, so zero is unambiguous
  and a constraint that carries it accepts the array whatever its element type is.
- **`+[MLModel compileModelAtURL:error:]` answers a URL, not a model.** It writes the
  specification's own message into a bundle of the shape a compiled model has, under a name of its
  own in the temporary directory, and answers where it put it. A bundle written this way is read
  and run by this port; Apple's own compiled storage form is private and is not read, as above.

## What this group does not carry, and why

The rest of Core ML's Objective-C surface is **not** in this delivery:

- **The state API of iOS 18** -- `-[MLModel newState]`, the three predictions that take a state,
  `MLFeatureDescription.stateConstraint` and `MLModelDescription.stateDescriptionsByName`. A state
  is a recurrent model's own carry between calls, and the recurrent layers that would carry it are
  refused by name above, so there is no state for any of them to answer about.
- **`MLModel.availableComputeDevices`** and the compute-device family of iOS 17. The set names the
  units a model may run on, and this release has one of them: no Metal driver on iOS 6 and no
  neural engine at all.
- **`MLModelConfiguration.optimizationHints`** and **`MLModelConfiguration.functionName`**: advice
  to a compiler, and the entry point of a model of a program. This port compiles no model -- it
  reads a container and runs it -- and refuses the `mlProgram` form by name.
- **The initialisers Core ML declares `NS_UNAVAILABLE`**: a key, a model asset and an image
  constraint have none, because a model builds them and an application only reads them. Not
  implementing one is what `NS_UNAVAILABLE` means.
- **The image constructors** (`+featureValueWithCGImage:`, `+featureValueWithImageAtURL:` and
  their variants). `+featureValueWithPixelBuffer:` is carried and takes a 32-bit BGRA or ARGB
  buffer; a CGImage or a URL is a decode that belongs with the image handling, and the port
  answers the undefined value of the image type rather than an image it did not decode.
- **The compute-plan, the update-task, the model-structure and the custom-model classes**, and
  the kinds of model the interpreter refuses: support vector machines, k-nearest neighbours,
  item similarity, MIL (`mlProgram`) models, linked and custom models. Each is refused by name
  in `facts/CoreML/CoreML.md`.
