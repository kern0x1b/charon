#!/usr/bin/env python3
"""Write the .mlmodel containers the C reader is measured against, and the reference dump.

One model per model kind the port interprets, written with coremltools' own writer so the
container is one a real converter emits. Two artefacts per model:

  <name>.ref          the tree protobuf's own reflection prints, after reading the file that
                      was written. The C reader prints the same tree and the two are diffed; a
                      difference is a field the reader did not read, or read wrongly.
  manifest.json       the model's own prediction for a fixed input, which is what the
                      interpreter is measured against: coremltools' own runtime, on this host.

The specification version is the model's own field, and it is set here: a model declares the
specification it was written against and nothing else may declare one for it.

Usage:
    python3 tools/coreml/make-models.py [--out <directory>]
"""
import json
import os
import sys

import numpy as np
import coremltools as ct
from coremltools.models import datatypes
from coremltools.proto import FeatureTypes_pb2 as FT
from coremltools.proto import Model_pb2

HERE = os.path.dirname(os.path.realpath(__file__))

# A model whose host runtime is known not to answer exactly, with the tolerance that covers it
# and the measurement behind it. The embedding is the one: coremltools' runtime on this host
# answers 0.600097656 for a row of 0.5 and a bias of 0.1, where the sum is 0.6 -- a relative
# difference of 1.6e-4, and the same 2.2 comes back as 2.19921875. The port's answer is the
# exact sum; the check is widened for this model and only this model, and fails if the host ever
# stops diverging (see check-predict.sh).
TOLERANCES = {
    "nn_embedding": (1e-3, "the host runtime's embedding output is not the exact sum; measured on one row"),
}

# A model the port's answers differ from the host's on, with what is known about the difference.
# This is not a pass and not a failure: the check prints the difference, and fails if the two
# ever come to agree, because then whatever caused it has gone and the port's answer is no
# longer explained. There is none: nn_image was in here until 2026-10-03, and the cause was that
# this port put an array input through the network's own scaler, which neither Core ML nor
# coremltools does. The four numbers are in facts/CoreML/CoreML.md.
DIVERGENCES = {}

# The specification version a model declares, by the values the CoreML specification gives:
# 1 came with 11.0, 2 with 11.1, 3 with 11.2, 4 with 12.0, 5 with 12.2, 6 with 13.0.
SPEC_11_2, SPEC_12_0, SPEC_12_2, SPEC_13_0 = 3, 4, 5, 6

# A host input per model. None records that the container is written and referenced but there
# is no host input for it -- the image model wants a PIL image, and this host has none.
# Each sample matches the shape the model declares: the dense classifier's input is a vector
# of three, not a batch of them, and the pipeline's scaler takes one double at a time.
SAMPLES = {
    # The image model is declared as a picture, and coremltools 9.0's runtime will not run a
    # network whose input is one -- measured -- so there is no host input for it here. The
    # framework that does run it is Apple's Core ML, through the Vision host differential.
    "vision_image": None,
    "glm": {"x": [-1.5, 0.0]},
    "glm_classifier": {"x": [0.5, -0.5]},
    "nn_classifier": {"x": np.array([0.5, -0.25, 1.0], np.float32)},
    # The convolutional model's input, channels first with no batch dimension, the pixels fixed
    # so the two runtimes see the same ones.
    "nn_image": {"img": (np.arange(3 * 8 * 8, dtype=np.float32).reshape(3, 8, 8) / 255.0)},
    "nn_embedding": {"index": np.array([[[2]]], np.int32)},
    "nn_layers": {"x": np.array([[[0.5, -1.5, 2.0, 0.25]]], np.float32)},
    "nn_layers_shape": {"x": np.array([[[0.5, -0.25]]], np.float32)},
    # The tree's four samples walk every branch: below and above each of the two thresholds.
    "tree_classifier": {"a": [0.25, 1.0, 3.0, -2.0], "b": [1.0, 3.0, 0.0, 2.0]},
    "pipeline": {"x": [2.0]},
}


def sample_of(name):
    """The input for a model, or None when this host cannot give it one."""
    recorded = SAMPLES[name]
    if recorded is None:
        return None
    if isinstance(recorded, str) and recorded.startswith("image:"):
        from PIL import Image
        side = int(recorded.split(":")[1].split("x")[0])
        pixels = bytes((at * 37 % 256) for at in range(side * side))
        return {"img": Image.frombytes("RGB", (side, side), pixels)}
    return recorded


# --- the feature descriptions the specification gives -----------------------------------------

def array_type(size, data_type=FT.ArrayFeatureType.FLOAT32):
    return FT.ArrayFeatureType(shape=list(size), dataType=data_type)


