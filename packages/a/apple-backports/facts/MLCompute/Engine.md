# What the framework computes, measured, so the engine can be written against it

Every number here came out of `tests/backports/host/mlcompute/engine.m`, which asks the host's own
MLCompute through an inference graph and prints what comes out. `sh tests/backports/host/mlcompute/measure.sh`
runs it and writes the answers to a file; this is that file, read. The input in every case is a 2 by 2
image of one channel holding 1, 2, 3, 4, whose shape the framework reports as 1, 1, 2, 2.

**The layers are not carried.** This is the measurement the layers family starts from, the same way
`Layers.md` is the measurement for their factories, and the code that uses it - the thirty layer
classes and the engine - is not written. No registry entry claims a layer.

## The activations, all twenty-one types, over 1, 2, 3, 4

| Type | Answers | | Type | Answers |
| --- | --- | --- | --- | --- |
| none | 1, 2, 3, 4 | | hard sigmoid | 0.7, 0.9, 1, 1 |
| ReLU | 1, 2, 3, 4 | | tanh | 0.7615941, 0.9640276, 0.9950548, 0.9993293 |
| linear | 1, 2, 3, 4 | | absolute | 1, 2, 3, 4 |
| sigmoid | 0.7310586, 0.880797, 0.9525741, 0.9820138 | | soft plus | 1.313262, 2.126928, 3.048587, 4.01815 |
| soft sign | 0.5, 0.6666667, 0.75, 0.8 | | ELU | 1, 2, 3, 4 |
| ReLUN | 1, 1, 1, 1 | | log sigmoid | −0.3132617, −0.126928, −0.04858733, −0.01814996 |
| SELU | 1.050701, 2.101402, 3.152103, 4.202804 | | CELU | 1, 2, 3, 4 |
| hard shrink | 1, 2, 3, 4 | | soft shrink | 0.5, 1.5, 2.5, 3.5 |
| tanh shrink | 0.2384059, 1.035972, 2.004945, 3.000671 | | threshold | 1, 2, 3, 4 |
| GELU | 1, 2, 3, 4 | | hard swish | 0.6666667, 1.666667, 3, 4 |
| clamp | 1, 1, 1, 1 | | | |

Three of these are worth naming because the header's own comment is not what the framework does:

- **GELU with the descriptor's default parameters is the identity.** The default a and b are 1 and 1
  (measured), and 1, 2, 3, 4 comes back unchanged. The GELU that does what its name says is
  `+[MLCActivationLayer geluLayer]`, whose descriptor carries a of 0.797885 and b of 0.044715, and
  which answers 0.841192, 1.954598, 2.996363, 3.99993 - the standard function. The two are different
  layers, and the port carries both as the framework does.
- **ReLUN and clamp with their default parameters are both a constant one**, because both take the
  maximum with b and b is 1. `+relu6Layer` is the ReLUN with a of 0 and b of 6, and `+clampLayerWithMinValue:maxValue:`
  is the clamp with the numbers the program gives.
- **The soft shrink and the tanh shrink differ**: with a of 0.5 the soft shrink is x − sign(x)·0.5,
  and the tanh shrink with its own default of 1 is x − tanh(x).

The parameterised factories answer what their arguments say: a leaky ReLU of 0.2, a linear of 3 and 4
giving 3x + 4, a soft plus of 2, an ELU of 0.5, a ReLUN of 0.1 and 6, a CELU of 0.7, a hard shrink of
0.3, a soft shrink of 0.4 giving 0.6, 1.6, 2.6, 3.6, a threshold of 0.6 and −1, a clamp of −1 and 2
giving 1, 2, 2, 2, and the default hard sigmoid and hard shrink layers giving what the table says.

## The arithmetic layer's arity depends on the operation

