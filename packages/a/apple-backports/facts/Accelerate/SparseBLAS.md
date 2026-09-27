# The sparse BLAS of vecLib/Sparse/BLAS.h — the 69 entry points of iOS 9

`Accelerate.framework`'s `vecLib/Sparse/Sparse.h` is `Types.h` and `BLAS.h`: a sparse matrix of float or
double, the inserts and extractions that fill one, the three levels of the sparse BLAS over it, and the
vector utilities. Sixty-nine names, arrived in iOS 9, and this port carries every one of them.

Nothing here is a port of Apple's code. The header declares the interface and the arithmetic is written
here, over the BLAS and the LAPACK the release itself exports. Source of the interface: the header of
iOS 16.4,
`System/Library/Frameworks/Accelerate.framework/Frameworks/vecLib.framework/Headers/Sparse/Types.h` and
`…/Sparse/BLAS.h`, with the declarations the port is compiled against and the documented contract.

## What the releases this port supports have: measured, symbol by symbol

The ladder was walked one symbol at a time with `dyld.first_releases` over every cache this port holds —
the armv7 and armv7s of 2.2.1, 3.0, 3.1.3, 3.2, 4.0, 4.2.1, 4.3, 4.3.5, 5.0, 5.1.1, 6.0, 6.0.2, 6.1,
6.1.3, 6.1.4, 6.1.6, 7.0, 7.0.1, 7.0.6, 7.1, 7.1.1, 7.1.2, 8.0, 8.0.2, 8.1, 8.1.1, 8.1.2, 8.1.3,
8.2, 8.3, 8.4.1, 9.0, 9.0.2, 9.1, 9.2, 9.2.1, 9.3, 9.3.5, 9.3.6, 10.0.1, 10.1.1, 10.2, 10.2.1, 10.3,
10.3.4 and the arm64 or arm64e of 11.0, 12.0, 16.0 and 18.0, where a release has no armv7 — against the
iOS 16.4 SDK, so a name counts as exported only where a client binds it. The results:

| family | rows | first release any held cache exports |
| --- | --- | --- |
| this one, the 67 names of `SparseBLAS9.m` | 67 | 9.0 |
| this one, the two names of `SparseProduct10.m` | 2 | 10.0.1 |
| the complex variants `_complex` | 58 | no release at all |
| the `Sparse*` and `_Sparse*` solve entry points | 158 | 11.0 for 57 of them, 16.0 and 18.0 for the rest, and no release at all for the remainder |
| `BNNS*` | 139 | 10.0.1 for 6, 11.0 for 1, 16.0 for 83, 18.0 for 45 and no release at all for 4 |
| **the control: the 35 `cblas_*`, `ssyev_`, `dsyev_` and LAPACK names this port imports** | 35 | **4.0** |

Three things follow, and the last one is the load-bearing one:

1. **Nothing here is on any release this port supports.** The last of them is 6.1.3 and the earliest of
   this family is 9.0, two releases later; the `Sparse` framework itself arrives after the newest release
   this port supports. So every band builds this family and there is nothing to leave out.
