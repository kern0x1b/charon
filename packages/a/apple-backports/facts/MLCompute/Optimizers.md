# MLCompute's optimizers: what a descriptor makes of them

Measured on this host's own MLCompute, macOS 27.0 build 26A428 (M4 Pro), by
`.agent-work/runs/probe/mlc-optimizers.m` in the worker's `.agent-work/runs/probe/`. Two descriptors go in:
one whose every field is a value of its own - learning rate `0.125`, gradient rescale `0.25`, clipping on,
clip max `3.5`, clip min `-2.5`, `MLCRegularizationTypeL2`, regularization scale `0.75` - and one that says
nothing, made with the four-argument descriptor factory at `0`.

**An optimizer is a copy of the descriptor's numbers and its own.** Every one of the seven numbers a 14.0
descriptor carries comes out of an SGD, an Adam and an AdamW exactly as it went in, over both
descriptors:

| | learning rate | rescale | clipping | clip max | clip min | regularization | scale |
| --- | --- | --- | --- | --- | --- | --- | --- |
| from the full descriptor | 0.125 | 0.25 | yes | 3.5 | -2.5 | L2 (2) | 0.75 |
| from the empty one | 0 | 0 | no | 1 | -1 | none (0) | 0 |

The three numbers a 15.0 descriptor adds are `MLCGradientClippingTypeByValue` (0), `1` and `1` out of every
descriptor asked for, including the four-argument factory that cannot name them - which is what
`MLCDescriptors14.m` already answers for the descriptor itself, so the optimizer inherits it.

**What each optimizer adds is its own, and the defaults are the header's own, measured.**

| | | default | measured as |
| --- | --- | --- | --- |
| `MLCSGDOptimizer` | `momentumScale` | 0.0 | 0 |
| | `usesNesterovMomentum` | NO | 0 |
| `MLCAdamOptimizer`, `MLCAdamWOptimizer` | `beta1` | 0.9 | 0.899999976 |
| | `beta2` | 0.999 | 0.999000013 |
| | `epsilon` | 1e-8 | 9.99999994e-09 |
| | `usesAMSGrad` | NO | 0 |
| | `timeStep` | 1 | 1 |

**Adam and AdamW hold the same five numbers.** Over the full descriptor, an Adam and an AdamW answer
`0.899999976`, `0.999000013`, `9.99999994e-09`, no AMSGrad and step `1` - the same ten digits each. What
the two optimizers differ in is what an update does with them, the weight decay being decoupled from the
gradient in AdamW and not in Adam, and that is the engine's business and not a number this class holds.

**The factories that carry numbers pass them through verbatim**, measured:
`+[MLCSGDOptimizer optimizerWithDescriptor:momentumScale:usesNesterovMomentum:]` at `0.625` and YES answers
`0.625` and `1`; `+[MLCAdamOptimizer optimizerWithDescriptor:beta1:beta2:epsilon:timeStep:]` at `0.1`,
`0.2`, `0.3`, `7` answers `0.100000001`, `0.200000003`, `0.300000012` and `7`, and the AMSGrad flag, which
is not one of that factory's arguments, stays NO; the five-argument Adam factory at `0.4`, `0.5`, `0.6`,
YES, `9` answers `0.400000006`, `0.5`, `0.600000024`, `1` and `9`; the AdamW factory at `0.7`, `0.8`, `0.9`,
YES, `11` answers `0.699999988`, `0.800000012`, `0.899999976`, `1` and `11`.

**What each factory answers is an instance of its own class**: an SGD is an `MLCSGDOptimizer` whose
superclass is `MLCOptimizer`, an Adam an `MLCAdamOptimizer`, an AdamW an `MLCAdamWOptimizer`, all three
measured.

**The base class's own `+new` and `-init`, which its header marks unavailable, answer an `MLCOptimizer`
with the family's defaults** - a learning rate of `0`, no clipping, `MLCGradientClippingTypeByValue`. That
is the whole of what a bare optimizer is, and it is why the port makes one by allocating and giving it the
defaults rather than through `-init`: the factories in the 15.0 objects cannot call an initialiser the SDK
declares unavailable.

**`+[MLCTensorOptimizerDeviceData new]`, which its header also marks unavailable, answers an
`MLCTensorOptimizerDeviceData`** with nothing of its own set (measured).

## One object per release, and one that the SDK spells differently

`MLCOptimizers14.m` carries the base class and the two 14.0 subclasses;
`MLCOptimizers15.m` carries AdamW, its two factories, its five properties and the three properties the base
class gained in 15.0. The one factory of 14.0's `MLCAdamOptimizer` that takes an AMSGrad flag is an object
of its own, `MLCAdamAMSGrad15.m`, and the reason is in that file's own header: the SDK annotates it
`MLCOMPUTE_AVAILABLE_STARTING(macos(12.0), ios(15), tvos(15))` - with "ios(15)" and not "ios(15.0)" as
AdamW and the base class's three 15.0 properties are spelled - and an object carries one release, which
`misplaced()` in `modules/apple/backports.lua` reads off those two spellings. Its registry row therefore
says `introduced: "15"` and every other 15.0 row says `"15.0"`.

## The three seams, and where they live

`CharonMLCOptimizerState` is the port's own object and holds the seventeen numbers, so a factory in one
release's object and a property in another's read the same values; its name begins with `Charon`, so
`internal_symbol()` in `modules/apple/backports.lua` keeps it out of the exports and the band splitter
never weighs it. Three methods of `MLCOptimizer` are the seams between it and the optimizers -
`charon_mlc_state`, `charon_mlc_takeStateFrom:` and `charon_mlc_optimizerOfClass:copying:` - and each is a
registered row, as the graph library's own thirteen are. They are declared in `CharonMLCompute.h` because
three objects of the library read them.