This is a rule the header does not state and that cost a run of failed compiles to find: **a unary
operation takes one source and a binary one takes two, and the framework compiles only the arity each
really has.** Asked with two sources, every one of floor, round, ceiling, square root, its inverse, the
six trigonometric and their inverses, the three hyperbolic and their inverses, exp, exp2, log and log2
fails to compile; asked with one, add, subtract, multiply, divide, pow, multiply-no-NaN,
divide-no-NaN, minimum and maximum fail. Measured, both ways, for all thirty.

The binary answers, a tensor against itself: add 2, 4, 6, 8; subtract 0, 0, 0, 0; multiply 1, 4, 9, 16;
divide 1, 1, 1, 1; pow 1, 4, 27, 256; multiply-no-NaN 1, 4, 9, 16; divide-no-NaN 1, 1, 1, 1; minimum
and maximum 1, 2, 3, 4. The unary answers are the library functions, with the infinities and the NaNs
left as they are: the arcsine of 2, 3 and 4 is `nan`, the arc-cosine of 2, 3 and 4 is `nan`, the inverse
tangent of 1 is `inf` and of the rest `nan`, and the inverse hyperbolic tangent of 1 is `inf`.

## The comparison layer

A comparison layer **writes 2.369428e-38 for true and 0 for false** into a float output, and its
logical operations do not compile with two sources. Measured: a tensor against itself answers
2.369428e-38 for equal, for less-or-equal and for greater-or-equal, and 0 for not-equal, for less and
for greater. 2.369428e-38 is a real measured constant of the framework, not a number this port chose,
and the port writes the same one.

## The shape-moving layers

| Asked for | Shape | Values |
| --- | --- | --- |
| reshape to 1, 4 | 1, 4 | 1, 2, 3, 4 |
| transpose by 0, 2, 1, 3 | 1, 2, 1, 2 | 1, 2, 3, 4 |
| transpose by 0, 1, 2, 3 | 1, 1, 2, 2 | 1, 2, 3, 4 |
| transpose of a tensor of three dimensions by 0, 2, 1 | 1, 2, 2 | 1, 3, 2, 4 |
| concatenate two on dimension 1 | 1, 2, 2, 2 | (see the caveat) |
| concatenate two on dimension 2 | 1, 1, 4, 2 | (see the caveat) |
| slice from 0, 0, 1, 1 to 1, 1, 2, 2 | 1, 1, 1, 1 | 4 |
| split in two on dimension 2 | 1, 1, 1, 2 | 1, 2 |
| upsample to 4, 4 | 1, 1, 4, 4 | 1, 1, 2, 2, 1, 1, 2, 2, 3, 3, 4, 4, 3, 3, 4, 4 |
| pad with zeros by 1, 1, 1, 1 | 1, 1, 4, 4 | 0, 0, 0, 0, 0, 1, 2, 0, 0, 3, 4, 0, 0, 0, 0, 0 |
| pad with the constant 9 by 1, 1, 1, 1 | 1, 1, 4, 4 | 9, 9, 9, 9, 9, 1, 2, 9, 9, 3, 4, 9, 9, 9, 9, 9 |
| pad by reflection by 1, 1, 1, 1 | 1, 1, 4, 4 | 4, 3, 4, 3, 2, 1, 2, 1, 4, 3, 4, 3, 2, 1, 2, 1 |
| pad symmetrically by 1, 1, 1, 1 | 1, 1, 4, 4 | 1, 1, 2, 2, 1, 1, 2, 2, 3, 3, 4, 4, 3, 3, 4, 4 |
| dropout at rate 0 | 1, 1, 2, 2 | 1, 2, 3, 4 |

The upsample is nearest-neighbour, each value repeated twice along each axis, in the order
1, 1, 2, 2, 1, 1, 2, 2, 3, 3, 4, 4, 3, 3, 4, 4 - which is the height varying slowest. The reflection
pads by repeating the far edge, not the near one, so a 1-wide border on the left of the row 1, 2 is 2;
the symmetric pad repeats the edge on both sides of it.