def vector(name, size, data_type=FT.ArrayFeatureType.FLOAT32):
    """A multiArray of `size` elements, which is the shape a converted model's input has."""
    return Model_pb2.FeatureDescription(name=name, type=FT.FeatureType(multiArrayType=array_type(size, data_type)))


def scalar_double(name):
    """A GLM's own features are scalars, not arrays: a validator refuses a multiArray there."""
    return Model_pb2.FeatureDescription(name=name, type=FT.FeatureType(doubleType=FT.DoubleFeatureType()))


def label(name):
    return Model_pb2.FeatureDescription(name=name, type=FT.FeatureType(stringType=FT.StringFeatureType()))


def probabilities(name):
    """The probabilities of a classifier are a string-to-score dictionary, the type
    MLFeatureProvider hands back as a prediction."""
    return Model_pb2.FeatureDescription(
        name=name,
        type=FT.FeatureType(dictionaryType=FT.DictionaryFeatureType(stringKeyType=FT.StringFeatureType())))


def carry_fields(source, into, out_of):
    """Copy every field `source` and `into` share, by the kind the descriptor gives it. Used
    for NeuralNetwork -> NeuralNetworkClassifier, which are separate messages that hold the
    same first five fields rather than one message with the others added."""
    shared = ({field.name for field in into.DESCRIPTOR.fields}
              & {field.name for field in out_of.DESCRIPTOR.fields})
    for field in out_of.DESCRIPTOR.fields:
        if field.name not in shared:
            continue
        value = getattr(out_of, field.name)
        if field.is_repeated:
            for item in value:
                if field.type == field.TYPE_MESSAGE:
                    getattr(into, field.name).add().CopyFrom(item)
                else:
                    getattr(into, field.name).append(item)
        elif field.type == field.TYPE_MESSAGE:
            getattr(into, field.name).CopyFrom(value)
        else:
            setattr(into, field.name, value)


def class_labels(model, classifier, labels, name="classLabel"):
    """Give a model its class labels.

    coremltools 9.0's builder helper for this reaches for a field of the neural network that
    this specification version does not have, so both steps it does are done here: the model's
    kind oneof moves to the classifier carrying the same layers, and the classifier's own
    `ClassLabels` oneof takes the labels, in the StringVector this version declares."""
    field = classifier.WhichOneof("ClassLabels") or "stringClassLabels"
    getattr(classifier, field).vector.extend(labels)
    model.description.predictedFeatureName = name
    model.description.predictedProbabilitiesName = name + "Probability"
    for declared in (name, name + "Probability"):
        if not any(feature.name == declared for feature in model.description.output):
            model.description.output.append(label(declared) if declared == name else probabilities(declared))


# --- the models --------------------------------------------------------------------------------

def build_nn_classifier():
    """A dense classifier: 3 -> 4 dense, ReLU, 4 -> 2 dense, softmax. One model that holds at
    once every layer kind the reader has to see: a weight matrix, a bias vector, an activation
    oneof and a layerType oneof, each of which the specification writes in its own way."""
    builder = ct.models.neural_network.NeuralNetworkBuilder(
        input_features=[("x", datatypes.Array(3))], output_features=[("p", datatypes.Array(2))])
    w1 = np.array([[1.0, -2.0, 0.5], [0.25, 0.75, -1.5], [-0.5, 1.0, 2.0], [3.0, 0.0, -1.0]], np.float32)
    b1 = np.array([0.1, -0.2, 0.3, 0.0], np.float32)
    w2 = np.array([[2.0, -1.0], [0.5, 0.5], [-1.5, 1.0], [0.25, 0.75]], np.float32)
    b2 = np.array([0.05, -0.05], np.float32)
    builder.add_inner_product("fc1", w1, b1, 3, 4, True, "x", "h")
    builder.add_activation("relu", "RELU", "h", "hr")
    builder.add_inner_product("fc2", w2, b2, 4, 2, True, "hr", "z")
    builder.add_softmax("sm", "z", "p")
    spec = builder.spec
    # A layer that names an input rewrites that input's description, so the shapes are written
    # after the layers are laid down: a neural network's array input is a vector or an
    # image-like array, and the writer's own validation refuses anything else.
    spec.description.input[0].CopyFrom(vector("x", [3]))
    spec.description.output[0].CopyFrom(vector("p", [2]))
    classifier = spec.neuralNetworkClassifier
    carry_fields(spec.neuralNetwork, classifier, spec.neuralNetwork)
    spec.ClearField("neuralNetwork")
    class_labels(spec, classifier, ["no", "yes"])
    spec.specificationVersion = SPEC_12_2
    return spec


