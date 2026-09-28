# The single-section biquad of vImage, iOS 6.0 — in progress, and not carried

`vDSP_biquad`, `vDSP_biquadD`, `vDSP_biquad_CreateSetup`, `_CreateSetupD`, `_DestroySetup`, `_DestroySetupD`
in `Accelerate/vDSPBiquad6.m`, measured against the host's own vImage in `tests/backports/host/vdspbiquad6`.

**None of the six is in the registry, and the page says exactly why.** The kernel implements the header's
printed pseudocode exactly, and the host is one ULP away from it in both precisions, on both a stable and an
unstable filter, and the association the host uses has not been identified. Carrying a row that is not
bit-exact is not a thing this library does, so the rows wait.

## What is measured and stands

**The ladder puts all six at 6.0.** `release-split.lua` over the object, from the real caches:

```
vDSPBiquad6.o  _vDSP_biquad  6.0      _vDSP_biquad_CreateSetup   6.0
vDSPBiquad6.o  _vDSP_biquadD 6.0      _vDSP_biquad_CreateSetupD  6.0
vDSPBiquad6.o  _vDSP_biquad_DestroySetup  6.0   _vDSP_biquad_DestroySetupD  6.0
release-split: clean, every object file's symbols first-appear in one release (23 files, 177 symbols, 50 releases)
```

So 4.3 does not have them, the file is needed, and the rows carry `minimum: 4.3` — the convention every one
of the 171 implemented Accelerate rows follows, whatever its `introduced`. **The 4.3 build exports all six**,
measured with `nm -gU` on the gate's `libAccelerateBackports.dylib`, whose 177 exports are exactly the object
set's 177 symbols.

**The delay buffer is 2(M+1) elements, not 2M.** The pseudocode's loop is `for (s = 0; s <= S; ++s)` —
*inclusive* — so M sections are M+1 rows of two. A first version of the differential passed a one-element
`float` delay and the host wrote 2M floats straight over the test's own `sections`, which is what produced a
`SIGSEGV` and a run with no summary line. The `<=` is the whole of that difference.

**A cascade of no sections is a setup, not a refusal, on both creates.** Asked of the host: `vDSP_biquad_CreateSetup(coeffs, 0)`
answers a setup, `vDSP_biquad_CreateSetupD(coeffs, 0)` answers a setup, `vDSP_biquadm_CreateSetup(coeffs, 0, 1)`
answers a setup, and so does the m-form at one section and no channels. `CharonBiquadCreate` already agrees —
it refuses only on no coefficients or an overflow — so **the shared create needed no change and the gated
`vDSP_biquadm*` rows are untouched.**

## The kernel, and the one ULP that is open

The port is the header's printed form, accumulated left to right in the caller's type, with the state in the
caller's `Delay` and no working rows: one register per section for the current sample, shifted into the
caller's buffer once the whole sample has run. Two things in the pseudocode are easy to get wrong and both
were, in this file's own history: the inclusive row count above, and the fact that a cascade's delay pairs
must be shifted **after** the whole sample — updating each pair inside the section loop hands section 2
section 1's value *at n* where it needs section 1's value *at n-1*.

**The port's saved `Delay` now matches the host's own dump**, which is the check that settles the layout:

```
    Delay after the call, the host: 1.25 0.25 0.465946406 0.488799572
    Delay after the call, the port: 1.25 0.25 0.465946376 0.488799483
```

The input's last two samples are `1.25 0.25`, so `Delay[2s] = x[s][N-2]` and `Delay[2s+1] = x[s][N-1]` — the
header is right. **A claim in an earlier version of this page said the host's layout was the opposite, and it
was wrong**: it was read off a probe whose own indexing was broken, and the host's dumped `Delay` disproves it.

**What is open: the host is one ULP from the printed form, and it is not the unstable filter.** A normalised
RBJ low-pass (poles about 0.643) diverges at sample 1–3; the unstable one diverges at sample 5–16 and reaches
50851 with a delay of −2.2e7. So the difference is real arithmetic, present from the second sample in a
well-conditioned filter, in both precisions and at every section count. Contraction is not it: `FPC=off`
builds both sides through `run.sh`'s own flags and the one-section outputs are bit-identical with contraction
on and off, and the band build sets no `-ffp-contract` flag at all.

## The search, and why it has not reported

`brute_forcer` in the differential enumerates **all 105 binary trees over five labelled leaves** (not
Catalan(4) = 14 — that counts shapes for a fixed leaf order) times every subset of the 512 fused-combine
masks, so 53760 variants per precision per filter.

**It has not reported, because control 1 has not passed.** The controls are the point: variant 0 is the
printed form, hand-built, and must reproduce the port's output bit for bit on every sample; and at sample 0
with a zero delay every variant must equal `b0 * x[0]`. **Control 1 currently fails at sample 0 while the
`initial_state` dump in the same run shows the host and the port agreeing on that sample to all nine printed
digits.** Those cannot both be true, so the search's evaluator is wrong and its result is withheld. Four bugs
in that evaluator have been found and fixed — the bipartition loop visited each pair twice, the tree array
was sized for 14 rather than 105, the host's `Delay` was not reset between filters, and the double pass
compared a double result against the *float* form's output — and the controls are what turned the search
from "matches none" into "will not report", which is the correct outcome for a search whose control fails.

## The oracle, and the open item

**This host is the macOS arm64 vImage, and it is not what these rows must match.** They are native on 6.0
armv7, and that is the implementation a 4.3–5.x application calls. armv7 VFP before VFPv4 has no fused
multiply-add, so an answer only a fused combine can produce is one the real target cannot give — and the
macOS host has one. Until a variant is shown to match **in a search whose controls pass**, or the 6.0 armv7
implementation is run through the emulator, this shape cannot be gated bit-exact and the six rows stay out of
the registry. That emulator run is the open item.

## How to run this

```
sh tests/backports/host/vdspbiquad6/run.sh              # the differential
SAN=1 sh tests/backports/host/vdspbiquad6/run.sh        # the same, under AddressSanitizer
FPC=off sh tests/backports/host/vdspbiquad6/run.sh      # the same, with contraction off on both sides
```

`SAN=1` and `FPC=off` are in `run.sh`'s own flags on purpose: the renamed `_charon_host_*` objects have to be
built the way the plain run builds them, or the comparison is between two different builds. An ad-hoc command
that renames differently builds different objects and says nothing — which cost this shape a day.
