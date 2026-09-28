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

## 5. The error bound, and why it is not yet a specification

The coordinator's rule for this one place is right: `vDSP_DFT_Interleaved` is 15.0, **no guest here runs 15.0**,
and the host's own FFT cannot be reached bit-exactly, so the differential must hold both the host and the port
to a bound of the form

    per element:  |out - ref| <= K * log2(N) * FLT_EPSILON * ||x||_2

**K is not measured yet, and the reason is my reference rather than the host.** Taking the ratio
`|out - ref| / (log2(N) * FLT_EPSILON * ||x||_2)` over the accepted lengths gives a worst case of 1.6e7 at
Length 16 element 0 — which is a denominator of about 1e-6 against an implied error of about 21, and an error
that large means the *reference* is wrong, not the host. Element 0 is the packed one, holding `(2*X_0, 2*X_n)`,
and my reference computes its Nyquist term from the wrong quantity.

**So no bound is written down, and the port is not written against one.** A K of 1.6e7 taken from a broken
reference would be a number in a facts file that looks like a specification and is not one — which is the
failure this whole facts page exists to prevent. The reference's element-0 term is the thing to fix, and
K falls out of the sweep once it is.

This is the one place in this band where an error bound IS the specification rather than a tolerance, and
saying so here is the point: the exact parts of this family are the packing layout, the x2 and the
4*Length factors, and the accepted-length set above. Everything else is bounded, and the bound's constant is
not yet known.
