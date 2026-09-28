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

## Two of the four are defined by the header, and I did not read past the signature

Each declaration carries a **Maps** comment giving the computation in one line, and I took the signature as
the whole specification. That was the mistake, and it cost two of my four open questions:

    vDSP_distancesq / vDSP_distancesqD:   C[0] = sum((A[n] - B[n]) ** 2, 0 <= n < N);
    vDSP_vsmsma / vDSP_vsmsmaD:           E[n] = A[n]*B[0] + C[n]*D[0];

So **`vDSP_distancesq` writes one scalar**: the squared distance summed over a window of N, with `IA` and `IB`
the strides of the two inputs and no inner count because there is no inner dimension. A port that wrote one
`C` per element would be wrong in a way no test of the input strides would catch.

And **`B` and `D` in `vDSP_vsmsma` are one scalar each** — `B[0]` and `D[0]`. There are no channels. That idea
came from reading `const float *__B` and imagining an array of per-channel scalars; the formula says
otherwise, and the ports are one multiply-add per element with two scalars read once.

## What the guest must still decide

1. **`vDSP_normalize` with a zero spread.** `C = (x - mean) / sd` and `sd` is 0 for a constant input, so the
   division has no answer to copy. Zero, a NaN, or something else — and whether `C == NULL` changes it, since
   `C` is `__nullable` and the header says so deliberately. **The row is not implemented until the guest answers
   both.**
2. **`vDSP_distancesqD` at 8.0.** The emulator's images are 3.x, 4.3, 5.1.1 and the 6.1.3 this band uses
   (`iPhone2,1_10B329`). **There is no 8.0 image**, so this row has no oracle here at all and waits - and
   `vDSP_distancesq` at 5.0 is answered on the 5.1.1 guest, which is the nearest release this emulator holds
   that has it, said rather than glossed.

The macOS arm64 host's answers are candidates for all of this and the oracle for none of it: it has been wrong
twice on rows that are native on 6.0 armv7 — the reduction's order, and the biquad's one-ULP float difference.

## Blocked: vDSP_biquad_SetCoefficientsSingle and _Double

Both are 15.0, and **both act on the release's own `vDSP_biquad_Setup`**, whose layout vDSP.h leaves opaque — the
type is `struct vDSP_biquad_SetupStruct *` and the header says the contents may change between releases and are
to be touched only through the setup routines. That is a different situation from every other row in this band:

- The three **double** biquad rows are implemented because the setup is **the port's own object** from end to
  end — `vDSP_biquad_CreateSetupD` allocates it, `vDSP_biquadD` reads it — so both sides of the comparison are
  the port's and the host's own, and the host is a full oracle.
- `SetCoefficients` is handed a setup **the release allocated**. A port cannot construct one, so the host
  differential has nothing to call it on: the setup type is opaque on both sides and only the release can make
  one.

**So the two rows wait for a guest probe**, after 7e035ac0's install fix, where the probe creates a setup with
`vDSP_biquad_CreateSetup`, calls `SetCoefficients` on it, and observes the change through `vDSP_biquad` — the
setup never being read. **The layout is not guessed, and no host-side row is claimed.**

What a guest probe will still have to settle, because the header does not say it: how many coefficients the
call reads (`__nsec` sections at five each, or something else), what happens to a section's state when its
coefficients change under a filter that has already run, and whether float coefficients are rounded once or
approached — which the multi-section form's `interpolates` flag already models for `SetTargets`.
