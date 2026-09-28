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

## 3. The real-to-complex packing does NOT match, and this is why there is no port

**Checked numerically as the coordinator proposed, and it fails: 0 of 64 random 16-sample real inputs match.**
With a naive double-precision DFT `X` of the 16 real samples, the prediction was `o[0] = (2*X_0, 2*X_8)` and
`o[k] = 2*X_k`. What the host returns, first mismatch at k = 1:

    the host    -2.20978284  -1.72107601
    predicted   -2.20978308   0

**The real part agrees to about one ULP and the imaginary part does not agree at all.** For a real input `X_k`
is real, so a packed real DFT would carry zero in the imaginary parts of elements 1 to Length-1, and the host
carries `-1.72`. That is the same observation the impulse sweep made — the array is being read as `Length`
complex values — and it is also why an impulse gives a flat spectrum, which is a property of a complex DFT and
is not evidence about a real one.

The forward-then-inverse factor on the real signal is **32 = 4 * Length**, measured on the positions my probe
read correctly; neither `2*N = 16` nor `N = 8`.

**Two readings have now been offered for this packing — the coordinator's packed real DFT, and mine that the
flag is inert — and the numbers support neither.** The real part landing within an ULP of `2*X_k` says the host
is close to the real transform and not doing it, which is a third thing again. So the packing is unresolved, and
**the port is not written**, because choosing between those three is a guess about the one thing this family
exists to get right.

The probe is `.agent-work/runs/dft/` and is not source.