2. **One object file may not carry two releases' symbols**, and this family does: `sparse_matrix_product_
   sparse_float` and `sparse_matrix_product_sparse_double` first appear at 10.0.1 while the other
   sixty-seven appear at 9.0. They are therefore the object file of their own
   (`Accelerate/SparseProduct10.m`, registry `ios10sparseproduct.json`, `introduced` 10.0.1) and the other
   sixty-seven are `Accelerate/SparseBLAS9.m` (registry `ios9sparseblas.json`, `introduced` 9.0). This is
   the same defect `tools/release-split.lua` exists to find — SCNLightTypeProbe was declared 10.0 and
   exported at 9.0 — and the build would have linked a band whose file spans two releases.
3. **Every name the port imports is exported from 4.0**, the oldest rung held, so `cblas_sgemv`,
   `cblas_dgemv`, `cblas_sger`, `cblas_dger`, `cblas_saxpy`, `cblas_daxpy`, `cblas_sdot`, `cblas_ddot`,
   `cblas_scopy`, `cblas_dcopy`, `cblas_sswap`, `cblas_dswap`, `cblas_sscal`, `cblas_dscal`, `cblas_ssyrk`,
   `cblas_sgemm`, `cblas_dgemm`, `ssyev_`, `dsyev_`, `ssyevd_`, `ssygvd_`, `sgesv_`, `dgesv_`, `spotrf_`,
   `dpotrf_`, `sgels_`, `sgetrf_`, `sgetrs_`, `dgetrf_`, `dgetrs_`, `sgeqrf_`, `sorgqr_`, `sgeqp3_`,
   `sposv_` and `dposv_` all resolve on the 4.3 band and on the 6.1.3 one. That is the control the ladder
   measurement needs: "no release exports it" means nothing unless the same walk finds the symbols it is
   known to export, and this walk finds thirty-five.

### The 58 `_complex` variants: measured, and NOT yet carried

The iOS 26.2 SDK this port has, at `$HOME/Git/projects/ios/charon/.agent-work/sdk-26.2/iPhoneOS26.2.sdk`,
declares all fifty-eight in its own `Sparse/BLAS.h`, and `Sparse/Types.h` adds the two matrix types
`sparse_matrix_float_complex` and `sparse_matrix_double_complex`. The declarations are the sixty-nine
beside them with `_Complex` substituted, and a transcription of them, the two matrix types completed with
the same body the real ones have, and an implementation of all fifty-eight are written and held in this
worktree's `.agent-work/wip/sparsecomplex/` — `SparseComplex18.m` (1 700 lines), `CharonSparseComplex.h`
(the fifty-eight declarations) and `host/differential.m`, the host differential.

**They are not in this delivery, because their host differential is red**: 158 checks pass and 41 fail.
A library whose own check is red is not "implemented", and the rules do not allow it to be. What the
work established, all of it measured and all of it re-usable, is this:

- **The host's own Accelerate carries all fifty-eight.** Measured with `dlsym` over the fifty-one names
  asked there: fifty-one present, none absent. So the whole complex half can be held against the host,
  half by half, and there is no oracle missing.
- **The ladder puts all fifty-eight at no release at all**, not even at 18.0 (in the table above), so
  they are one release class and would be one object file.
- **A value of exactly zero is not stored in the complex half, and is stored in the real half.**
  Measured: a batch of five distinct entries of which one is exactly zero leaves a real matrix's nonzero
  count at 5 and a complex one's at 4. So the complex half leaves a zero value out of the structure
  entirely, and an overwrite with zero leaves it out too. The real half keeps it (measured: an entry of
  `0.0` inserted into an empty matrix leaves its count at 1). This one rule fixed five of the failures.
- **The three complex vector norms are not the moduli-based ones the real half uses.** Measured, on
  `{1, 0, 3 - i}` at columns `{0, 2, 3}` with `nz = 3`, the one, two and infinity norms answer
  **5, 3.31662 and 3.16228**, and on a single value `{3 - i}` they answer **4, 3.16228 and 3.16228**:

  | norm | the host's answer | the reading |
  | --- | --- | --- |
  | `SPARSE_NORM_ONE` | 5, and 4 for one value | the sum over the values of `\|re\| + \|im\|` — `1+0+3+1` and `3+1` |
  | `SPARSE_NORM_TWO` | 3.31662, and 3.16228 | the root sum of the squared moduli — `sqrt(1+0+9+1)` and `sqrt(9+1)` |
  | `SPARSE_NORM_INF` | 3.16228, and 3.16228 | the same root sum of squares, **not** the largest modulus, which would be 3 for that one value |

  A pure imaginary value is a nonzero value: `sparse_get_vector_nonzero_count_double_complex` over
  `{0, 2, 0, 4i, 5, 0}` answers 3, and `sparse_pack_vector_double_complex` over it answers the three
  entries at columns 1, 3 and 4 with the right values.
- What is still red, and is what a next session starts from: the two complex triangular solves (16
  failures between them), the complex matrix-vector product (8), the complex pack (6), the complex matrix
  norms (5), the complex vector norm for the two names the host does not answer as the two-norm (3), one
  extraction of a batch, and one outer product.

The port's own BLAS is not the obstacle: the ladder puts `cblas_caxpy`, `cblas_ccopy`, `cblas_zaxpy`,
`cblas_zcopy`, `cblas_cgemv`, `cblas_zgemv`, `cblas_cgemm`, `cblas_cherk`, `cblas_ctrsm`, `cblas_cscal` and
`cblas_zscal` at 4.0, and `ssyev_`/`dsyev_` at 4.0, while `cblas_cger`, `cblas_zger`, `cblas_cdotu`,
`cblas_cdotc` and `cblas_zdotu` are exported by **no release at all** — which is why the rank-one update
in both halves is an axpy and the inner product in both is a loop.

## What the arithmetic is made of

A matrix is a list of rows, each a run of `(column, value)` pairs kept sorted by column
(`Accelerate/CharonSparseBLAS.h`). That is the whole storage, and every operation is either a walk of the
stored entries or a call into the release's own BLAS over one of them:

| operation | what it is made of |
| --- | --- |
| `sparse_matrix_product_dense_*` | the release's `cblas_scopy` gathers the row of `B` a stored entry names and `cblas_saxpy` adds `alpha` times the entry's value times it to the row of `C` — one rank-one update per nonzero, the sparse level-3 kernel |
| `sparse_matrix_product_sparse_*` | the same update with the row of `B` taken from `B`'s own stored entries |
| `sparse_matrix_vector_product_dense_*` | the release's `cblas_saxpy` over the single product of each stored entry, with the address of the element computed here |
| `sparse_operator_norm_*` with `SPARSE_NORM_TWO` | the Gram matrix `A A'` and the largest of its eigenvalues, through the release's LAPACK `ssyev_` / `dsyev_` |
| `sparse_vector_triangular_solve_dense_*`, `sparse_matrix_triangular_solve_dense_*` | the sparse substitution over the stored entries, `O(nnz)`; a dense `cblas_strsv` would spend `O(n^2)`, which is the reason a caller reached for a sparse matrix |
| the norms, the trace, the inner products, the permutations, the vector utilities | the arithmetic the header writes out — irregular indices, a maximum, a diagonal — none of which has a dense BLAS form |