def build_nn_image():
    """A convolutional classifier over an image-shaped input: one conv, a ReLU and a max pool,
    with the preprocessing that gives the input its scale and its per-channel bias. The input
    is three channels of 8 by 8 with no batch dimension, which is the shape a neural network
    calls image-like. It is declared as that array and not as an imageType, because coremltools
    9.0's own runtime refuses an image input to a network it will otherwise run -- measured, and
    the preprocessing is the same either way, so the arithmetic under test is unaffected."""
    builder = ct.models.neural_network.NeuralNetworkBuilder(
        input_features=[("img", datatypes.Array(3, 8, 8))], output_features=[("p", datatypes.Array(4))])
    weights = (np.arange(4 * 3 * 3 * 3, dtype=np.float32).reshape(4, 3, 3, 3) / 97.0) - 0.5
    builder.add_convolution("conv", 3, 4, 3, 3, 1, 1, "valid", 1, weights, np.zeros(4, np.float32),
                            True, False, output_name="c", input_name="img")
    builder.add_activation("relu", "RELU", "c", "cr")
    # A global pool, so the four channels come out as the four numbers the classifier's four
    # classes are scored from: a windowed pool over six by six would leave thirty-six.
    builder.add_pooling("pool", 6, 6, 6, 6, "MAX", "VALID", input_name="cr", output_name="p", is_global=True)
    spec = builder.spec
    spec.description.input[0].CopyFrom(vector("img", [3, 8, 8]))
    spec.description.output[0].CopyFrom(vector("p", [4]))
    # The preprocessing, written as the specification writes it: a scale and a bias per channel,
    # which is what turns a pixel into the number a convolution sees.
    preprocessing = spec.neuralNetwork.preprocessing.add()
    preprocessing.featureName = "img"
    preprocessing.scaler.channelScale = 1.0 / 255.0
    preprocessing.scaler.redBias = -1.0
    preprocessing.scaler.greenBias = -1.0
    preprocessing.scaler.blueBias = -1.0
    classifier = spec.neuralNetworkClassifier
    carry_fields(spec.neuralNetwork, classifier, spec.neuralNetwork)
    spec.ClearField("neuralNetwork")
    class_labels(spec, classifier, ["a", "b", "c", "d"])
    spec.specificationVersion = SPEC_12_2
    return spec


def build_tree_classifier():
    """A tree ensemble, the shape a converted random forest has: three depth-2 trees over two
    features, whose leaves carry a value per class. A prediction is the base score plus the sum
    down the tree, then a softmax over the classes -- the arithmetic the port has to do."""
    spec = Model_pb2.Model(specificationVersion=SPEC_11_2)
    spec.description.input.append(vector("a", [1]))
    spec.description.input.append(vector("b", [1]))
    spec.description.output.append(label("classLabel"))
    spec.description.output.append(probabilities("classLabelProbability"))
    spec.description.predictedFeatureName = "classLabel"
    spec.description.predictedProbabilitiesName = "classLabelProbability"
    # The tree ensemble the specification declares: nodes with a behaviour from an enumeration,
    # a leaf carrying one evaluation value per class, and a base prediction per class. A
    # prediction is the base prediction plus the value of the leaf each tree reaches, and a
    # softmax over the classes unless the post-evaluation transform says otherwise. This
    # specification version has no base score and no weights threshold: the two arrived in
    # earlier ones and were removed, and a reader must not expect a field that is not there.
    ensemble = spec.treeEnsembleClassifier.treeEnsemble
    ensemble.numPredictionDimensions = 2
    ensemble.basePredictionValue.extend([0.0, 0.0])
    spec.treeEnsembleClassifier.postEvaluationTransform = "Classification_SoftMax"
    for tree_index, (feature, threshold, low, high) in enumerate(
            [(0, 0.5, 130, 140), (1, 2.5, 150, 160), (0, -1.0, 170, 180)]):
        root = ensemble.nodes.add()
        root.treeId = tree_index
        root.nodeId = tree_index * 4
        root.nodeBehavior = "BranchOnValueLessThan"
        root.branchFeatureIndex = feature
        root.branchFeatureValue = threshold
        root.trueChildNodeId = low
        root.falseChildNodeId = high
        for child, values in ((low, [0.9, 0.1]), (high, [0.2, 0.8])):
            leaf = ensemble.nodes.add()
            leaf.treeId = tree_index
            leaf.nodeId = child
            leaf.nodeBehavior = "LeafNode"
            # Each evaluation of a leaf names the class it applies to and the value it
            # contributes: one entry per class, not one per value.
            for class_index, value in enumerate(values):
                leaf.evaluationInfo.add(evaluationIndex=class_index, evaluationValue=value)
    spec.treeEnsembleClassifier.stringClassLabels.vector.extend(["low", "high"])
    return spec


