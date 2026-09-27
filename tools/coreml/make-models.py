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

# The specification version a model declares, by the values the CoreML specification gives:
# 1 came with 11.0, 2 with 11.1, 3 with 11.2, 4 with 12.0, 5 with 12.2, 6 with 13.0.
SPEC_11_2, SPEC_12_0, SPEC_12_2, SPEC_13_0 = 3, 4, 5, 6

# A host input per model. None records that the container is written and referenced but there
# is no host input for it -- the image model wants a PIL image, and this host has none.
# Each sample matches the shape the model declares: the dense classifier's input is a vector
# of three, not a batch of them, and the pipeline's scaler takes one double at a time.
SAMPLES = {
    "nn_classifier": {"x": np.array([0.5, -0.25, 1.0], np.float32)},
    "nn_image": None,
    "tree_classifier": {"a": [0.25, 1.0, 3.0, -2.0], "b": [1.0, 3.0, 0.0, 2.0]},
    # The tree's four samples walk every branch: below and above each of the two thresholds.
    "glm": {"x": [-1.5, 0.0]},
    "pipeline": {"x": [2.0]},
}


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
    """A convolutional classifier over an image input: one conv, a ReLU and a max pool, with
    the preprocessing that says the input is an image and gives its scale and per-channel bias.
    A neural network's array input is a vector or an image-like array, so the input is three
    channels of 8 by 8 with no batch dimension."""
    builder = ct.models.neural_network.NeuralNetworkBuilder(
        input_features=[("img", datatypes.Array(3, 8, 8))], output_features=[("p", datatypes.Array(4))])
    weights = (np.arange(4 * 3 * 3 * 3, dtype=np.float32).reshape(4, 3, 3, 3) / 97.0) - 0.5
    builder.add_convolution("conv", 3, 4, 3, 3, 1, 1, "valid", 1, weights, np.zeros(4, np.float32),
                            True, False, output_name="c", input_name="img")
    builder.add_activation("relu", "RELU", "c", "cr")
    builder.add_pooling("pool", 2, 2, 2, 2, "MAX", "VALID", input_name="cr", output_name="p")
    spec = builder.spec
    spec.description.input[0].CopyFrom(vector("img", [3, 8, 8]))
    spec.description.output[0].CopyFrom(vector("p", [4]))
    builder.set_pre_processing_parameters(image_input_names=["img"], image_scale=1.0 / 255.0,
                                          red_bias=-1.0, green_bias=-1.0, blue_bias=-1.0)
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


BUILDERS = {
    "nn_classifier": build_nn_classifier,
    "nn_image": build_nn_image,
    "tree_classifier": build_tree_classifier,
    "glm": build_glm,
    "pipeline": build_pipeline,
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
                 "specification": written.get_spec().specificationVersion}
        sample = SAMPLES[name]
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
