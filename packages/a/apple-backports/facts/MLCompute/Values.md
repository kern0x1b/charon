# What MLCompute is made of, and where each answer came from

MLCompute.framework of iOS 14 and macOS 11, in the version the newest SDK still declares
(SDK 16.4, which is what this port builds against; the corpus of SDK 26.2 names the same
seventy-eight classes and members for this framework, and its 26.2 headers dropped four of the
factories of iOS 14, which is written down below). Nothing here is a retyping of Apple's headers:
the declarations an application compiles against are Apple's, read from the SDK, and only the
behaviour is the port's.

This file is the reasoning behind the answers the registry gives, and the other five files in this
directory are the measurement behind each family:

| File | What it covers |
| --- | --- |
| `Values.md` | the thirteen functions of `MLCTypes.h`, `MLCPlatform` and the values of the enumerations |
| `Tensors.md` | `MLCTensorDescriptor`, `MLCTensorData`, `MLCTensorOptimizerDeviceData`, `MLCTensor`, `MLCTensorParameter` |
| `Device.md` | `MLCDevice`, and what a machine with no GPU and no Neural Engine answers |
| `Layer.md` | `MLCLayer`, the number a layer has before it is in a graph, and `+supportsDataType:onDevice:` |
| `Descriptors.md` | the ten descriptor classes, and the two host defects the port keeps |

## How each answer was measured

Every value in this delivery was read off the host's own MLCompute, on macOS, through Mac
Catalyst, by asking it and writing down what it said. `tests/backports/host/mlcompute` is that
measurement turned into a check: one program of 377 cases, compiled once beside the framework and
once beside the port's four translation units with every name they define renamed, and the two
runs compared line by line. `sh tests/backports/host/mlcompute/run.sh` runs it.

Three cases are meant to differ and run.sh says so every time: `+[MLCDevice gpuDevice]`,
`+[MLCDevice aneDevice]` and `+[MLCDevice deviceWithType:MLCDeviceTypeGPU]`. The host has a Metal
device and a Neural Engine; iOS 6.1.3 has neither, and each side answers as a machine with what it
has. `Device.md` has the table.

## What is not carried in this delivery

The framework is delivered in three families, and this is the first: everything MLCompute is *built
out of* - the tensors, the device, the layer base, the ten descriptors and the functions that name
an enumeration's cases. 248 of the corpus's 564 missing rows for this framework.

The other two are the layers with the arithmetic behind them, and the graphs, optimizers and
training that drive them. They are listed in the same registry file with the rows they are, so the
owner can see what is and is not there: `registry/MLCompute/ios14layers.json` and
`ios14graphs.json` name what the next two families carry, and the code that carries them is not in
this delivery.

Four factories of iOS 14 are not in the 26.2 headers and are not carried: the one-argument
`+[MLCTensorDescriptor descriptorWithShape:]`, and `+[MLCTensor tensorWithShape:fillWithData:]` and
`+[MLCTensor tensorWithShape:data:]`. The corpus of SDK 26.2 does not name them, the host's
framework answers `unrecognized selector` for the descriptor one (measured) and does not implement
the other two (measured: the class does not respond to them), so there is nothing to carry. The
two-argument `+[MLCTensorDescriptor descriptorWithShape:dataType:]` that iOS 14 declared beside
`descriptorWithShape:` is in the corpus, is carried, and is what the differential compares.

`MLCRMSPropOptimizer` was in iOS 14 and is in neither the corpus of SDK 26.2 nor the current
headers: the framework took it away, and the registry says so with a `removed` entry rather than
backporting an API that modern iOS no longer has.

## The enumerations

A case of an enumeration is a value the compiler writes into the program. There is no symbol for
it at run time, so the registry gives it no entry - the rule is in `registry/README.md` - and the
values are the ones Apple's own headers carry, read from the SDK this port builds against. The
fourteen cases of iOS 14.5 and 15.0 that the corpus asks about are
`MLCActivationTypeHardSwish`, `MLCActivationTypeClamp`,
`MLCArithmeticOperationMultiplyNoNaN`, `MLCArithmeticOperationDivideNoNaN`,
`MLCArithmeticOperationMin`, `MLCArithmeticOperationMax`, `MLCReductionTypeL1Norm`,
`MLCReductionTypeAny`, `MLCReductionTypeAll`, `MLCDataTypeFloat16`, `MLCDataTypeInt8`,
`MLCDataTypeUInt8`, `MLCDeviceTypeANE` and `MLCExecutionOptionsPerLayerProfiling`. They compile
for 6.1.3 against the lifted headers, which is what the ledger's `header-ok` says, and no lift
change is owed for them: the lift lowers `API_AVAILABLE(ios(15.0))` to the target, so a case the
newest header declares is declared for this release too.