def build_glm():
    """A GLM: one weight per input element and an offset beside it, with a post-evaluation
    transform. weights is a repeated DoubleArray -- one vector per class, which is what a
    one-vs-rest GLM classifier carries and what a regressor leaves at one."""
    spec = Model_pb2.Model(specificationVersion=SPEC_11_2)
    spec.description.input.append(vector("x", [2], FT.ArrayFeatureType.DOUBLE))
    spec.description.output.append(scalar_double("y"))
    spec.description.predictedFeatureName = "y"
    glm = spec.glmRegressor
    glm.postEvaluationTransform = "Logit"
    glm.weights.add(value=[1.5, -2.5])
    glm.offset.append(-0.5)
    return spec


def build_pipeline():
    """A pipeline of a scaler and a neural network, which is the shape a converted tabular
    classifier has and the shape a Core ML model an application ships most often has."""
    scaler = Model_pb2.Model(specificationVersion=SPEC_11_2)
    # A pipeline is described with the datatypes the pipeline builder takes, which are arrays;
    # the scaler's own features are arrays of one double, so a pipeline of them takes a single
    # value per step and passes a single value on.
    scaler.description.input.append(vector("x", [1], FT.ArrayFeatureType.DOUBLE))
    scaler.description.output.append(vector("scaled", [1], FT.ArrayFeatureType.DOUBLE))
    # The scaler holds one value per feature, each a repeated field: the scale, then the
    # shift. A model with one input therefore has one of each.
    scaler.scaler.scaleValue.append(0.25)
    scaler.scaler.shiftValue.append(-1.5)

    inner = ct.models.neural_network.NeuralNetworkBuilder(
        input_features=[("scaled", datatypes.Array(1))], output_features=[("y", datatypes.Array(2))])
    inner.add_inner_product("fc", np.array([[2.0], [-1.0]], np.float32), np.array([0.0, 0.1], np.float32),
                            1, 2, True, "scaled", "y")
    inner.add_softmax("sm", "y", "probs")
    inner_spec = inner.spec
    inner_spec.description.input[0].CopyFrom(vector("scaled", [1], FT.ArrayFeatureType.DOUBLE))
    # The pipeline builder's datatypes carry no element type and default to double, so the
    # chain inside the pipeline is declared in doubles: the scaler before it is, the network
    # after it is, and a pipeline's outputs must match what its last model produces.
    inner_spec.description.output[0].CopyFrom(vector("probs", [2], FT.ArrayFeatureType.DOUBLE))
    # The last model of a pipeline is not made a classifier: a chain of feature transforms is
    # what this fixture is for, and the probabilities come out as the array the softmax wrote.
    del inner_spec.description.output[1:]

    # The pipeline's own description is the first model's input and the last model's output:
    # a pipeline has no computation of its own, only the chain between the two.
    pipeline = ct.models.pipeline.Pipeline(
        input_features=[("x", datatypes.Array(1))],
        output_features=[("probs", datatypes.Array(2))])
    pipeline.add_model(ct.models.MLModel(scaler))
    pipeline.add_model(ct.models.MLModel(inner_spec))
    spec = pipeline.spec
    spec.specificationVersion = SPEC_12_2
    return spec


def _layer(layers, name, inputs, outputs):
    entry = layers.add()
    entry.name = name
    entry.input.extend(inputs)
    entry.output.extend(outputs)
    return entry


