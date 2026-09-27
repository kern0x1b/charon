# The thirty layers: measured, and not yet carried

This file is the measurement the layers family starts from. Every number in it was read off the
host's own MLCompute on macOS through Mac Catalyst, the same way `Tensors.md` and `Descriptors.md`
were, and none of the thirty layer classes is in the delivery the registry describes: the code that
carries them is `MLCLayers14.m` and the engine beside it, and neither is written yet. Nothing in
`registry/MLCompute/ios14values.json` claims a layer.

What is here is what a program reads back, so that the implementation is written against the
host's answers rather than against the header's comments.

## The name each factory gives its layer

Measured for every factory, all thirty. It is the class's own name with `MLC` and `Layer` off, and
four of them shortened, two of them the full name:

| Factory | `label` |
| --- | --- |
| `+[MLCSelectionLayer layer]` | Selection |
| every `MLCActivationLayer` factory | Activation |
| `+[MLCArithmeticLayer layerWithOperation:]` | Arithmetic |
| `+[MLCComparisonLayer layerWithOperation:]` | Compare |
| `+[MLCConcatenationLayer layer]`, `+layerWithDimension:` | Concat |
| `+[MLCConvolutionLayer layerWithWeights:biases:descriptor:]` | Convolution |
| `+[MLCDropoutLayer layerWithRate:seed:]` | Dropout |
| `+[MLCEmbeddingLayer layerWithDescriptor:weights:]` | Embedding |
| `+[MLCFullyConnectedLayer layerWithWeights:biases:descriptor:]` | FullyConnected |
| `+[MLCGatherLayer layerWithDimension:]` | Gather |
| `+[MLCGramMatrixLayer layerWithScale:]` | GramMatrix |
| `+[MLCPaddingLayer layerWith...Padding:]` | Padding |
| `+[MLCPoolingLayer layerWithDescriptor:]` | Pooling |
| `+[MLCReductionLayer layerWithReductionType:...]` | Reduction |
| `+[MLCReshapeLayer layerWithShape:]` | Reshape |
| `+[MLCScatterLayer layerWithDimension:reductionType:]` | Scatter |
| `+[MLCSliceLayer sliceLayerWithStart:end:stride:]` | Slice |
| `+[MLCSoftmaxLayer layerWithOperation:]` | Softmax |
| `+[MLCSplitLayer layerWithSplitCount:dimension:]` | Split |
| `+[MLCTransposeLayer layerWithDimensions:]` | Transpose |
| `+[MLCUpsampleLayer layerWithShape:]` | Upsampling |
| `+[MLCLossLayer ...]`, `+[MLCYOLOLossLayer layerWithDescriptor:]` | Loss |
| `+[MLCBatchNormalizationLayer layerWithFeatureChannelCount:...]` | BatchNorm |
| `+[MLCInstanceNormalizationLayer layerWithFeatureChannelCount:...]` | InstanceNorm |
| `+[MLCGroupNormalizationLayer layerWithFeatureChannelCount:groupCount:...]` | GroupNorm |
| `+[MLCLayerNormalizationLayer layerWithNormalizedShape:...]` | LayerNorm |
| `+[MLCLSTMLayer layerWithDescriptor:inputWeights:hiddenWeights:biases:]` | LSTM |
| `+[MLCMatMulLayer layerWithDescriptor:]` | MatMul |
| `+[MLCSelectionLayer layer]` | Selection |

An initialised layer of any class has no name at all, measured for all of them.

## What the factories keep, and what they refuse

**`MLCConvolutionLayer` validates the weights against the descriptor and keeps nothing when they do
not match.** A 3 by 3 convolution from 4 channels to 5 wants weights of the shape
`convolutionWeightsDescriptorWithWidth:3 height:3 inputFeatureChannelCount:4 outputFeatureChannelCount:5`
gives - 1, 20, 3, 3 - and biases of `convolutionBiasesDescriptorWithFeatureChannelCount:5` - 1, 5, 1, 1.
Handed weights of some other shape it answers a layer with **no descriptor, no weights, no biases and
no weights parameter** (measured), and a layer with no biases keeps none and has no biases parameter.
`MLCFullyConnectedLayer` and `MLCEmbeddingLayer` do *not* check: the same mismatched weights are kept
along with the descriptor, and both make their parameters (measured).