Two of those need their reason stated, because they are the two places a shorter version would be wrong.

**The stride never reaches the BLAS.** `cblas_saxpy` on this host treats an increment that is not positive
as one — measured: a single call with `incY = 0` and another with `incY = -1` each leave every element
but the first alone — so the address of the element is computed by the port and the release's function is
given that address and an increment of one. That is what makes an increment of zero and a negative one
answer as the header says.

**CLAPACK takes its scalars by pointer.** `vecLib/Headers/clapack.h` declares `ssyev_("N", "L", &n, a,
&lda, w, work, &lwork, &info)` and the release's own functions read them there, so that is the call the
port makes.

## What was measured, and where the host was asked

Every behaviour on this page is a measurement of the host's own Accelerate on macOS, taken case by case by
`tests/backports/host/sparseblas`, which runs this port's own `SparseBLAS9.m` and the host's library over
the same inputs and compares every status, every count and every element: **355 checks, 0 failures**. The
discovery probes the cases were first taken with are `probe.m`, `probe2.m` and `probe3.m` beside it.

The measurements that fix the contract, all of them from that host run:

- **A dimension of zero is accepted.** `sparse_matrix_create_float(0, 5)`, `(5, 0)` and `(0, 0)` each
  answer a matrix whose row and column counts are what was asked, and so do
  `sparse_matrix_block_create_float(0, 3, 2, 2)` and `(3, 3, 0, 2)`, and a variable-block matrix whose `K`
  or `L` contains a zero. The header says a dimension "must be greater than 0"; the host accepts them and
  the port does too.