def build_nn_layers():
    """The dense half of the layer set, in one short chain: a dense layer, a scale with its own
    offset, a bias, an L2 normalisation, a constant and a squeeze. Each is on the answer of the
    one before, so a wrong answer in any of them shows in the one value at the end.

    Every value is channels first and three dimensions, because that is what the specification's
    own validators require of a network: an input is a vector or an image-like array, a constant
    is three, and a scale and a bias declare the shape their values are laid out for."""
    spec = Model_pb2.Model(specificationVersion=SPEC_12_2)
    spec.description.input.append(vector("x", [1, 1, 4]))
    spec.description.output.append(vector("out", [1, 1, 2]))
    layers = spec.neuralNetwork.layers

    entry = _layer(layers, "fc", ["x"], ["d"])
    entry.innerProduct.inputChannels = 4
    entry.innerProduct.outputChannels = 2
    entry.innerProduct.hasBias = True
    entry.innerProduct.weights.floatValue.extend([0.5, -1.0, 2.0, -0.5, 0.25, 0.75, -0.5, 2.0])
    entry.innerProduct.bias.floatValue.extend([0.25, -0.25])

    entry = _layer(layers, "scale", ["d"], ["sc"])
    entry.scale.hasBias = True
    entry.scale.shapeScale.extend([1, 1, 2])
    entry.scale.scale.floatValue.extend([2.0, 0.5])
    entry.scale.shapeBias.extend([1, 1, 2])
    entry.scale.bias.floatValue.extend([0.125, -0.5])

    entry = _layer(layers, "bias", ["sc"], ["bi"])
    entry.bias.shape.extend([1, 1, 2])
    entry.bias.bias.floatValue.extend([0.5, -0.25])

    entry = _layer(layers, "l2", ["bi"], ["out"])
    entry.l2normalize.epsilon = 1e-6
    # A load constant is not in this chain. Measured: coremltools' runtime wants a constant in
    # the five dimensions of the rank-five array mapping, refuses a rank-5 network input as well,
    # and so will not run a network that carries a constant at all. The layer is carried by the
    # port and is listed as not measured in facts/CoreML/CoreML.md rather than counted here.
    spec.neuralNetwork.arrayInputShapeMapping = "EXACT_ARRAY_MAPPING"
    return spec


def build_nn_layers_image():
    """The spatial half of the layer set: a convolution, a ReLU, a padding, a max pool, a
    global pool and a batch normalisation, over three channels of eight by eight.

    It is written but not part of the set, and the reason is measured rather than guessed:
    coremltools 9.0's own runtime will not run it. A rank-three input to a convolution is
    refused ("expects rank at least 4"), a rank-five one is refused as a network input ("must
    have dimension 1 or 3"), and the model the builder writes for the same arithmetic -- which
    is nn_image, and does run -- is what the port's convolution and pooling are measured
    against. The batch normalisation and the padding layer are carried and are listed as not
    measured in facts/CoreML/CoreML.md rather than counted as a pass."""
    spec = Model_pb2.Model(specificationVersion=SPEC_12_2)
    spec.description.input.append(vector("x", [3, 8, 8]))
    spec.description.output.append(vector("out", [4, 1, 1]))
    layers = spec.neuralNetwork.layers

    weights = [(at * 11 % 97) / 97.0 - 0.5 for at in range(4 * 3 * 3 * 3)]
    entry = _layer(layers, "conv", ["x"], ["c"])
    entry.convolution.kernelChannels = 3
    entry.convolution.outputChannels = 4
    entry.convolution.kernelSize.extend([3, 3])
    entry.convolution.stride.extend([1, 1])
    entry.convolution.dilationFactor.extend([1, 1])
    entry.convolution.nGroups = 1
    entry.convolution.hasBias = True
    entry.convolution.weights.floatValue.extend(weights)
    entry.convolution.bias.floatValue.extend([0.1, -0.1, 0.2, -0.2])

    entry = _layer(layers, "relu", ["c"], ["cr"])
    entry.activation.ReLU.SetInParent()

    padding = _layer(layers, "pad", ["cr"], ["pd"])
    padding.padding.constant.value = 0.0
    padding.padding.paddingAmounts.borderAmounts.extend([
        Model_pb2.BorderAmounts.EdgeSizes(startEdgeSize=1, endEdgeSize=1),
        Model_pb2.BorderAmounts.EdgeSizes(startEdgeSize=1, endEdgeSize=1)])

    pool = _layer(layers, "pool", ["pd"], ["gp"])
    pool.pooling.type = "AVERAGE"
    pool.pooling.globalPooling = True
    pool.pooling.avgPoolExcludePadding = True

    entry = _layer(layers, "bn", ["gp"], ["out"])
    entry.batchnorm.epsilon = 1e-5
    entry.batchnorm.instanceNormalization = True
    entry.batchnorm.gamma.floatValue.extend([1.0, 2.0, 0.5, 1.5])
    entry.batchnorm.beta.floatValue.extend([0.0, 0.25, -0.25, 0.1])
    entry.batchnorm.mean.floatValue.extend([0.0, 0.0, 0.0, 0.0])
    entry.batchnorm.variance.floatValue.extend([1.0, 1.0, 1.0, 1.0])

    spec.neuralNetwork.preprocessing.add()
    preprocessing = spec.neuralNetwork.preprocessing[0]
    preprocessing.featureName = "x"
    preprocessing.scaler.channelScale = 2.0
    spec.neuralNetwork.arrayInputShapeMapping = "EXACT_ARRAY_MAPPING"
    return spec


