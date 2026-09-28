// model.swift — the port's `.mlmodel` writer, read back by an implementation that is not this port's.
//
// **What this reaches and what it does not.** The writer emits Core ML's protobuf over the schema
// vendored in `packages/c/createml/proto/`, and the check below is that **coremltools 9.0** — a
// protobuf implementation written by neither this port nor Swift's Core ML — parses the file and every
// field in it round-trips. That proves the *schema and the encoding*.
//
// It does **not** prove the arithmetic. A load and a predict is the only check that does, and on this
// machine's CoreML Swift surface it is not reachable: `MLModel.prediction(fromFeatures:options:)` is
// `unavailable in macOS`, `MLModel.prediction(from:)` takes `[String: MLTensor]` and is `async`, and
// `MLTensor(shape:scalars:)` trips a compiler crash ("failed to produce diagnostic"). So the prediction
// comparison is **not** in this suite and no claim is made about it; `facts/CreateML/Export.md` says
// so, and the writer's own comment says which estimators it covers and which it refuses.

import Foundation
import PortProto

var checks = 0
var failures = 0

func checkEqual<T: Equatable>(_ what: String, _ a: T, _ b: T) {
    check(what, a == b, "the port answered \(a)")
}

func check(_ what: String, _ equal: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !equal {
        failures += 1
        print("FAIL \(what)\(detail().isEmpty ? "" : ": \(detail())")")
    }
}

/// The port's own model: `y = 3 + 2*x1 - 1.5*x2`, as the schema's protobuf.
let coefficients: [Float] = [2.0, -1.5]
let intercept: Float = 3.0
let writer = ModelWriter.model(featureName: "x", outputName: "prediction",
                              weights: coefficients, bias: intercept,
                              author: "charon CreateML", version: "1.0",
                              description: "the port's linear regressor")
let path = NSTemporaryDirectory() + "/createml-model-\(getpid()).mlmodel"
do {
    try Data(writer.bytes).write(to: URL(fileURLWithPath: path))
} catch {
    print("FAIL the writer could not write its model: \(error)")
    failures += 1
    exit(1)
}

// The round trip through this package's own reader first: a writer whose reader cannot read it is
// a writer that emits the wrong bytes, whatever any other implementation thinks.
do {
    let fields = try ProtoReader.fields(writer.bytes)
    var seen = [Int: Int]()
    for (number, _) in fields { seen[number, default: 0] += 1 }
    check("the model's own reader sees the top-level fields", seen.isEmpty == false,
          "the port's reader found \(seen.count) distinct field numbers")
    var specVersion: Int?
    var description: [UInt8]?
    var network: [UInt8]?
    for (number, field) in fields {
        switch number {
        case 1: specVersion = field.intValue
        case 2: description = field.bytesValue
        case 303: network = field.bytesValue
        default: break
        }
    }
    checkEqual("specificationVersion is the one the SDK declares", specVersion, ModelWriter.specificationVersion)
    check("the description is there", description != nil)
    check("the oneof is neuralNetworkRegressor, field 303", network != nil)

    // And inside the network: one layer, whose oneof is innerProduct, field 140.
    var layers = 0
    var innerProducts = 0
    var inputChannels: Int?
    var weightValues: [Float] = []
    var biasValues: [Float] = []
    var hasBias: Bool?
    for (number, field) in try ProtoReader.fields(network ?? []) {
        guard number == 1, let layerBytes = field.bytesValue else { continue }
        layers += 1
        for (layerNumber, layerField) in try ProtoReader.fields(layerBytes) {
            if layerNumber == 140, let inner = layerField.bytesValue {
                innerProducts += 1
                for (innerNumber, innerField) in try ProtoReader.fields(inner) {
                    switch innerNumber {
                    case 1: inputChannels = innerField.intValue
                    case 10: hasBias = innerField.boolValue
                    case 20, 21:
                        let name = innerNumber == 20 ? "weights" : "bias"
                        for (_, blob) in try ProtoReader.fields(innerField.bytesValue ?? []) where blob.floatValues != nil {
                            if name == "weights" { weightValues = blob.floatValues ?? [] }
                            if name == "bias" { biasValues = blob.floatValues ?? [] }
                        }
                    default: break
                    }
                }
            }
        }
    }
    checkEqual("one layer", layers, 1)
    checkEqual("whose oneof is innerProduct", innerProducts, 1)
    checkEqual("with the feature count as its input channels", inputChannels, coefficients.count)
    checkEqual("and the weights in order", weightValues, coefficients)
    checkEqual("and the intercept", biasValues, [intercept])
    checkEqual("and hasBias set", hasBias, true)
} catch {
    print("FAIL the writer's own reader could not read the model: \(error)")
    failures += 1
}

// The independent read, through coremltools, is a *process* and not a library here, so the file is
// left on disk with a known name for the caller to read, and this suite says so rather than claiming
// a check it did not make.
let readBack = Process()
readBack.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
let scriptPath = NSTemporaryDirectory() + "/createml-read-\(getpid()).py"
readBack.arguments = [scriptPath]
var script = """
import coremltools as ct, sys
m = ct.models.MLModel("\(path)", skip_model_load=True)
s = m.get_spec()
nn = s.neuralNetworkRegressor
ip = nn.layers[0].innerProduct
shape = s.description.input[0].type.multiArrayType
# `|` and not a space: the list literals contain spaces, and splitting on whitespace silently
# shifted every field after the third.
print("|".join([str(s.specificationVersion), s.WhichOneof("Type"),
      ",".join(d.name for d in s.description.input), ",".join(d.name for d in s.description.output),
      ",".join(str(v) for v in shape.shape), str(shape.dataType),
      str(ip.inputChannels), str(ip.outputChannels), str(bool(ip.hasBias)),
      ",".join(str(round(v, 6)) for v in ip.weights.floatValue),
      ",".join(str(round(v, 6)) for v in ip.bias.floatValue)]))
"""
try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
let pipe = Pipe()
readBack.standardOutput = pipe
readBack.standardError = FileHandle.nullDevice
do {
    try readBack.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    readBack.waitUntilExit()
    let text = String(data: data, encoding: .utf8) ?? ""
    let fields = text.split(separator: "\n").last.map { $0.split(separator: "|").map(String.init) } ?? []
    check("coremltools 9.0 read the port's model", fields.count >= 11,
          "it answered " + text)
    if fields.count >= 11 {
        checkEqual("with the specification version the SDK declares",
                   fields[0], String(ModelWriter.specificationVersion))
        checkEqual("as a neuralNetworkRegressor", fields[1], "neuralNetworkRegressor")
        checkEqual("one input, named", fields[2], "x")
        checkEqual("one output, named", fields[3], "prediction")
        checkEqual("of the shape the weights need", fields[4], "1,2")
        checkEqual("and Core ML's single-precision array type", fields[5], "65568")
        checkEqual("with the feature count as input channels", fields[6], "2")
        checkEqual("and one output channel", fields[7], "1")
        checkEqual("and a bias", fields[8], "True")
        checkEqual("and the weights in order", fields[9], "2.0,-1.5")
        checkEqual("and the intercept", fields[10], "3.0")
    }
} catch {
    check("coremltools 9.0 could be run", false, "\(error)")
}
try? FileManager.default.removeItem(atPath: path)
try? FileManager.default.removeItem(atPath: scriptPath)

print("\(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
