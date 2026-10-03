# MLCompute's graph: a node, and what a node answers

Measured on this host's own MLCompute, macOS 27.0 build 26A428 (M4 Pro), by
`.agent-work/runs/probe/mlc-graph.m`, and held to again by `tests/backports/host/mlcompute/graph-cases.m`,
which compiles `MLCGraph14.m` beside the port's other six objects and beside the framework and compares the
two runs. Nothing here is read out of a header comment: where the header says nothing, the run is what
decided.

## The device is nil, and a bind does not change that

`+[MLCGraph graph].device` is nil on a graph nothing has been added to, and it is nil again on a graph that
`bindAndWriteData:forInputs:toDevice:synchronous:` has just been given the CPU device. So the device a
graph runs on is set by a compile, and this port's is nil until one. The property is not "the CPU device by
default": measured, it is nil.

## A node's result, and a layer that cannot take the sources it was given

| what was asked | what the host answers |
| --- | --- |
| `nodeWithLayer:source:` over a ReLU and a 2x3 tensor | a 2x3 `MLCDataTypeFloat32` tensor |
| `nodeWithLayer:sources:` over the same layer and two tensors | **nil** |
| `nodeWithLayer:sources:` over three tensors | **nil** |
| `nodeWithLayer:sources:disableUpdate:YES` over two | **nil** |
| `nodeWithLayer:sources:lossLabels:` over two | **nil** |
| `graph.layers` before any node, and after those five | `0`, and **`1`** |

So a node is one layer, one source, one result, and a layer that takes more sources than it has answers nil
rather than a tensor of a guessed shape. And `layers` holds each layer **once**: five nodes made over one
ReLU answer a graph with one layer in it. `sourceTensorsForLayer:` and `resultTensorsForLayer:` answer one
tensor each for that layer, and an empty array for a layer no node uses.

## The shape operations do not check, and one of them refuses

| what was asked over a 2x3 float32 tensor | what the host answers |
| --- | --- |
| `concatenateWithSources:@[a, b] dimension:1` | 2x6 |
| `concatenateWithSources:@[a, b] dimension:0` | 4x3 |
| `concatenateWithSources:@[a, b] dimension:3` | **an `NSRangeException`**, from `-[MLCConcatenationLayer resultTensorFromSources:]` indexing the sources with the dimension |
| `reshapeWithShape:@[@6]` / `@[@3, @2]` | 6, and 3x2 |
| `reshapeWithShape:@[@7]` over six elements | **a 7-element tensor** - the graph does not check the count |
| `reshapeWithShape:nil` | **an `NSRangeException`**: `+[MLCTensorDescriptor descriptorWithShape:stride:dataType:]` reaches `-[__NSArray0 objectAtIndex:]` |
| `transposeWithDimensions:@[@0, @1]` / `@[@1, @0]` | 2x3, and 3x2 |
| `transposeWithDimensions:@[@0]` over a rank-2 tensor | **nil** |
| `transposeWithDimensions:@[@0, @2, @1]` over 2x3x4 | 2x4x3 |

A permutation that is not a permutation of the rank is nil; a shape the caller asked for is the shape the
caller gets. The two exceptions are recorded and not asked, because a probe that raises is a probe that
stops - and the harness's cases would stop with it.

## A split

| what was asked over a 2x3 tensor | what the host answers |
| --- | --- |
| `splitWithSource:splitCount:2 dimension:1` | two tensors, **2x2** and **2x1** |
| `splitWithSource:splitCount:3 dimension:0` (extent 2) | **two** tensors, 1x3 and 1x3 |
| `splitWithSource:splitSectionLengths:@[@1, @5] dimension:1` (extent 3) | two tensors, **2x1** and **2x5** |
| `splitWithSource:splitCount:2 dimension:1` over 2x3x4 | two tensors, 2x2x4 and 2x1x4 |

Two rules, both measured and both counter-intuitive enough to be worth stating: **the remainder goes to
the first part** (an extent of 3 into two gives 2 then 1, not 1 then 2), and **the count is capped at the
extent** (an extent of 2 into three gives two parts, not three and not an error). The section lengths are
not checked against the extent either: lengths summing to six over an extent of three answer extents of one
and five.

## What a bind answers

| what was asked | what the host answers |
| --- | --- |
| `bindAndWriteData:forInputs:toDevice:synchronous:` with a name the graph never knew | **YES** |
| the same with an empty dictionary on both sides | **YES** |
| the same with `forInputs:` nil | **NO** |
| `graph.device` straight afterwards | **nil** |

So what decides it is whether the caller's inputs are there at all, not whether every name resolves, and a
bind does not give the graph its device.

## `summarizedDOTDescription`, character for character

```digraph MLCGraph {
 node [style=filled];
}
```

42 characters on this host, with nodes in the graph and without. The nodes are not in it: the host's is a
summary, and this is the summary.

## The two raises, recorded and not asked

* `concatenateWithSources:dimension:` with a dimension at or past the rank is an `NSRangeException` inside
  `-[MLCConcatenationLayer resultTensorFromSources:]`, which indexes the sources array with the dimension.
* `reshapeWithShape:` with a nil or empty shape is an `NSRangeException` inside
  `+[MLCTensorDescriptor descriptorWithShape:stride:dataType:]`, reached through
  `-[MLCReshapeLayer resultTensorFromSources:]`.

