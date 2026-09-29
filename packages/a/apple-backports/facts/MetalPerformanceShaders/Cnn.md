# The convolutional kernels: the first slice of the CNN family

`MPSCNNConvolution`, `MPSCNNConvolutionDescriptor`, `MPSCNNConvolutionWeightsAndBiasesState`,
`MPSCNNPooling`, `MPSCNNPoolingAverage`, `MPSCNNPoolingMax` and `MPSCNNBatchNormalization`.

The reference is **ncnn** at `c6b351b56fbe32e0381ae00331e3df649b20d7b7` (BSD 3-Clause), read from
`https://github.com/tencent/ncnn` — a fresh clone, not a package cache, which `charon/AGENTS.md` says is
patched. Three things were taken from it, and each is named where it is used.

## The convolution

`Convolution::convolution` (line 157) is the walk this port uses: a `space_ofs` table of the kernel's
taps, computed once for the stride and the dilation, then per output channel and output pixel one
accumulator seeded with that channel's bias, walked over the input channels and the taps, with the
neuron's function applied once to the accumulator. The weights are read in the OHWI layout the release
uses: output, kernel height, kernel width, input channels.

What differs is where the values live — an `MPSImage` is a plane per feature channel, not an `ncnn::Mat`
per channel — and that **a tap outside the image contributes nothing**, rather than reading a bordered
copy of the input, which is what the release's `MPSImageEdgeModeClamp` describes and what
`MPSCNNPadding` will have to say. `groups` other than 1 is refused in the log: it is a different walk
and is not carried yet.

## The pooling divisor, measured

**The divisor is the window's area, always.** A 3x3 window over a 3x3 image, a stride of one, the zero
edge mode, so that the corner windows hang half outside: the top left answers **1.33333**, which is
12/9 — the sum of the four values really there over the whole window — and not 12/4, the count of them.
Setting `zeroPadSize` to one on each side changes nothing, so the pad does not grow the window here.

That is ncnn's rule with `avgpool_count_include_pad` set (`Pooling`, parameter 6): the window is
divided by, and what falls outside is zero rather than skipped. ncnn's other setting, dividing by the
count of the values really there, is the one MPS does not take. Getting this wrong was caught by the
differential, which is what it is for: the port had been growing the window by the pad and dividing by
the grown area.

## The normalisation fold

`BatchNorm::load_model` folds the normalisation once, when the parameters are given, into

    a = beta  - gamma * mean / sqrt(variance + epsilon)
    b = gamma /               sqrt(variance + epsilon)
    value = b * value + a

so the loop that normalises an image is a multiply and an add per value, with no division and no square
root in it, and a zero variance is sanitised to a divisor of 0.0001 the way ncnn sanitises it.

**Epsilon is inside that fold, so changing it has to fold again.** The differential caught this: the
release answers -4.0356 for the first value with epsilon 0.25, which is a fold that used it, and a fold
made when the state was created answers -4.3990, which is a fold that did not. `-setEpsilon:` folds
again.

## The output shape, measured

The release's pooling output is **not cropped to the window arithmetic**. Over a 4x4 source of 1..16, a
2x2 window and a stride of one, the whole destination read back with a 4-wide row stride answers sums
over the window's area of

    1   3   5   7
    6   14  18  22
    14  30  34  38
    22  46  50  54

and every one is **the 2x2 window whose top-left is one row and one column before the output pixel**,
with what lies outside the source counted as zero but still in the divisor: the output is the
source-sized result, shifted a row and a column, its first row and column partial. A 3x3 window over a
3x3 image has the whole image in every interior window, which is why the maximum and the 3x3-average
cases agreed with a cropped walk all along.

**This port answers the same values.** Measured on both sides of a standalone program over a 3x3 source
of 1..9, a 2x2 window, a stride of one, the zero edge mode:

| destination | release | this port |
| --- | --- | --- |
| 2x2 | `0.25  0.75  1.25  3` | `0.25  0.75  1.25  3` |
| 3x3 | `0.25  0.75  1.25  1.25  3  4  2.75  6  7` | `0.25  0.75  1.25  1.25  3  4  2.75  6  7` |

So the window is centred, the divisor is its area, and what falls outside is zero - which is what
`MPSCNNPooling10.m` does, and there is no second, source-sized path to add: one rule answers both
destination sizes the release answers. The stride-1 offset in the table above is the centred one, not a
separate shift; a 2x2 window centred on the first pixel takes the first pixel alone, and a 3x3 one takes
the first three.

## What the host differential says

`tests/backports/host/mpscnn/` compiles `cnn-cases.m` twice - once against the system's MPS, once
against this port's classes with the MPS names mapped to `Charon` names and their selectors prefixed -
and compares with a tolerance written down before the numbers were read: **1e-4 absolute or relative**
for a single-precision result, because a convolution accumulates in a different order on a GPU than on
a CPU, and **exact** for pooling, whose cases are named as such.

**Four of the five cases agree bit for bit**: `pooling-max`, `pooling-average-pad0`,
`pooling-average-pad1` and `batch-normalization`.

`pooling-average-2x2` is reported as differing, and **it does not**: the standalone program above has
both sides answering the release's `0.25 0.75 1.25 3` for that shape. The difference is in the harness,
not in the kernel, and where to look is the rename: the port's objects are compiled with `rename.h`, so
`CharonMPSCNNPooling` derives from `CharonMPSCNNKernel`, which derives from the **system's**
`MPSKernel` - a class of the port's tree that the rename does not cover, and one the port's `MPSKernel`
also defines. The harness's port build and the standalone link therefore have two different
`MPSKernel` classes in the process. Which of them the pooling walk ends up using is the thing to check
first, and it is a harness defect to fix before the case is read as a kernel defect.
