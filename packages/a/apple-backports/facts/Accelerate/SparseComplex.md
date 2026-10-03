# The complex sparse BLAS of vecLib/Sparse/BLAS.h (iOS 18.5)

The fifty-eight entry points `Accelerate/SparseComplex18.m` defines, in the float complex and the double
complex of each: the whole complex half of `Sparse/BLAS.h`. Behaviour here is the host's own, measured
case by case by `tests/backports/host/sparseblas/differential-complex.m`, which runs that file and the
host's own Accelerate over the same inputs and compares a status, a count and every element. **170
checks, 0 failures** (`sh tests/backports/host/sparseblas/run.sh`).

Read with `facts/Accelerate/SparseBLAS.md`, which is the real family's file: the storage is the same
(CharonSparseBLAS.h), the refusals are the same, and where this file says "as the real family does" that
is the reference. What follows is only what the complex half does differently, and the five places
where the host cannot be the oracle.

## The release, and why one object file

No release this port supports exports any of the fifty-eight. Measured over the fifty-one rungs of the
ladder this port holds (1.1.4 through 18.0, read through `tools/cache-index/first-rung.py`), the first
held rung carrying any of them is `NONE`, and the 26.2 header that declares them puts every one of them
at 18.5. They are one object file because they are one release. The iPhoneOS 16.4 SDK this package
compiles against declares none of them, so they are transcribed into
`packages/a/apple-backports/Accelerate/CharonSparseComplex26.h`.

