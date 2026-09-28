# Mutants for vDSPDFTInterleaved15.m

Applied to a **copy** of the port under this directory, never to the tree. **The port's object is compiled
with the three `-D` renames and the differential's translation unit is compiled WITHOUT them**, so the
differential's host calls keep the release's own names. The earlier arrangement passed `-D` to both, which
renamed the host calls to `charon_host_*` as well and made the port's output the answer on both sides.

Proof the two sides are distinct, from the binary:

    undefined   _vDSP_DFT_Interleaved_Execute                    the release's, bound to Accelerate
    defined     _charon_host_vDSP_DFT_Interleaved_Execute       the port's

## The six

| mutant | result |
| --- | --- |
| a twiddle's sign flipped | **8 of 17 red** — the complex-to-complex forward at N 8 first |
| the real forward's x2 dropped | **4 of 17 red** — the real-to-complex forward at N 8 first |
| the packing swapped at element 0 | **4 of 17 red** — the real-to-complex forward at N 8 first |
| DC's O_0 term dropped | **4 of 17 red** — the real-to-complex forward at N 8 first |
| the inverse's (-1)^j term dropped | **4 of 17 red** — the real-to-complex inverse at N 8 first |
| the header's 5*5 length accepted back | **0 of 17 — NOT DETECTED** |

The unmutated port: **17 checks, 0 failures**, worst ratios 0.820 (real-to-complex inverse) and 1.401 (the
real-to-complex forward) at N = 32, against the bound 1.538. **Not bit exact** — the port differs from the
release by ULPs and the bound is what holds it, which is what the bound is for.

**The sixth mutant does not go red, and that is a gap in the length check, not a pass.** Accepting
`f = 5*5 = 25` should make the port accept 25 * 2**n for n >= 2 — 400 is inside the 1 to 1024 sweep and the
host refuses it — so the accept/refuse comparison should disagree. It does not, and the reason has not been
looked at. The row's own record says so; the length rule is not yet covered by a failing mutant.
