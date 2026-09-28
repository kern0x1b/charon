# Mutants for vDSPDFTInterleavedD15.m — the double rows

Applied to a copy under this directory, never to the tree. **The port's object is compiled with the three
`-D` renames and the differential's translation unit is not**, so the differential's host calls keep the
release's own names. The binding is checked before anything is run:

    undefined   _vDSP_DFT_Interleaved_CreateSetupD  _DestroySetupD  _ExecuteD   the release's
    defined     _charon_host_…D                                                the port's

| mutant | result |
| --- | --- |
| a twiddle's sign flipped | 8 of 17 red |
| the real forward's x2 dropped | 4 of 17 red |
| the packing swapped at element 0 | 4 of 17 red |
| DC's O_0 term dropped | 4 of 17 red |
| the inverse's (-1)^j term dropped | 4 of 17 red |
| the exponent floor lowered from 2 to 1 | 1 of 17 red |
| the factor table grown to the header's 5*5 | **1 of 17 red** |

The unmutated double port: **17 checks, 0 failures, worst ratio 0.000**.

**The 0.000 is a real result here and was not one in float**, and the difference is the binding check. In
double the release's transform is the same direct sum, so the port matches it exactly; in float the port's
arithmetic differs by ULPs and the bound carries it, at 1.401. Both numbers are against a host that `nm` shows
to be the release's.

**The last mutant only fails because of the previous commit.** Growing the factor table to the header's
`f = 5*5` while the loop still read five was inert; `sizeof factors / sizeof *factors` made the bound follow
the table, so the mutation is breakable. That is the fix generalised, measured rather than asserted.