The imports the object does carry are the release's own and resolve on every band: `cblas_ccopy`,
`cblas_zcopy`, `cheev_` and `zheev_` are all first exported by 3.2, and the oldest band this port
supports is 4.0 (the same measurement SparseBLAS.md makes for the real family's `cblas_saxpy`).

## No `_Complex` operator is ever applied to two complex values

A complex product and a complex quotient are the only two operations where the C99 operators need a
helper the compiler calls out to. Measured by compiling a translation unit that multiplies and divides
`float _Complex` and `double _Complex` for `armv7-apple-ios6.0`: the only names left undefined are
`__mulsc3`, `__muldc3`, `__divsc3` and `__divdc3`. Addition, subtraction and a real scaling need none of
them (the same object leaves them all defined), so they are written with the operators in
`CharonSparseComplex.h`, and the two that would need a helper are spelled out there - the product as
`(ar br - ai bi) + (ar bi + ai br)i`, and the quotient by Smith's algorithm, which divides by a real
number once. A complex value is a pair of doubles throughout, and a value is rounded to the width its row
stores when it is written, which is the rule the real family follows when it stores a float through a
double.

A zero divisor is not a special case and needs none: `1/0` is an infinity, an infinity times zero is a
NaN, and the arithmetic carries it into a NaN in both parts. That is what the host's own zero pivot
answers (measured: the lower triangular `[[0,0],[0,1]]` against `(1,1)` gives a NaN in both parts of both
elements).

## The release's complex BLAS does not do a complex alpha

Measured on the host (macOS 27.0), calling it directly with `alpha = 2+i` and the vector element `2+i`:

| call | answer | the product |
| --- | --- | --- |
| `cblas_caxpy(1, alpha, x+1, 1, y, 1)` | `4+2i` | `3+5i` |
| `cblas_caxpy(1, alpha={0,1}, x+1, 1, y, 1)` | `0+0i` | `-1+2i` |
| `cblas_zaxpy(1, alpha, x+1, 1, y, 1)` | `4+2i` | `1+4i` |

Both read the real part of `alpha` and discard the imaginary one: the first answer is exactly
`2 * (2+i)`. Every factor in this family is complex, so delegating the multiply-add would drop the
imaginary part of every product of every level-2 and level-3 call. **The multiply-add is the port's own
pair arithmetic.** The gather beside it is the release's own `cblas_ccopy` / `cblas_zcopy`, which is
measured to copy both parts of a value and to honour the increment (two elements at an increment of 2
give the first and the third).

The real family keeps its `cblas_saxpy` / `cblas_daxpy`: its factor is a real `alpha`, which those handle
correctly, and that is the real family's own measured behaviour. This is the one place where the two
halves of the family take different routes and the reason is a measurement, not a preference.

## Two measured rules that are not the real family's

**The inner products do not conjugate.** For `x = {3+4i, 1}` and `y = {1+i, 2}` the host answers `1+7i`
for `sparse_inner_product_dense_float_complex`, which is `x.y` term by term; `9-i` is what `conj(x).y`
gives. Both the dense and the sparse-sparse forms are the bilinear form.

**The one norm is the sum of the parts, not the sum of the moduli.** For the values `{3+4i, 1}` the host
answers `8`, which is `(3 + 4) + 1`; the sum of the moduli is `5 + 1 = 6`. The two norm and the infinity
norm are over the moduli - the same vector answers `sqrt(26)` and `5`. This is true of the vector norms
and of the matrix ones: for a matrix whose entries are `3+4i` at `(0,0)`, `1` at `(1,0)` and `-2+i` at
`(1,2)`, the elementwise norms answer `11`, `5.56776` and `5` for one, two and infinity, and the operator
ones answer `8` and `7`. A vector answers zero in a count of zero, a norm the enumeration does not name
is answered as `SPARSE_NORM_INF`, and `SPARSE_NORM_R1` is answered as `SPARSE_NORM_TWO` for a vector and
as a NaN for a matrix - all measured, and the same two fallbacks the real family has.

The operator-two norm is the release's own LAPACK, `cheev_` / `zheev_` over the Hermitian Gram matrix
`A * A'`, and that is the exact answer: the host answers `5.12196` for the matrix above where the exact
largest singular value is `5.12206`, the square root of the larger root of `t^2 - 31t + 125`. That is
the one case in this family with a tolerance, it is `3e-3` in the differential, and it is the host that is
the approximation - the same situation SparseBLAS.md records for the real family's two-norm, where the
port's answer is also the eigen-decomposition and also the exact one.

## Where the host cannot be the oracle

Five places, each named in the differential's case names and each checked against the header's own rule
instead. A differential that cannot ask the host is still a differential: the expectation in each of
these is written out from the header in the test, and it is not the code under test that produces it.

1. **A complex alpha anywhere.** Everything above. The affected cases are the two products, the outer
   product and the matrix-vector product at a complex `alpha`; every one of them is compared against a
   product written out by hand in the test.
2. **A transpose the enumeration does not name, in a matrix-vector product.** The host hands it to
   `cblas_cgemv`, which prints `BLAS error: Parameter transpose passed to cblas_cgemv was 77, which is
   invalid` and ends the process. The port refuses it, which is what the header says.
3. **A zero increment, in a matrix-vector product.** The host hands it to `cblas_cgemv` and the process
   ends. The port folds the increments into the addresses, so every row's result lands on the one element
   the increment names and the elements between are untouched; the differential checks that against a sum
   of three products written out in the test.
4. **A leading dimension below what the layout needs, in either triangular solve, and an order the
   enumeration does not name.** The host hands it to `cblas_ctrsm` and walks off the caller's buffer.
   The real family's differential never asks the host for an `ldb` below what the layout needs for the
   same reason.
5. **A row permutation whose target is outside the matrix or is the row itself.** Measured: the host
   answers `SPARSE_SUCCESS` for `{5,5}` on a 2x3 matrix and leaves row 0 holding denormals and a `1e29`
   - it writes through its own row array - and the matrix then cannot be destroyed either (the run ends
   with a SIGBUS). The port skips such a target, which is what the swap loop the header writes out does,
   and the differential checks the port against that loop run over a plain array of the six entries.

Three more, smaller: a matrix that is not one of ours is never handed to either side (the host
dereferences a foreign pointer - measured: `sparse_elementwise_norm_float_complex` on `0x1234` is a
SIGBUS), a `row_end` of `NULL` and the trace at an offset of 4 or more on a 3x3 (measured: offsets -6 to
3 answer, 4 is a SIGBUS).

## One place the host answers two different things

A value of exactly zero, inserted into an empty row. With sequenced statements in a fresh process the
host stores it and counts it - `nz` goes 1, 2, 2 for the insertions `0@(0,1)`, `2@(1,0)` and `0` over
`(1,0)`, and row 0 holds one entry - and the extract answers `0+0i` for it. Inside the differential's
process, the same three insertions answer `nz = 1` with row 0 empty, which is the answer as if the zero
had been dropped; and the host's own **real** family answers the dropped one, where `sparse_insert_entry_float`
answers `nz = 1` with row 0 empty for the same sequence.

A behaviour that differs between two runs of the same calls on the same build is not a contract. The port
follows the real family's own rule - the entry is stored and counted - which is also what
`sparse_insert_entry_float_complex` is documented to do, and the differential checks that rule against the
port and records the host's two answers rather than picking one of them. **The real family has the same
divergence and its differential does not cover the case**, which is worth a decision of its own and is
reported to the coordinator.

Two further measurements came out of writing the harness, both of which cost real rounds and are the kind
of thing a reader will otherwise repeat:

- `(float)(a + b * 1.0fi)` keeps the **real part only**. Six places in the first version of the
  differential had it and every one of them silently built a matrix with no imaginary parts, after which
  the port and the host agreed on a wrong answer. The imaginary part has to be multiplied in after the
  cast.
- `printf("%d", f(x()), g(y()))` does not sequence `f` before `g`. Three host probes read
  `sparse_get_matrix_nonzero_count` in the same `printf` as the insertion it was supposed to follow and
  reported the count from before it, which is what sent this section the wrong way twice.

## What changed in the shared helpers

Five statics moved out of `SparseBLAS9.m` into `CharonSparseBLAS.h` without a change of behaviour -
`CharonSparseMake`, `CharonSparseRepeated`, `CharonSparseWritable`, `CharonSparsePutEntry` and the two
permutations - because this file needs all of them and a function defined in a file that exports an API
symbol is left out of a band the release already has, which is how a shared C function becomes an
undefined symbol in a later band only. The real family's differential still answers **368 checks, 0
failures** after the move, which is the check that it is the same arithmetic.

One of them changed behaviour, and it is a fix rather than a port of the complex rule:
`CharonSparsePutEntry` refused an index past the end of a matrix but not a **negative** one, so
`sparse_insert_entry_float(A, v, -1, 0)` read `row[-1]` and wrote outside the allocation. Measured on the
host, for the real type and for the complex one alike, all four of `(3,0)`, `(0,3)`, `(-1,0)` and `(0,-1)`
against a 2x2 answer `SPARSE_ILLEGAL_PARAMETER` and change nothing. The guard is now there for both
types.

## What the differential covers

`sh tests/backports/host/sparseblas/run.sh` builds `SparseBLAS9.o`, `SparseProduct10.o` and
`SparseComplex18.o` with every `sparse_*` name the registry carries renamed, and runs two binaries over
them: the real family's `differential.m` (**368 checks, 0 failures**) and this family's
`differential-complex.m` (**170 checks, 0 failures**). Between them every one of the fifty-eight names
is called on both sides with a real and a double value where the two paths differ, and each refusal the
list above is exercised.
