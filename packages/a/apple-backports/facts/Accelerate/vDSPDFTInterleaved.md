# vDSP_DFT_Interleaved: what is measured, and what is still not

Six rows at 15.0, all unwritten. This page records what the host answers, so the port is written from
measurement rather than from a signature. **The real-to-complex packing is NOT settled** — see the third fact,
which is a negative result and is the reason no port exists.

## 0. The accepted-length set, exact, swept 1 to 1024 against the host

**31 of 1024 lengths are accepted, and the set is exactly `f * 2**n` with `f` in {2, 3, 5, 9, 15} and `n >= 2`:**

    8 12 16 20 24 32 36 40 48 60 64 72 80 96 120 128 144 160 192 240 256 288 320 384 480 512 576 640 768 960 1024

`vDSP_DFT_Interleaved_RealtoComplex` and `vDSP_DFT_Interleaved_ComplextoComplex` accept **the same set**, measured
over the whole sweep. And **the header's `5*5 = 25` is not implemented**: 25 itself is refused, and so are
25 * 2**2 = 100, 25 * 2**3 = 200, 25 * 2**4 = 400 and 25 * 2**5 = 800 - every one of which the header's list
admits. `3*5 = 15` is implemented, and 15 * 2**n appears throughout the accepted list.

So the refusal rule the port must use is **`f` in {2, 3, 5, 9, 15}, `n >= 2`**, and the header's list is right
about every factor except `5*5`. That is an exact, host-measured specification for `CreateSetup`, and it is the
first part of this family that needs no error bound at all.

## 1. The supported-length predicate, and where the header is wrong

The header says `Length = f * 2**n, where f is 2, 3, 5, 3*3, 3*5, or 5*5 and n >= 2`, and that zero is returned
if there is no implementation for the requested case. Measured over 1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 16, 25, 27,
50, 100, 125, 128 and 0: **8, 12, 16 and 128 are accepted; every other length is NULL.** So the predicate holds
where the small lengths are concerned — 9 and 25 are refused because `n = 0 < 2` — **and it is wrong at 100**,
which is `25 · 2**2` and satisfies it exactly, and which the host refuses.

**So `CreateSetup` must refuse exactly the set the host refuses, measured over a sweep of 1 to 1024, and the
header's predicate is a starting point with at least one known exception rather than the rule.** Length 4, which
is `2 · 2**1` with `n = 1`, is refused — a useful control, since the coordinator's suggested 8-real-sample case
would have used it.

## 2. The inverse is unscaled, and the two directions do not reverse the index

Forward then inverse on `Length = 8`, a single unit bin at each k in turn: **every bin returns at exactly
`8.0` (`0x41000000`) from an input of `1.0`**, and the energy comes back to the *same* bin. So the factor is
the length and not its reciprocal — `1/8 = 0.125` would be the other reading — and there is no index reversal
between the directions.

## 3. The real-to-complex packing — SOLVED, and my check was the wrong part

**The packing is the documented one**, confirmed numerically over 64 random 16-sample real inputs:

    o[0] = (2*X_0, 2*X_8)     both real, by conjugate symmetry
    o[k] = 2*X_k              BOTH parts, for k = 1 .. Length-1

**My first check was wrong, and it was wrong in a way worth recording.** I computed the naive double DFT keeping
only the real part and wrote the imaginary part as zero, on the reasoning that a real input gives a real
spectrum. That holds only for `X_0` and `X_{N/2}`; every other `X_k` is complex. So the prediction was half
wrong — and **the real part matching to about one ULP was the part that was right**, which is what the packing
predicts, and I read it as the host being "close but not doing the real transform" instead of as confirmation.
The coordinator's reading of the same impulse sweep was the correct one: the DFT of an impulse IS a flat
spectrum, and `(2, 2)` and `(2, -2)` at k = 0 are DC and Nyquist packed.

With both parts carried, the imaginary part matches **exactly** and the real part differs by **1 ULP** — the
host's float against a double-precision reference, so the double is the more accurate side. **1 of 64 trials
match bit for bit**, and those are the ones where the float result happens to be exact. This is the same class
of one-ULP as the biquad's float, and it is the reason a bit-exact differential needs the host's own algorithm
rather than a naive float DFT.