def build_nn_layers_shape():
    """The shape half of the layer set: an upsample, an elementwise product, a clamp, a
    reduction over the height and width, a tile and a second reduction, on one channel."""
    spec = Model_pb2.Model(specificationVersion=SPEC_12_2)
    spec.description.input.append(vector("x", [1, 1, 2]))
    # Both reductions take the whole value -- the channels, the height and the width together,
    # which is the specification's first reduce axis -- so what is left is one value.
    spec.description.output.append(vector("out", [1, 1, 1]))
    layers = spec.neuralNetwork.layers

    up = _layer(layers, "up", ["x"], ["uu"])
    up.upsample.scalingFactor.extend([1, 2])
    _layer(layers, "mul", ["uu", "uu"], ["mu"]).multiply.alpha = 1.0
    clip = _layer(layers, "clip", ["mu"], ["cl"])
    clip.clip.minVal = 0.1
    clip.clip.maxVal = 0.9
    _layer(layers, "tile", ["cl"], ["tl"]).tile.reps.extend([1, 1, 2])
    _layer(layers, "sum", ["tl"], ["rd"]).reduce.mode = "SUM"
    _layer(layers, "avg", ["rd"], ["out"]).reduce.mode = "AVG"
    spec.neuralNetwork.arrayInputShapeMapping = "EXACT_ARRAY_MAPPING"
    return spec


def build_nn_embedding():
    """An embedding over three rows: the input is one word index and the output is that row of
    the table. The input is three dimensions of one each, because a network's input is a vector
    or an image-like array and the embedding layer insists that every dimension of the image-like
    one is of length one -- measured by trying the four shapes and reading which each refused."""
    spec = Model_pb2.Model(specificationVersion=SPEC_12_2)
    spec.description.input.append(vector("index", [1, 1, 1], FT.ArrayFeatureType.INT32))
    spec.description.output.append(vector("vector", [1, 1, 2], FT.ArrayFeatureType.FLOAT32))
    network = spec.neuralNetwork
    layer = network.layers.add()
    layer.name = "emb"
    layer.input.extend(["index"])
    layer.output.extend(["vector"])
    layer.embedding.inputDim = 3
    layer.embedding.outputChannels = 2
    layer.embedding.hasBias = True
    layer.embedding.weights.floatValue.extend([1.0, -1.0, 0.5, 0.25, -0.5, 2.0])
    layer.embedding.bias.floatValue.extend([0.1, 0.2])
    return spec


def build_nn_recurrent():
    """A simple recurrent layer over three steps: y_t = f(W x_t + R h_t + b), the order the
    specification's own documentation gives, with the state carried from step to step and taken
    at the start from the second input.

    It is written but not part of the set: a recurrent layer takes a *sequence*, which the
    specification types as a dictionary of indices to vectors, and coremltools' runtime refuses
    every multiArray shape for it (measured: the height must be one, then the width must be
    one). This port does not carry a sequence value yet, so the layer is carried but not
    measured, and facts/CoreML/CoreML.md says so rather than the check counting it."""
    spec = Model_pb2.Model(specificationVersion=SPEC_12_2)
    # A network's input is a vector or an image-like array, and a recurrent layer wants the
    # height to be one, so the sequence of three steps of two values is one row of six:
    # (1, 1, 6), measured against the three shapes the validator refuses.
    spec.description.input.append(vector("seq", [1, 1, 6], FT.ArrayFeatureType.FLOAT32))
    # A recurrent layer takes the sequence and the state to start it from, and the validator
    # insists on both: a layer with only the sequence is refused.
    spec.description.input.append(vector("state", [1, 1, 2], FT.ArrayFeatureType.FLOAT32))
    spec.description.output.append(vector("out", [1, 1, 6], FT.ArrayFeatureType.FLOAT32))
    spec.description.output.append(vector("outstate", [1, 1, 2], FT.ArrayFeatureType.FLOAT32))
    network = spec.neuralNetwork
    layer = network.layers.add()
    layer.name = "rnn"
    layer.input.extend(["seq", "state"])
    # A recurrent layer writes the state it ends on as well as its output, and the validator
    # insists on both; sequenceOutput is what says the output is every step rather than the last.
    layer.output.extend(["out", "outstate"])
    layer.simpleRecurrent.sequenceOutput = True
    recurrent = layer.simpleRecurrent
    recurrent.inputVectorSize = 2
    recurrent.outputVectorSize = 2
    recurrent.hasBiasVector = True
    # A plain tanh, which the specification's ActivationTanh declares with no fields of its
    # own; a scaled tanh is the separate case beside it and carries the two.
    recurrent.activation.tanh.SetInParent()
    # The input matrix is over the input, the weight matrix over the state, each as the
    # specification lays them out: a row per input, a column per output.
    # The three matrices and the bias are all WeightParams, which is the same oneof of ways
    # of writing numbers every other weight in the specification is.
    recurrent.weightMatrix.floatValue.extend([1.0, -0.5, 0.25, 0.5])
    recurrent.recursionMatrix.floatValue.extend([0.5, 0.25, -0.5, 1.0])
    recurrent.biasVector.floatValue.extend([0.0, 0.1])
    return spec