- **A row and column count is in elements.** A matrix built by `sparse_matrix_block_create_float(3, 3, 2,
  2)` reports 6 rows and 6 columns, and one built with the block heights `{2,1,3}` and the block widths
  `{1,2,1}` reports 6 and 4.
- **A block dimension is the size of the block the element is in, not of the block row it names.** For
  those heights and widths the host answers 2, 2, 1 for element rows 0, 1 and 2 — row 1 is in block 0, so
  it answers block 0's height — and 1, 2, 2 for element columns 0, 1 and 2. Zero for a point-wise matrix,
  for an index past the last element, for a negative index and for a `NULL`.
- **A stored entry and a nonzero value are two different things.** Inserting `0.0` into an empty matrix
  leaves its nonzero count at 1, inserting over it leaves it at 1, and a block entry of `k` by `l` adds
  `k * l`. So the count counts entries, and a product of exactly zero is not stored — the outer product
  `alpha * x * y'` with `alpha = 2`, `x = (1,1)` and `y` at columns 0 and 2 answers a matrix whose count
  is 4, not 6.
- **An entry of the wrong kind is refused.** A point entry into a block matrix and a block entry into a
  point-wise matrix both answer `SPARSE_ILLEGAL_PARAMETER` and store nothing.
- **The four properties are bits, and any name is remembered.** A name of `-1` to `-9` answers
  `SPARSE_ILLEGAL_PARAMETER`; 0, 1, 2, 3 and 99 answer `SPARSE_SUCCESS`; and the name 3 reads back as 3,
  which is a matrix carrying `SPARSE_UPPER_TRIANGULAR` and `SPARSE_LOWER_TRIANGULAR` at once. A read
  answers the name when every bit it has is set and 0 when any of them is not: a matrix with the upper
  and lower triangular bits set reads 1, 2 and 3 for those three names and 0 for the two symmetric ones.
  Once a value has been inserted every name answers `SPARSE_CANNOT_SET_PROPERTY`.
- **The row extraction returns a count, not a status.** The indices written are absolute columns, not
  offsets from `column_start`; `column_end` is `column_start` when `nz` is zero whatever the row holds,
  and otherwise the column of the next stored entry after the ones written or the number of columns when
  there is none. The column extraction is the same on the rows: a column with one entry at row 1, read
  from row 0, answers one entry and the number of rows. A row, a column or a starting index outside the
  matrix, and a negative one, answer `SPARSE_ILLEGAL_PARAMETER`.
- **The permutations are the header's swap loop, not a gather.** On `[[1,2,3],[4,5,6]]` the row
  permutations `{1,0}` and `{0,1}` leave the rows where they are and `{0,0}` and `{1,1}` swap them; the
  column permutations `{1,0,0}` and `{0,1,0}` reverse the three columns, `{2,0,1}` gives
  `[[2,1,3],[5,4,6]]`, and `{0,2,1}`, `{2,1,0}` and `{0,1,2}` leave them. The loop is what produces
  every one of those, and a gather would not.
- **`SPARSE_NORM_R1` is answered where the host answers it.** A matrix treats it as `sum over j of
  sqrt(sum over i of A[i,j]^2)` — 11.9541 for `[[-1,2,-3],[4,0,-5]]` — a vector treats it as the
  two-norm (3.16228 for `{1,0,3}`, where the two-norm is 3.16228), and the operator form of it answers
  `NaN` because the header says a matrix does not support it. A name the enumeration does not name is
  answered as `SPARSE_NORM_INF` everywhere, and 0 for every norm of an empty matrix.