**The three normalizations want their parameters in the shape the framework's own per-channel
descriptor gives**, which is 1, channels, 1, 1 (measured: with that shape a batch normalization of 4
channels keeps its mean, variance, beta and gamma, makes a parameter for the beta and for the gamma,
and answers a variance epsilon of what it was given and a **momentum of 0.99**). With a one
dimensional or a 1, 1, 1, 4 parameter it answers a layer of nothing - no channels, no tensors, a
momentum and an epsilon of zero - and the three-tensor form of the instance normalization, which
passes no mean and no variance at all, raises `NSRangeException` on this release of the framework
(measured). An instance normalization made with a beta and a gamma and no mean answers no mean and
no variance, a momentum of 0.99, and keeps the two it was given. The group normalization needs a
group count, which it has no default for.

**`MLCLayerNormalizationLayer` wants a one-dimensional beta and gamma**, one element per normalized
shape: with those it keeps the shape, the two and the epsilon, and is named LayerNorm; with the
per-channel shape it keeps nothing at all (measured both).

**`MLCLSTMLayer` supplies its own gate activations** - four sigmoids and an output activation of
none - when the shorter factory is given no gates, makes a parameter for every weight and every bias,
and has no peepholes and no peephole parameters (measured). The longest form, the one that takes
peephole weights and both activation arrays, answers a layer of nothing for weights it does not
accept (measured), so the rule that accepts and refuses them is the open question of the layers
family.

**`MLCMultiheadAttentionLayer` refused every weight set tried**, answering no descriptor, no weights
and no parameters (measured), so the rule for what it accepts is likewise open. Its `weights`,
`biases` and `attentionBiases` are arrays of tensors and its parameters are arrays of parameters,
whatever shape they are (measured from the header and from a layer that kept them).

## The values the layers read back

Measured and small enough to write down whole:

| Layer | Measured |
| --- | --- |
| `MLCSoftmaxLayer` | the operation asked for; the dimension is 1 unless another is given |
| `MLCReductionLayer` | `layerWithReductionType:dimension:` answers `dimensions` of the one dimension it was given, and `dimension`; `layerWithReductionType:dimensions:` answers the array and a `dimension` of its first entry |
| `MLCSliceLayer` | the start and end as given; a nil stride answers 1, and a stride of 2 is kept |
| `MLCSplitLayer` | `layerWithSplitCount:dimension:` answers the count and the dimension and **no** section lengths; `layerWithSplitSectionLengths:dimension:` answers the lengths and a count of how many there are |
| `MLCUpsampleLayer` | the shape as given, the nearest-neighbour mode and no corner alignment unless the longer factory is used |
| `MLCPaddingLayer` | the padding array is read as **top, bottom, left, right**: `@[@1,@2,@3,@4]` answers top 1, bottom 2, left 3, right 4; a two-entry array answers 2 in each of the four; a constant padding keeps its value |
| `MLCDropoutLayer` | the rate and the seed as given |
| `MLCScatterLayer` | the dimension, and a reduction of none or sum; a reduction of anything else answers no layer (measured) |
| `MLCGatherLayer`, `MLCConcatenationLayer` | the dimension, the concatenation layer's default being 1 |
| `MLCGramMatrixLayer` | the scale as given |
| `MLCArithmeticLayer`, `MLCComparisonLayer` | the operation as given |
| `MLCLossLayer` | the descriptor as given, and the weights tensor; the nine convenience factories each answer their own loss type with the reduction and the arguments they were given, and the defaults the descriptor carries |

## What is open for the layers family

Three things this measurement did not settle, all of which the family's own differential will have
to:

1. the shape rule `MLCConvolutionLayer` validates its weights against, beyond "the channel count must
   be the descriptor's output times input" - the two cases measured agree with that and nothing else
   was tried;
2. what `MLCMultiheadAttentionLayer` accepts;
3. what the longest `MLCLSTMLayer` factory accepts.

None of them is guessed at in the delivered code, because none of them is in it.