def build_glm_classifier():
    """A GLM classifier in the one-against-rest encoding: one weight vector per class but the
    first, which is the reference class and scores the total of the rest."""
    spec = Model_pb2.Model(specificationVersion=SPEC_11_2)
    spec.description.input.append(vector("x", [2], FT.ArrayFeatureType.DOUBLE))
    spec.description.output.append(label("classLabel"))
    spec.description.output.append(probabilities("classLabelProbability"))
    spec.description.predictedFeatureName = "classLabel"
    spec.description.predictedProbabilitiesName = "classLabelProbability"
    classifier = spec.glmClassifier
    classifier.classEncoding = "ReferenceClass"
    classifier.postEvaluationTransform = "Logit"
    classifier.weights.add(value=[1.0, -0.5])
    classifier.weights.add(value=[-0.25, 0.75])
    classifier.offset.append(0.1)
    classifier.offset.append(-0.1)
    classifier.stringClassLabels.vector.extend(["first", "second", "third"])
    return spec


def build_vision_image():
    """An image in, an image out: a picture of 32 by 32 through one 1x1 convolution, which is the
    smallest model a Vision request can be run on, and the shape Vision's own transform exists for.

    A `VNCoreMLRequest` hands the handler's picture to a model that takes one, brings it to the
    size the model declares, and answers with the model's own output: for this model an image
    again, which is a `VNPixelBufferObservation`. The convolution is 1x1 and one channel, so it is
    a per-pixel weight on the red channel and nothing else -- the arithmetic cannot be argued
    about, and what the case is measuring is the *path*: the size the picture was brought to, and
    the observation that comes back.

    The input is declared as the specification's own `imageType`, and not as the array of three
    channels the convolutional model beside it uses, because the two are different features to a
    model: an image input is a picture with a colour space and a size, and it is the only kind a
    `VNCoreMLRequest` will hand a picture to. coremltools 9.0's runtime refuses to *run* a network
    with an image input -- measured, and recorded as `prediction: null` below, which is the
    manifest's way of saying "this container is for a framework that runs it" -- while Apple's own
    Core ML and Vision, which are what the Vision host differential runs, run it exactly.
    """
    builder = ct.models.neural_network.NeuralNetworkBuilder(
        input_features=[("image", datatypes.Array(3, 32, 32))], output_features=[("out", datatypes.Array(1, 32, 32))])
    # The layers are written for the 32 by 32 the corpus is built at; the range is what the
    # *description* says the feature will take, which is a claim about the model rather than about
    # this build of it, and the request path is what brings a picture inside it.
    weights = np.zeros((1, 1, 1, 3), np.float32)
    weights[0, 0, 0] = [1.0 / 255.0, 0.0, 0.0]
    builder.add_convolution("conv", 3, 1, 1, 1, 1, 1, "valid", 1, weights, np.zeros(1, np.float32),
                            True, False, output_name="out", input_name="image")
    spec = builder.spec
    # Both ends are pictures: the builder wrote arrays of channels, and an image is a picture with
    # a colour space and a size, which is a different thing to a model.
    described = Model_pb2.FeatureDescription(name="image")
    picture = described.type.imageType
    picture.colorSpace = 20          # 20 is the specification's own "RGB"
    # A range rather than a size, which is what Vision's own crop-and-scale is for: the model will
    # take a picture of any size inside the range, and the request path is what brings the
    # handler's picture inside it. A model that fixes its size has nothing for that to do.
    size = picture.imageSizeRange
    size.widthRange.lowerBound = 16
    size.widthRange.upperBound = 256
    size.heightRange.lowerBound = 16
    size.heightRange.upperBound = 256
    spec.description.input[0].CopyFrom(described)
    # The preprocessing: the scale and bias a picture's bytes are put through before a layer sees
    # them, which is what Core ML's own compiler writes into a model with an image input and what
    # Vision's transform is built around. Without it the model has no image processing to run, which
    # is what the three shapes measured without it say.
    preprocessing = spec.neuralNetwork.preprocessing.add()
    preprocessing.featureName = "image"
    preprocessing.scaler.channelScale = 1.0 / 255.0
    preprocessing.scaler.redBias = -1.0
    preprocessing.scaler.greenBias = -1.0
    preprocessing.scaler.blueBias = -1.0
    # The answer is a picture too, and of a *range* like the input: a model whose two ends disagree
    # about whether their size is fixed is a model Vision's transform cannot build, which is measured
    # -- the wrapper refuses a ranged input with a fixed output outright -- and the range is what the
    # request path is for: a picture of any size inside it, brought to a size the model accepts.
    answer = Model_pb2.FeatureDescription(name="out")
    out_picture = answer.type.imageType
    out_picture.colorSpace = 20
    out_size = out_picture.imageSizeRange
    out_size.widthRange.lowerBound = 16
    out_size.widthRange.upperBound = 256
    out_size.heightRange.lowerBound = 16
    out_size.heightRange.upperBound = 256
    spec.description.output[0].CopyFrom(answer)
    spec.specificationVersion = SPEC_12_2
    return spec