- **A triangular solve needs the property.** A matrix with no `SPARSE_UPPER_TRIANGULAR` and no
  `SPARSE_LOWER_TRIANGULAR` is refused with `SPARSE_ILLEGAL_PARAMETER` and the right-hand side is left
  alone. A pivot of exactly zero divides, so the answer is an infinity and then a `NaN`.
- **The trace's negative offset is `A[i - offset, i]`, not `A[i + offset, i]`.** Measured on a 3x4 whose
  diagonal is 2, 4 and 0 and whose first superdiagonal is 3 and 5: the offsets 0, 1 and -1 answer 6, 8
  and 0, which is the header's own spelling and not the other one.

### The one rule the measurements settled against the header: `alpha` divides

`vecLib/Sparse/BLAS.h` writes both triangular solves as "x = alpha * T^-1 * x", which reads as scaling the
solution. The host does not do that: it divides the right-hand side by `alpha` and solves that. Measured on
the lower triangular `[[2,0,0],[1,3,0],[0,0,4]]` against `(2, 5, 4)`, the host's answers for
`alpha = 2, 0.5, -1, 0` are

| alpha | the host answers | scaling the solution would give | solving `T x = b / alpha` gives |
| --- | --- | --- | --- |
| 1 | 1, 1.33333, 1 | — | — |
| 2 | 0.5, 0.666667, 0.5 | 2, 2.66667, 2 | 0.5, 0.666667, 0.5 |
| 0.5 | 2, 2.66667, 2 | 0.5, 0.666667, 0.5 | 2, 2.66667, 2 |
| -1 | -1, -1.33333, -1 | -1, -1.33333, -1 | -1, -1.33333, -1 |
| 0 | inf, nan, nan | 0, 0, 0 | inf, nan, nan |

and the matrix form agrees: with `B` of two right-hand sides `(2,5,4)` and `(7,9,6)` and `alpha = 2` the
host answers `0.5, 1.75, 0.666667, 0.916667, 0.5, 0.75`, which is `T^-1 (B / 2)` and not `2 T^-1 B`. The
`alpha = 0` row is the one that settles it: scaling the solution would give zeros, and the host gives an
infinity and then a `NaN`, which is what dividing by zero gives.

**The port divides.** A caller that read the header and wrote `alpha * T^-1 * b` gets `T^-1 (b / alpha)`,
which is a real difference and is named here and in each entry's `effect` in the registry rather than left
for a caller to find. The header is not the system, and where the two disagree the system is what a
caller of this library has been getting.

## The one tolerance in the family, and what it is

`sparse_operator_norm_*` with `SPARSE_NORM_TWO`, the largest singular value. The host reaches it by an
iteration and the port by an eigen-decomposition of the Gram matrix through `ssyev_`, and the two agree to
about one part in three thousand and not to the last bit:

| matrix | the exact largest singular value | the host answers |
| --- | --- | --- |
| `[[-1,2,-3],[4,0,-5]]` | 6.70179 | 6.69983 |
| the diagonal `(3, 4)` | 4 | 3.9941 |

The differential compares that one case to `5e-3` and every other element of every other case with no
tolerance at all. The port's answer is the exact one.

## Four places the host is not the port's answer, and why

Each of these is a case where the host's own answer is either not reproducible or not something a port may
reproduce. None of them is silently different: each is here, in the entry's `effect` in the registry, and
in the differential, which checks the port against the header's rule for exactly these cases.

1. **A leading dimension below what the layout needs, in `sparse_matrix_triangular_solve_dense_*`.** The
   header says `SPARSE_ILLEGAL_PARAMETER`; the host hands the parameter to `cblas_strsm`, which prints
   `LDB must be >= MAX(N,1): LDB=1 N=2 BLAS error: Parameter number 12 passed to cblas_strsm had an
   invalid value` and takes the process with it. A port must not end its caller's process, so the port
   answers the status the header names. The differential asks the host's answer in a child process and
   compares the child's fate with the port's status.