A release that raises is a release that has no answer to compare, so the port's `nil` in those two places is
a difference of this port's own and not a match: they are named here rather than asked.

## Not asked, and why

`MLCInferenceGraph` and `MLCTrainingGraph` are the next family - fifteen and twenty-six members - and the
port carries neither yet, so a case that asks one of them on the port's side would answer nil and be a
difference where there is nothing to compare. The one case that would have asked an inference graph's
`deviceMemorySize` (measured: 0 before a compile) is left out for that reason and is in this family's place
when those two classes are written.

## The inference and training graphs: measured, not yet written

`.agent-work/runs/probe/mlc-inference.m`, kept in the tree as `tests/backports/host/mlcompute/probes/`,
measures both. What it answers on this host, over one graph with one ReLU node over a 2x3 float32 tensor:

| | `MLCInferenceGraph` | `MLCTrainingGraph` |
| --- | --- | --- |
| `addInputs:`, with a name the graph knows, one it does not, an empty dictionary, or nil | **YES, YES, YES, YES** | - |
| `addInputs:lossLabels:` and `addInputs:lossLabels:lossLabelWeights:` | - | **YES** and **YES** |
| `addOutputs:`, known, unknown, nil | **YES, YES, YES** | **YES** |
| `linkWithGraphs:`, empty, itself, another | **YES, YES, YES** | **NO, NO, NO** |
| `compileWithOptions:device:` | **YES**, and **YES** again on a second call, and **YES** with a nil device | **NO** |
| `compileOptimizer:` | - | **NO** |
| `deviceMemorySize` before a compile / after | 0 / **24** | 0 / **24** |
| `stopGradientForTensors:`, known and unknown | - | **YES** and **YES** |
| `setTrainingTensorParameters:` | - | **YES** |
| `bindOptimizerData:deviceData:withTensor:`, known and unknown tensor | - | **YES** and **YES** |
| `executeForward…`, `executeGradient…`, `executeOptimizerUpdate…`, the two `executeWithInputsData:…` forms | **YES** | **NO** for every one of them |
| `gradientTensorForInput:`, for the input, for an output, for an unknown tensor | - | **nil, nil, nil** |
| `sourceGradientTensorsForLayer:` / `resultGradientTensorsForLayer:` | - | **1** / **0** |
| `gradientDataForParameter:layer:` | - | **nil** |
| `allocateUserGradientForTensor:`, known and unknown | - | **nil** and **nil** |
| `optimizer` of a graph made with one / with nil | - | kept / **nil** |
| `compileWithOptions:device:` and `executeForward…` with a nil loss layer and a nil optimizer | - | **NO** and **NO** |

So the shape of both classes is measured and is not a guess: the inference graph answers YES to everything it
is asked and the training graph answers NO to everything that needs an engine, and the two are different
answers rather than one of them being unimplemented.

**`deviceMemorySize` is pinned down, and it is none of the three hypotheses.**
`tests/backports/host/mlcompute/probes/device-memory.m` builds graphs where the input's bytes, the output's
bytes and a sum over both are three different numbers. Every operand in it is a tensor the probe makes, never
one a node made, because a graph's own result asked for as an output raised inside the host on the earlier
sweep. What this host answers, over a graph with a single node whose result holds six `MLCDataTypeFloat32`
elements - twenty-four bytes - and over one whose result holds one - four bytes:

| the graph | before a compile | after |
| --- | --- | --- |
| six elements, nothing bound | 0 | **24** |
| six elements, one input of six | 24 | **24** |
| six elements, one input of **one** | 24 | **24** |
| six elements, one output of six | 24 | **24** |
| six elements, an input of one **and** an output of six | 24 | **24** |
| six elements, two inputs of six | 24 | **24** |
| six elements, one input of six and **two** outputs of six | 24 | **24** |
| six elements, an input of one and outputs of six and one | 24 | **24** |
| **one element**, an input of one and an output of one | 0 | **4** |
| one element, nothing bound | 4 | **4** |
| one element, an input of six | 4 | **4** |
| one element, an input of six and an output of one | 4 | **4** |
| two graphs linked, one bound to an input of one and the other to six | 24 and 24 | **24 and 24** |

Two rules, and both are measured:

* **It is the byte width of a tensor the graph's OWN nodes produce.** The caller's bindings do not move it at
  all: an input of one element and an input of six over the same six-element graph are the same 24, two
  outputs of six are the same 24, and a graph whose node holds one element is 4 whatever is bound to it and
  whatever a link adds. So the input's bytes, the output's bytes and a sum over both are **all three refuted**.
* **It is 0 until the graph has been compiled** - or until another graph in the same process has been, which
  is a lazy global of the framework's own and is measured rather than argued: read in order, a six-element
  graph answers 0, 0 and then 24 after its compile, a one-element graph answers 0 and then 4 after its
  compile, and a **third** six-element graph made afterwards and never compiled answers **24 on its first
  read**. So "before a compile" means "before anything in the process has been compiled".

**What is still not measured, and is not needed for the two classes to be written:** whether a graph of
**several** nodes answers the largest node's bytes or the sum of theirs. A second node over a graph's own
result raises inside the host (`-[__PlaceholderDictionary initWithObjects:forKeys:count:]`), so every graph
above has exactly one node. The port therefore computes the sum over its nodes' results and the facts name
that as the one rule this measurement does not decide - it is a choice between two readings of a property
whose multi-node value is unmeasured, and it is written down rather than passed off as measured.
