# quadrature_integrate, iOS 10.0 - a native C translation of QUADPACK, held against the host

`quadrature_integrate` in `Accelerate/Quadrature10.m`, one row, checked case by case against the host's own
Accelerate by `tests/backports/host/quadrature`: **86 checks, 0 failures**, with three mutations of the port
red at 5, 1 and 48 failures and each reverted byte-identically.

The header says the QNG and QAG integrators "are C ports of the QUADPACK library corresponding routines" and
that QAGS "provides the functionality offered by the QAGS and QAGI QUADPACK routines", so the reference is
netlib's `dqng.f`, `dqags.f`, `dqagse.f`, `dqagie.f`, `dqk15.f`, `dqk15i.f`, `dqk21.f`, `dqk31.f`, `dqk41.f`,
`dqk51.f`, `dqk61.f`, `dqelg.f` and `dqpsrt.f` (public domain), transcribed statement for statement, with the
host as the oracle for everything QUADPACK leaves to the implementation. The six node tables and the four
tables of `dqng.f` are generated from the Fortran `DATA` statements by `tables.py`, which `run.sh` checks
before it builds anything; `all 29 tables hold the 406 values their DATA statements give`.

## Where the port follows the host rather than the Fortran, and the measurement for each

Four sites. Each carries dqagse.f's own line beside it in the source, so a reviewer can read the original.

1. **The first pass stops when its own estimate is inside the tolerance.** `dqagse.f` also asks for
   `abserr.ne.resabs`, which for these integrals is 1.57 against a tolerance of 1e-13 and so cannot fail; the
   host does not ask it. Measured over 1/(1+x^2) from -1 to 1 at 1e-12: the 21-point rule's first pass estimates
   7.1215e-08 and the host subdivides once, three calls of 21 points; the 31-point rule's estimates 1.30239e-13
   and the host stops there, one call of 31; the 51-point rule's 1.74393e-14 and it stops there.
2. **The limit flag is raised before the tolerance test for QAGS and after it for QAG.** Over the same
   integral at `max_intervals` 2 both make three calls of 21 and end inside the tolerance with an error of
   1.74393e-14: QAGS answers -101, QAG answers 0.