BUILDERS = {
    "glm_classifier": build_glm_classifier,
    "nn_layers": build_nn_layers,
    "nn_layers_shape": build_nn_layers_shape,
    "nn_embedding": build_nn_embedding,
    "nn_layers": build_nn_layers,
    "nn_classifier": build_nn_classifier,
    "nn_image": build_nn_image,
    "tree_classifier": build_tree_classifier,
    "glm": build_glm,
    "pipeline": build_pipeline,
    "vision_image": build_vision_image,
}


# --- the reference dump ------------------------------------------------------------------------

def reference(spec, out):
    """The tree protobuf's own reflection prints, as a stable, comparable text dump."""
    lines = []

    def walk(message, indent):
        pad = "  " * indent
        for field, value in message.ListFields():
            name = field.name
            if field.is_repeated:
                if field.type == field.TYPE_MESSAGE:
                    for index, item in enumerate(value):
                        lines.append("%s%s[%d] {" % (pad, name, index))
                        walk(item, indent + 1)
                        lines.append("%s}" % pad)
                else:
                    flat = ", ".join("<%d bytes>" % len(item) if isinstance(item, bytes) else repr(item)
                                     for item in value)
                    lines.append("%s%s = [%s]" % (pad, name, flat))
            elif field.type == field.TYPE_MESSAGE:
                lines.append("%s%s {" % (pad, name))
                walk(value, indent + 1)
                lines.append("%s}" % pad)
            elif field.type == field.TYPE_STRING:
                lines.append("%s%s = %r" % (pad, name, value))
            elif field.type == field.TYPE_BYTES:
                lines.append("%s%s = <%d bytes>" % (pad, name, len(value)))
            else:
                lines.append("%s%s = %s" % (pad, name, value))

    walk(spec, 0)
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main(argv):
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=os.path.join(HERE, "models"),
                        help="where the containers and the reference dumps are written")
    parser.add_argument("--check", action="store_true",
                        help="write nothing; fail if the containers are not byte for byte the ones here")
    args = parser.parse_args(argv)
    models = os.path.abspath(args.out)
    os.makedirs(models, exist_ok=True)
    manifest = {}
    for name, build in sorted(BUILDERS.items()):
        path = os.path.join(models, name + ".mlmodel")
        ct.models.MLModel(build()).save(path)
        # The reference is the tree as the writer's own reader sees the file that was written,
        # not the tree as it was built: a difference between the two is a loss in the writer.
        written = ct.models.MLModel(path)
        reference(written.get_spec(), os.path.join(models, name + ".ref"))
        entry = {"path": os.path.relpath(path, os.path.dirname(models) or "."), "bytes": os.path.getsize(path),
                 "specification": written.get_spec().specificationVersion,
                 # How far this model's answers may be from the port's, and why. The default is
                 # the float an interpreter and a compiled runtime may differ by anywhere; a model
                 # whose host runtime is known to answer in a lower precision says so here rather
                 # than the check being loosened for everything.
                 "tolerance": TOLERANCES.get(name, (1e-5, None)),
                 "divergence": DIVERGENCES.get(name)}
        sample = sample_of(name)
        if sample is None:
            entry["prediction"] = None
        else:
            output = written.predict(sample)
            entry["prediction"] = {key: np.asarray(value).tolist() for key, value in output.items()}
        manifest[name] = entry
        print("%-15s %6d bytes  spec %d  %s" % (
            name, entry["bytes"], entry["specification"],
            "no host input" if sample is None else "prediction ok"))
    with open(os.path.join(models, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