## 4. The inverse's factor, measured and not assumed

Forward then inverse on a real signal, through the same packing: **the factor is 32 = 4 * Length**, read on the
positions the probe unpacks correctly. That is the forward's x2 times the inverse's unscaled 2*Length, which is
the coordinator's reading, and it is measured rather than assumed.

## 5. The error bound — and this is the specification, not a tolerance

`vDSP_DFT_Interleaved` is 15.0, **no guest here runs 15.0**, and the host's own FFT cannot be reached
bit-exactly — so for this one place in the band an error bound IS the specification rather than a tolerance,
and both the host and the port are held to the same constant.

    per element:   |out - ref| <= K * log2(N) * FLT_EPSILON * ||x||_2      with  K = 1.538

**K is taken once from the host's own worst case over the 31 accepted lengths**, 24 random real inputs each,
with `ref` a naive double-precision DFT of the `2 * Length` real samples and the packing of section 3. The
worst ratio over the whole sweep is **1.538, at Length 64 element 30** — and it is the *host's* ratio, so the
constant is not chosen to pass the port.

**Getting there found a real fault in the reference, not in the host.** The first attempt gave a worst ratio of
1.6e7 at Length 16 element 0, which is an implied absolute error of about 21 — far too large to be rounding, so
the reference was the broken side. Element 0 is the packed one holding `(2*X_0, 2*X_n)`, and its imaginary part
is the **Nyquist bin, which for a real input is the alternating sum**:

    X_n = sum over the 2*Length real samples of x[j] * (-1)^j      real, since e^(-pi*i*j) = (-1)^j

An earlier version took that term from the same accumulator that produced `X_0`. With it corrected the ratio
falls from 1.6e7 to 1.538, and **the same mistake was what made the host look wrong at element 0** in the
packing check a turn earlier.

**What the bound is for.** The exact parts of this family are the packing layout, the x2 and the 4*Length
factors, and the accepted-length set of section 0 — all reproduced exactly and needing no bound. Everything
else is the transform's arithmetic, and it is held to K. A mutant that puts a twiddle's sign wrong, drops the
x2, or swaps the packing breaks the bound by orders of magnitude rather than by an ULP, which is the test that
the bound is tight enough to be a specification.

## 6. The inverse's unpacking, as a formula, and the obstacle to the differential

**The 16x16 table of impulses gives the unpacking directly** - the inverse is linear, so an impulse in each of
the sixteen scalar inputs of the packed spectrum, read out as the sixteen real samples it produces, IS the
formula. Measured, with N = 8 and j the sample index:

    o[0].real  contributes  1        to every sample
    o[0].imag  contributes  (-1)^j
    o[k].real  contributes  2*cos(2*pi*k*j/(2N))     for k = 1 .. N-1
    o[k].imag  contributes -2*sin(2*pi*k*j/(2N))

Written out and checked on 64 random packed spectra against the bound: **the worst ratio is 0.851, inside
K = 1.538.** So the inverse is specified as well as the forward, and both are held to the bound.

**The obstacle, and it is the house's rename mechanism rather than anything in the rows.** The differential
renames the port's definitions so the port's and the host's can sit in one binary, by compiling the port with
`-DvDSP_DFT_Interleaved_CreateSetup=charon_host_vDSP_DFT_Interleaved_CreateSetup` and so on. **Those three
function names share a prefix with the opaque setup type `vDSP_DFT_Interleaved_Setup`**, and the preprocessor
substitution reaches the header's own declarations of the type, so vDSP.h stops compiling at the family's own
declarations. Every other family in this band renames cleanly because no function name is a prefix of a type
name it also declares.

So the differential needs a different mechanism here - renaming by an explicit per-file list that does not
substitute the type, or compiling the port with a macro rather than `-D` - and **that is not a decision I
should make quietly, because it changes how every subsequent differential in this band is built.** The port
itself compiles clean.
