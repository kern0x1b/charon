# vDSP_DFT_Interleaved: what is measured, and what is still not

Six rows at 15.0, all unwritten. This page records what the host answers, so the port is written from
measurement rather than from a signature. **The real-to-complex packing is NOT settled** — see the third fact,
which is a negative result and is the reason no port exists.

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
