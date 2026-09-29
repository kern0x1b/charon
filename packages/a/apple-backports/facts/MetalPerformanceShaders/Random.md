# The random number generators on this port

`MPSMatrixRandomDistributionDescriptor`, `MPSMatrixRandom`, `MPSMatrixRandomPhilox` and
`MPSMatrixRandomMTGP32`. The linear solvers that sit beside them in the same header group are not in the
tree yet; see the handoff this directory's own `.agent-work` keeps.

Source: the header of `MPSMatrixRandom` in the SDK of iOS 16.4 for every signature, default and
documented data type, and `tests/backports/host/mpsmatrix/` for the behaviour.

## What the device is

Every random kernel here writes into an `MTLBuffer` and reads nothing from a texture, so — like the
matrix kernels in [Matrix.md](Matrix.md) — it runs over the host memory behind that buffer, on the CPU,
with the arithmetic done in the same precision the release's own does. No Metal capability is involved,
so none of this waits on the pixel formats.

## Philox, which is the release's own stream

`MPSMatrixRandomPhilox` is Philox4x32-10, the counter based generator of Salmon, Moraes, Dror and Shaw
(*Parallel Random Numbers: As Easy as 1, 2, 3*, SC'11), and this port reproduces the release's stream
**bit for bit**. What was measured, not assumed:

* the caller's `seed` is the key's first word and the key's second is zero;
* the counter is `(0, 0, 0, block)`, so element `i` comes from block `i / 4`, word `i % 4`;
* the ten rounds use the two multipliers `0xD2511F53` and `0xCD9E8D57`, the Weyl additions
  `0x9E3779B9` and `0xBB67AE85` on the key, and the hi/lo split of the 64 bit products — the
  published algorithm, unchanged.

The evidence is two independent oracles that agree: the release's own `MPSMatrixRandomPhilox` on macOS
26.5, and the published reference vectors. For seeds 0, 1 and 2 the port's sixteen words are equal to
both.

**A `Float32` destination is `t = (word >> 9) * 2^-23`**, the top twenty-three bits of the word as a
fraction, and a uniform distribution is `minimum + (maximum - minimum) * t` evaluated in one rounding.
Both were read off the release's own answers, bit by bit, and both are reproduced exactly; a float
chain that rounds the scale and the add separately is one unit in the last place out on three of eight
probed values, which is what a fused multiply-add or METAL's `lerp` avoids. A `Float32` destination is
in the differential's compared set and agrees.

## What the release of macOS 26.5 does not answer

Two things, and both are the release's own refusals rather than gaps in this port. Both are measured by
`crash-probe.m` in `tests/backports/host/mpsmatrix/`, which is kept out of the differential so the
oracle is not asked a question it dies on:

* **An `MPSVector` destination takes the release down.** Its own random kernel sends
  `-[MPSVector rowBytes]`, a selector `MPSVector` does not declare, and the process terminates on the
  unrecognised selector. Every shape was tried: one vector of four elements, sixteen vectors of one,
  four vectors of two, eight vectors of four, and every `vectorBytes` from the descriptor's own
  recommendation. `./crash-probe float32` answers, in the same process and the same minute, which is what
  says this is the release's own refusal and not this harness's mistake.
* **A batch range over a matrix destination is refused in the release's own validation**:
  `Number of requested results (4) is too large to fit in the destination image at the specified offset
  (16)`, for a 4x1x3 destination with `batchStart = 1` and `batchSize = 2`. The offset it names is not
  an offset the caller set.

This port fills both, as the header says it should. It is not the release's behaviour, it is a case the
release refuses, and saying so is the whole of what can honestly be claimed about it. The arithmetic
behind a `Float32` destination is the same `t` and the same scale-and-add measured above and compared
above, so this port's answers there are the release's own answers.

**A batch range is taken over the destination's batch dimension** — the matrices of an `MPSMatrix`, the
vectors of an `MPSVector` — which is what "the starting index in the destination batch" names. The
release instead treats the destination as a single image of `rows x columns`, which is the narrower
reading, and refuses a range that runs past it.

## Where the generator cases are verified, and where they are not

The differential's oracle **stops at `MPSMatrixBatchNormalization` with the GeLU neuron type**, the
eleventh of fifteen, after 1232 cases — the release's own kernel crashes there on this host, which is
a third instance of the same instability and has nothing to do with this port. The generator cases come
after it, so they are not in the differential's compared set.

They are verified against the release directly instead, and `crash-probe.m` is how: for seeds 0, 1 and
2 the port's sixteen words are equal both to the release's own `MPSMatrixRandomPhilox` and to the
published Philox4x32-10 reference vectors, which are two oracles that do not depend on each other. The
`Float32` uniform cases are in the differential and agree; the normal one is the divergence below.

## MTGP32, and what it does not reproduce

`MPSMatrixRandomMTGP32` is the Mersenne Twister of Matsumoto and Nishimura — the 624 word state, the
same recurrence and the same tempering that MTGP32 is a member of — seeded from the caller's `seed`.
The distribution is right: a uniform 32 bit stream from a generator built for exactly that.

**It is not the release's stream, and the release's is not reproducible from the published seeding.**
Measured: for `seed = 0` the release's first sixteen words are
`292b9f95 5e64b688 90d5d94d 1282ba5c …` and a Mersenne Twister seeded the published way gives
`8c7f0aac 97c4aa2f b716a675 d821ccc0 …`. The two are not truncations of one another. MTGP is a
*block* generator: it produces a fixed block of words per step and hands each thread its own position in
it, and the block size and the schedule that skips to a block are the implementation's own, not part of
the published seeding. Reproducing Apple's stream would mean reverse-engineering that schedule from its
output, which is not a native implementation of anything and is not attempted here.

What would remove the divergence: Apple's block size and skip schedule, which is not in any header.

## The normal distribution

`MPSMatrixRandomDistributionNormal` draws `mean + standardDeviation * invnorm(t)` from the same `t`.
The rule is measured — the release's answers for `mean = 2, standardDeviation = 3` are within one part in
`10^7` of this for every probed value — but the release evaluates its inverse normal in **single
precision**, and a sixteen-digit one does not land on the same bit: three of eight probed values differ
by one or two units in the last place of a `float`.

This is the open item of this family, and it has got further than "eight points are not enough".

**160,000 pairs are now measured** — `inverse-normal-probe.m` in `tests/backports/host/mpsmatrix/`
prints, for every element of a 400x400 draw, the twenty-three bit fraction `t` and the release's
answer as raw bits. The tails are covered: 3,863 points below 0.02425 and 3,818 above 0.97575, which
is where Wichura's three branches and Acklam's differ from one another, and `t` runs from 1.4e-05 to
0.999996.

**And the measurement found something else first: the release does not fill the destination in element
order.** The first ten rows pair with `t` reconstructed from the index, and agree with
`mean + standardDeviation * invnorm(t)` to about three parts in `10^6`. Past those rows they do not:
the median relative difference over the whole 160,000 is about one, not one in `10^7`. This is a
kernel that writes a block of values per thread group in an order of its own — which is what
`MPSParallelRandom.mm`, the file the release's own failures name, suggests it does.

So the inverse normal cannot be fitted until that order is recovered, and the order is the next thing
to work out, not the algorithm's coefficients. AS 241 evaluated in single precision and in double both
land on the release's bits for under 5% of the points, which says the release's is a *different*
approximation rather than the same one at a different precision.

Until both are done the port's value is a correct inverse normal to within a few units in the last
place, and the registry says that rather than claiming a bit-exactness that has not been shown.

## The distribution descriptor

`+uniformDistributionDescriptorWithMinimum:maximum:` also fills in the moments, and those were measured
rather than derived from the shape of the formula: for `[-2, 3]` the release answers `mean = 0.5` and
`standardDeviation = 1.44337571`, which is the mean at the middle and the width over the square root of
twelve. `+defaultDistributionDescriptor` answers every field zero, and
`+normalDistributionDescriptorWithMean:standardDeviation:` leaves the bounds infinite.