**The transpose needs one entry in the dimensions array for every dimension of the tensor.** Three
entries for a tensor of four raises `NSInvalidArgumentException` (measured); four entries for it and
three for a tensor of three both work, and the array is read as the input axis of each output axis, so
0, 2, 1, 3 on a 1, 1, 2, 2 gives 1, 2, 1, 2.

**One caveat on the concatenation:** the measured answers for it are 0, 0, 0, 0, 1, 2, 3, 4 on both
dimensions, where the two sources were the same tensor and only one input was bound to the graph. The
second half is the input and the first half is zeros, so the case is a property of the harness rather
than of the layer, and no rule is drawn from it. It is re-asked with two distinct bound inputs by the
layers family's own differential.

## The layers that reduce

| Asked for | Shape | Values |
| --- | --- | --- |
| softmax | 1, 1, 2, 2 | 1, 1, 1, 1 |
| log softmax | 1, 1, 2, 2 | 0, 0, 0, 0 |
| mean over dimension 2 | 1, 1, 1, 2 | 2, 3 |
| sum over dimensions 1 and 2 | 1, 1, 1, 2 | 4, 6 |
| max over dimension 2 | 1, 1, 1, 2 | 3, 4 |
| argmax over dimension 2 | 1, 1, 1, 2 | 1, 1 |
| max pooling of 2 | 1, 1, 1, 1 | 4 |
| average pooling of 2 | 1, 1, 1, 1 | 2.5 |
| L2-norm pooling of 2 | 1, 1, 1, 1 | 5.477226 |
| the Gram matrix of scale 2 | 1, 1, 1, 1 | 60 |

The softmax answers 1 and the log softmax 0 because their default dimension is 1, and dimension 1 of
a 1, 1, 2, 2 tensor holds one element, whose softmax is 1. That is the layer working, not a layer that
does nothing. The mean over the height is 2, 3; the sum over the channels and the height is 4, 6,
which is the height varying slowest; the argmax answers the index along the reduced axis, 1, for both
columns because the larger of each pair is in row 1. The L2-norm pooling is the square root of the
sum of the squares of the window, √30 for 1, 2, 3, 4, and the Gram matrix of scale 2 is twice the sum
of the squares of the flattened tensor, 2 × 30.

## The layers that carry parameters

| Asked for | Shape | Values |
| --- | --- | --- |
| a 1 by 1 convolution of weight 2 | 1, 1, 2, 2 | 2, 4, 6, 8 |
| the same with a bias of 1 | 1, 1, 2, 2 | 3, 5, 7, 9 |
| a matmul of a tensor against itself | 1, 1, 2, 2 | 7, 10, 15, 22 |
| a batch normalization of mean 1, variance 4, beta 0.5, gamma 2 | 1, 1, 2, 2 | 0.5, 1.499999, 2.499998, 3.499996 |
| a group normalization of beta 0, gamma 1 | 1, 1, 2, 2 | −1.341635, −0.4472118, 0.4472118, 1.341635 |
| an instance normalization of beta 0, gamma 1 | 1, 1, 2, 2 | −1.341635, −0.4472118, 0.4472118, 1.341635 |

The batch normalization is (x − mean) / √(variance + epsilon) · gamma + beta element by element, to
the last digit of the float: x = 2 gives 2 × 0.5 + 0.5 = 1.499999. The group and instance
normalizations of a 2 by 2 window with no running mean or variance are (x − 2.5) / √(var + epsilon),
and give the same answer, which is what a single group of one channel means. The matmul is the plain
2 by 2 product, 7, 10, 15, 22.

Four layers did not compile with the shapes tried and are the open questions of the family: the fully
connected layer with a 1 by 1 weight, the gather and the scatter with an index tensor of one element,
and the layer normalization with a one-dimensional beta. Each is asked again with the shapes the
framework's own descriptors give by the differential of the family that carries them.