3. **`dqagse.f`'s two roundoff flags are not raised for QAGS.** `ier = 2` at
   `abserr.le.1.0d+02*epmach*defabs.and.abserr.gt.errbnd`, and `ier = 2` at
   `iroff1+iroff2.ge.10.or.iroff3.ge.20`. QUADPACK's `dqags` is `dqagse` and nothing else - `call
   dqagse(...)` is its whole body - so it raises both. The host raises both for QAG and neither for QAGS.
   Measured over 0..1 at a 1e-300 tolerance for x^2, sin, 1/(1+x^2) and exp(-x), where each first pass's
   estimate is inside `100 * DBL_EPSILON * defabs` and far outside the tolerance: QAG answers
   QUADRATURE_INTEGRATE_BAD_BEHAVIOUR_ERROR after one pass of 21 points, QAGS subdivides to `max_intervals`
   and answers QUADRATURE_INTEGRATE_MAX_EVAL_ERROR, 199 passes over 4179 points at `max_intervals` 100, every
   one. On 1/(1+100 x^2), whose estimate 1.6332757290306007e-15 is inside 3.2659e-15, QAG stops at pass 10 over
   399 points in 19 batches with -102 at every limit from 10 to 100 while QAGS answers -101 at every limit and
   runs to it: nine passes at limit 5, nineteen at 10, thirty-nine at 20, a hundred and ninety-nine at 100. The
   threshold is the Fortran's own: at a tolerance of 4e-15 both integrators stop after one pass with
   QUADRATURE_SUCCESS and at 1e-15 they part company.
   **This costs the port QUADPACK's detection of the roundoff case for QAGS**, which is the one place where
   following the host and following the reference come apart in the value the caller sees, and not only in the
   number of passes.
4. **The host's infinite-bound QAGS is not `dqagie`, and the port does not imitate it.** See below.

## The infinite bound, measured

`dqagie.f` makes one 15-point `dqk15i` pass and asks for nothing else. The host alternates a call of 15
transformed abscissae with a call of 21 abscissae over (0,1) itself. Over 1/(1+x^2) from 0 to infinity it
answers in three batches - 15, 21, 15 over 51 points - where the port answers the same value, 1.5707963267948966
exactly, in six batches. Over exp(-x) from 0 to infinity: 15, 21, repeated to eleven batches and 195 points,
against the port's eighteen. Over 1/(1+100 x^2) from 0 to infinity: 15, 21, 15, 21 and then 21 alone, seven
batches and 135 points.

**What this costs and what it does not.** The port's answer is `dqagie`'s, and it is right: 1.5707963267948966
against pi/2, 1 against 1, and 0.15707963267948963 against atan(10)/10 = 0.15707963267948966, in each case
within one ULP of the host's own answer and inside the tolerance asked for. The batching is not part of the
header's contract - a callback sees the same points however they are grouped - so `differential.m` prints both
sequences on every such case and asserts only the answer, the status and the count where the bound is finite.

**The 21-point batch is not a second rule for the same integral.** Its abscissae are t itself, symmetric about
0.5, in the 21-point Kronrod's own structure, and v-tail-a3 measured that an integrand answering 1e10 where
that batch puts its centre point moves the host's answer by 3.8e-8, not by a weight times 1e10 - so its values
reach the answer only weakly. Reproducing what the host computes from it is not done here; it is the open half
of this row's oracle work and the next session should start by asking the host for that batch alone (a
tolerance that makes only the first 15-point pass fire, with the callback recording the batch's abscissae and
values) rather than by trying to infer it from the answer.

**A bound at an infinity with an integrand that has no finite integral there** is checked against QUADPACK's
own promise and not against the host: over x^2 from 0 to infinity the host answers QUADRATURE_SUCCESS with
5.5384500034908009e+34 and an estimate of 3.9108e+26, and over sin from 0 to infinity -647.55276816795913
with -101. QUADPACK's `dqagie` answers `ier = 1` ("the number of subintervals reached LIMIT") or `ier = 3`
("the integral is divergent, or the absolute error is maximal") for exactly that, which the header maps to -101
and -102, and the port answers -101 and -102. The case asserts the error and records both answers.

## The estimate cannot be compared between two builds, and is not

The differential used to require the port's `abs_error` to agree with the host's to 1e-6 relative. It cannot,
and the measurement is on both sides of the claim.

**The estimate is a cancellation-amplified quantity.** QUADPACK computes
`abserr = resasc*hlgth*min(1,(200*raw/resasc)^1.5)` with `raw = |resk-resg|*hlgth`. For these integrands `raw`
cancels four digits against `resk` - 1.9078066e-5 against 0.2942255 for 1/(1+100 x^2) on 0..1 - so one ULP in
the 21-point answer moves `raw` by 5.8e-12 relative and the estimate by 8.7e-12 relative. The amplified factor
has no bound, since it grows as `raw` falls, so no fixed tolerance separates two implementations.

**The port's numbers are QUADPACK's.** Over 1/(1+100 x^2) on 0..1 the 21 abscissae the two sides hand the
callback are bit-identical (dumped as bits, 63 of them over `max_intervals` 2, and identical), all 29 tables
are bit-identical, and `dq21.f`'s own statements computed by the compiler in a separate program over the port's
own tables give

```
QUADPACK resg = 0.29420645049898181   resk = 0.29422552856490269   abserr = 0.00020524906934811635
port                                                       0.14711276428245135   0.00020524906934811635
host                                                       0.14711276428245137   0.00020524906934901214
```

so the host's `resk` is one ULP above QUADPACK's and everything else follows from that one ULP.

**The host does not agree with itself.** Over the same integrand from -1 to 1 at 1e-12, its QAG reports
`0.29422553486074693` with an estimate of `3.276688748373941e-15` and its QAGS `0.29422553486074687` with
`3.2661123246874664e-15` - two values two ULP apart and two estimates 3.2e-3 relative apart, over one integral.
Over 1/(1+x^2) from -1 to 1 the values agree and the estimates differ by 4.4e-10 relative.

So the case asserts the header's own statement instead, with the exact integral computed in the same program
from the integrand's antiderivative: on success `fabs(result - exact) <= fmax(abs_tolerance,
rel_tolerance*fabs(exact))`, and an estimate of the absolute error does not come back below the error it
reports. That is stronger where it matters - a wrong value, a wrong status and an understating estimate all
fail - and it does not ask for bit-identity with another build's binary.

## What has not been run

No device or emulator call test has been run for Accelerate in this port at all, so every answer on this page is
a host measurement and a device-unverified one.