# The placement group: distancesq, normalize, vsmsma — what is measured and what the guest must decide

Ladder measured through `release-split` over an object that defines the names, with `_vDSP_sve_svesq` as the
control (it must come out at 6.0, and did — the first run put every name at `none` and was discarded on that
control, because a C definition of `_vDSP_distancesq` becomes `__vDSP_distancesq` on Mach-O).

| row | first release | file it belongs in |
| --- | --- | --- |
| `vDSP_distancesq` | **5.0** | a 5.0 file — not 6.0 with the rest |
| `vDSP_normalize` | 6.0 | a 6.0 file |
| `vDSP_normalizeD` | 6.0 | a 6.0 file |
| `vDSP_vsmsma` | 6.0 | a 6.0 file |
| `vDSP_distancesqD` | **8.0** | an 8.0 file |

**`vDSP_distancesqD` was not in the candidate list** this band took to the coordinator, so the shape is five rows
plus the two reductions, not four. Sizing a group from a list written before measuring anything in it is the
same fault as trusting the header's marks.

## Measured, by hand-computed controls

**`vDSP_normalize` divides the variance by N, not by N-1.** The sum of squared deviations from the mean of 5
over `{2,4,4,4,5,5,7,9}` is 32 exactly, and 32/8 = 4 is exactly representable in float while 32/7 is not — so
values where only one divisor is exact make the choice measurable rather than arguable. The host's answer is 2,
the population standard deviation. `C` is `(x - mean) / sd` elementwise with a stride of its own. The same
control holds in double.

**`vDSP_vsmsma` writes only the elements its stride names.** With `B = 2`, `D = 3` and a stride-2 destination,
the host wrote 32 64 96 128 into the even positions and **left the odd ones at the `0x5a3a3a3a` they were
filled with**. A test that checks only the elements the port is meant to write would miss that entirely.

## What the guest must decide before any of these five rows is written

None of this is guessed, and none of it is guessed *in advance* — each is a question only the release can answer,
on the release that has the function, at load under 12 and with a free slot.

1. **`vDSP_normalize` with a zero spread.** `C` is `(x - mean) / sd` and `sd` is 0 for a constant input, so the
   division has no answer to copy. Zero, a NaN, or something else — and whether `C == NULL` changes it, since
   `C` is `__nullable` and the header says so deliberately. **The row is not implemented until the guest answers
   both.**
2. **`vDSP_vsmsma`'s channel indexing.** The signature takes `const float *__B` and `__D` with no channel count,
   and the header gives one line and no pseudocode. A single scalar per side is measured; how more than one
   channel is expressed is not, and a port that assumes an array of one would be right on the control and wrong
   on everything else.
3. **`vDSP_distancesq`'s window.** The signature is `(A, IA, B, IB, C, N)` with two input strides, one output
   and no inner count, so what one element of `C` sums over is exactly the thing not to assume. A squared
   distance implies a window and the declaration does not say how wide.
4. **`vDSP_distancesqD` at 8.0**, which needs an 8.0 guest; the emulator's releases are what decides whether
   that is the nearest one available, and if it is not, that gets said rather than glossed.

The macOS arm64 host's answers are candidates for all of this and the oracle for none of it: it has been wrong
twice on rows that are native on 6.0 armv7 — the reduction's order, and the biquad's one-ULP float difference.