2. **A transpose the enumeration does not name.** The header says `SPARSE_ILLEGAL_PARAMETER` for
   `sparse_matrix_vector_product_dense_*`; the host hands it to `cblas_sgemv`, which prints
   `BLAS error: Parameter number 2 passed to cblas_sgemv had an invalid value` and exits with status 255.
   The level-3 forms do refuse with the status, so the two levels of the same library answer one bad
   transpose differently. The port answers the status in both.
3. **A negative stride in `sparse_vector_triangular_solve_dense_*`.** Everywhere else in this family the
   host implements the header's rule — the caller's pointer is the last element and the library walks down
   from it — which is what the port does too, and the differential compares it element for element
   (measured: an inner product with the pointer at the last element answers 390, an addition with it
   answers the three elements below the pointer, an unpack with it writes 7 at the pointer and 8 one
   stride below). The triangular solve is the exception: the host reads and writes the buffer *backwards*
   and therefore outside it. Measured: for the lower `[[2,0,0],[1,3,0],[0,0,4]]` with the right-hand side
   `(5,4,2)` at the last element of a three-element block and an increment of -1, the host writes 0.5,
   0.333333 and 1 at three elements *above* the pointer — past the end of the caller's block. The port
   answers the header's rule, which stays inside it.
4. **A few refusals and reads the host gets wrong, all measured, none of them reproduced.**

   - `sparse_matrix_trace_float` with an offset past the last column reads outside the matrix: on the 3x4
     above it answers 0 for the offsets -5 to 4 and takes the process at 5. The port answers 0, as the
     header says. The differential asks the host for -5 to 4 and checks the port against the header for
     5 to 9 and -6 to -9.
   - An outer product with an alpha of zero answers a matrix the host cannot then be read out of: the
     first row extraction answers 0 with an end of 0 and the second takes the process, because the host
     has not materialised the product. The port's matrix is empty and readable. The differential compares
     the status, the shape and the count for that case and the elements for the rest.
   - `sparse_get_matrix_property` with a negative name answers uninitialised memory — measured, -1 reads
     -520093697 on a fresh matrix. The port answers 0. The name is one the header does not declare.
   - The mixed sequence of a batch, a column, a row and another column leaves the host's column 0 at its
     first value where the port's has the last, because the host applies a column insertion lazily and the
     two sides' calls interleave over the same arrays. Each insertion kind is compared on a matrix of its
     own, and the host's own answers for the whole sequence are `[[5,7,8,1,0,0],[0,0,3,0],[6,0,0,0],[9,0,0,0]]`
     after `entries(3), entries(0), col(0,{5,6} at {0,2}), row(0,{7,8} at {1,2}), col(0,{9} at {3})`, which
     is what the port gives for the same sequence on its own matrix. The cause inside the host was not
     pinned down and is not claimed here.

## What has not been run

`tests/backports/device/sparseblas.m` calls all sixty-nine entry points on the device against the answers
recorded above: 86 checks, 0 failures when it is built and run on the host against the port's own objects.
**The run on the device has not happened.** The test is written, and it is built here for `armv7` against
the SDK this port builds with; until it is run on an emulated 6.1.3 (`xmake emulate`) or on an iPad 2
every answer on this page is a host measurement and a device-unverified one, which is the floor the
port's own contract asks for and not the bar.

The imports are not a guess: the ladder walk in the second section above puts all thirty-five of them at
4.0, so they resolve on the 4.3 band and on the 6.1.3 one, and the gate checks them against both as it
links each band. The first gate run of this tree stopped for a different reason and is recorded in the
delivery: the port's `ssyev_` call passed its scalars as `int *`, which the iOS 16.4 header's
`__CLPK_integer` refuses on a 32-bit target where that typedef is a `long int`. The host's own Accelerate
has the same header with `__CLPK_integer` as an `int`, so the host build accepted it and the device build
did not — the port's variables are that typedef now, and both builds compile.
