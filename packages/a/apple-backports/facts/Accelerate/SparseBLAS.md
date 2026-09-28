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
- **RETRACTED, and this is the correction that matters: the host does NOT answer the complex products
  and the complex solves with uninitialised memory.** That was over-general, and it came from my own
  probe using a **complex alpha**. With a real alpha the host and the port agree to the last bit:

  | case | the port | the host |
  | --- | --- | --- |
  | `y = 1 * op(A) * x + y`, `A = [[1,0,2],[0,0,0],[4,0,0]]`, `x = (1,2,4)`, `y` of ones | `10 1 1` | `10 1 1` |
  | the same transposed | `18 1 3` | `18 1 3` |
  | `alpha = 2`, not transposed | `19 45 1` | `19 45 1` |
  | `alpha = 2`, transposed | `3 13 21` | `3 13 21` |
  | `C = 1 * A * B + C`, `A = [[1,0,2],[0,3i,4]]`, `B = {1,2,9,9,3,4,9,9,5,6,9,9}` with `ldb = 3` | `26 27 70 52` | `26 27 70 52` |
  | the same with `alpha = 2` | `45 47 133 97` | `45 47 133 97` |
  | the complex triangular solve of a real `b` against `[[2,0,0],[1,3,0],[0,0,4i]]`, both transposes, `alpha` 1 and 2 | `1 1.33333 1`, `0.5 0.66667 0.5`, `0.16667 1.66667 1`, `0.08333 0.83333 0.5` | the same four |

  So **the host is the oracle for the complex products and the solves**, the earlier "uninitialised
  memory" claim does not stand, and the port's complex matrix-vector product and its complex dense
  product are CORRECT — the `i, k, re, im, from, to` printout for the transposed case reads
  `i=0 k=0 re=1 im=0 from=0 to=0`, `i=0 k=2 re=4 im=0 from=2 to=0`, `i=2 k=0 re=2 im=0 from=0 to=2`, and
  the answer is `18 1 3`. The oracle the last commit described (the port's own real half under a second
  prefix) is withdrawn: it was reporting the port wrong and is not an oracle for these families.
- **What the host accepts for the complex triangular solve, measured**: a matrix with a complex entry
  (`d00 = 2 + i`), a complex right-hand side, a complex alpha, a complex off-diagonal and the transpose
  — all six answer `SPARSE_SUCCESS`. So the `-1000` the differential saw was not the host refusing an
  argument, and that is a defect in the differential's cases, not in either library.
- **RETRACTED AGAIN, and this one is the "named defect" I reported last turn: the port's complex
  triangular solve is NOT wrong.** Measured in isolation, the port and the host agree to the last bit on
  every case, and agree with the substitution:

  | T | b | alpha | transpose | the port | the host | the substitution |
  | --- | --- | --- | --- | --- | --- | --- |
  | `[[2,0,0],[1,3,0],[0,0,4]]` | `(2, 5i, 4)` | 1 | no | `1, -0.33333 + 1.66667i, 1` | the same | the same |
  | the same | the same | 1 | yes | `1 - 0.83333i, 1.66667i, 1` | the same | the same |
  | `[[2+i,0,0],[1,3,0],[0,0,4+i]]` | `(2, 5, 4)` | 1 | no | `0.8 - 0.4i, 1.4 + 0.13333i, 0.94118 - 0.23529i` | the same | `2/(2+i) = 0.8 - 0.4i`, and `4/(4+i) = 16/17 - 4i/17` |

  The `0.8 - 0.4i` I reported as the port being wrong is the **correct** answer for
  `[[2+i,0,0],[1,3,0],[0,0,4+i]]`, and the `1` I set against it was the arithmetic of a *different*,
  real, matrix. I compared a complex matrix's answer with a real matrix's arithmetic.

- **Where that leaves the complex half, and why I stopped chasing it through the differential.** The two
  families I was asked to close — the matrix-vector product and the triangular solves — are measured
  **correct against the host**, in isolation, on both transposes and several alphas. The twenty-odd
  remaining failures all come from `host/differential.m`, which is my own scaffolding and which my
  scripted edits damaged repeatedly over three turns: the declaration block, the `void *` call sites and
  several conditions were mangled and repaired by pattern, and I cannot now vouch for a case that file
  reports. The operator-two norm, the one batch extraction and the one outer product are the only
  findings that still stand, and even those are unconfirmed outside that file.
- So the next step is not a fix in the port: it is to **rewrite the complex differential from scratch**,
  as a new file rather than another repair, and re-measure against it. Nothing about the port's
  behaviour should be concluded from the current one.
  - One thing already found and fixed by the oracle work: `cblas_caxpy` and its sisters address their
    vectors in units of a complex value, and every offset in this family is in complex units, so the
    pointers have to be complex-typed. Casting to `float *` and adding the offset counts floats, which
    is what the first version did.

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
the same inputs and compares every status, every count and every element. Every one of the sixty-nine rows is
called, and `CblasTrans` reaches all four level-3 entry points: **358 checks, 0 failures**. The
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

## What the review found, and what is now measured

The review of 2026-09-28 (`coordination/reviews/2026-09-28-api-sparseblas.md`) returned CHANGES with three
blockers and three minors. All six are fixed; this is what each one was and what the fix measures.

1. **A transposed level-3 product read through a NULL row pointer** — `CharonSparseProductDense` and
   `CharonSparseProductSparse` bound the row of the operand they walk to `NULL` when the operand is
   transposed and then read `line->value` from it, so `CblasTrans` took the process down on all four
   level-3 entry points. The entry the walk is at is `A[r, c]` in both cases and is now read through
   `CharonSparseElementAt`, the same lookup the trace, the norms and the triangular solve use. The
   differential now asks `CblasTrans` of all four: for a 3x2 `A` with a 3x2 `B` in both layouts
   (`a sparse product, CblasTrans, both layouts`), and for the dense form with a 3x2 `A` and a 3xN `B` in
   both transposes and both layouts (`a dense product, both transposes`), and every one agrees with the
   host element for element.
2. **`sparse_permute_cols_double` passed `sizeof(float)`** — the double twin of the float form was
   copied with the float element width, and that helper branches on it to read and write every value, so
   a double's values went through four bytes at a time and column 0 came back as denormal garbage
   (the review's probe, `1.1 2.2 3.3 / 4.4 5.5 6.6` with the permutation `{2,0,1}`). The argument is
   `sizeof(double)`, and the differential now compares the double row and column permutations on those
   same values over four column permutations and three row permutations.
3. **Sixteen rows were called by neither harness** — the review counted 51 of 69 in the host differential
   and 47 in the device test. All sixteen are now asked, as the double twins of cases the float half
   already compares: the double row and column insertions, the double block create/insert/extract at two
   stride pairs and one absent block, the double column extraction over every column and start, the
   double inner product of two sparse vectors, the double nonzero count, pack and unpack, the double
   matrix-vector product in both transposes, the double triangular solve of a vector and of a matrix over
   both layouts and both transposes and three leading dimensions, the double outer product and its refusal,
   and the double row and column permutations. The differential is now **358 checks, 0 failures**, and
   every one of the sixty-nine rows is called.
4. **A block commented as the transposed case passed `CblasNoTrans`** — the transposes went in, and the
   `A` is a 3x2 so the transpose is the header's own legal shape.
5. **A comment named a function not in the tree** — closed: `CharonComplexElementAt` belonged to the
   complex half, and the comment now says what the shared body is for without naming a reader. Re-checked
   in the rebased tree: `grep -rn CharonComplex packages/ tests/` returns the facts file's own record of
   the fix and nothing in any code comment.
6. **A computed-and-discarded search** — closed: the transposed triangular solve searched for an entry
   that `CharonSparseElementAt` searches for again. Re-checked: no `(void)at` remains anywhere in the
   port's Accelerate sources, and the only `CharonSparseSearch` in the transposed block is the one whose
   result is tested.

And finding C, "sixteen of sixty-nine called by neither test", recounted against the delivered files by
reading the registry and counting the call sites in each: **the host differential calls 69 of 69, the
device test calls 47, and the two together call 69 — none is called by neither.** It was 16 of 69 before;
all sixteen are now asked, as the double twins of cases the float half already compares.

One case is now a recorded divergence rather than an agreement: a sparse-sparse product whose inner
dimensions do not conform is `SPARSE_ILLEGAL_PARAMETER` at the port and a product of two matrices that do
not conform at the host. The header calls that shape undefined, and the port refuses rather than writing
one. It is in the differential as its own case, with both statuses in the output.

## The operator-two norm, settled with an oracle that is not a BLAS

The one number in this family where the port and the host were said to differ is the largest singular
value, and it is now settled without a LAPACK. For an `m x n` A with `m <= n`, `AᴴA` is `m x m` Hermitian
and its eigenvalues are the squares of the singular values; for `m = 2` they are in closed form,

```
lambda = (t + d + sqrt((t - d)^2 + 4 |z|^2)) / 2,   z = (AᴴA)[0][1],  t = (AᴴA)[0][0],  d = (AᴴA)[1][1]
```

evaluated in `long double complex`, and for larger `m` a power iteration on `AᴴA` in the same type,
started from a fixed vector so the answer is deterministic. Two identities hold it to the truth and both
are checked on every call: the squared singular values sum to the sum of the squared moduli (the Frobenius
identity), and `sigma_max` is at most their root.

| matrix | the oracle's `sigma_max` | `sqrt(sum \|a\|^2)` | the host's operator-two norm | the gap |
| --- | --- | --- | --- | --- |
| `[[1, 0, 2], [0, 3 + i, 0]]` | 4.13171487543 | 4.472135955 | 4.131535372 | 1.8e-5 relative |
| `[[-1, 2 + i, -3i], [4, 0, -5 + 2i]]` | 7.31109285942 | 7.745966692 | 7.311090975 | 2.6e-7 relative |

**So the host is right and the port is right, and the rule is the largest singular value.** Two things
follow, and the first is a correction of an earlier page of this file:

- The `6.5724` this file earlier gave for `[[-1, 2 + i, -3i], [4, 0, -5 + 2i]]` was a bad hand
  computation. The true value is **7.311092859** and the host answers 7.311090975, so the "the host
  differs from the largest singular value" finding is **withdrawn**: the host is within 2.6e-7 of it,
  which is its own iterative precision.
- The host reaches the number by an iteration and the port by an eigen-decomposition of `AᴴA` through
  the release's own `cblas_cherk` and `ssyev_`, so the two differ by about **1.8e-5** relative at worst.
  The differential's `5e-3` for that one number is therefore about **270x** the host's own error. It
  stays, and it is now a measured quantity rather than a guess.

Apple's CLAPACK `zgesvd_` is **not** usable as this oracle on this host: driven through `clapack.h`'s
pointer-scalar ABI it answers `2.62521e+299, 2, 3.27186e-314` for a matrix whose squared singular values
must sum to 15, so the closed form above is what the family is held against, and it needs no LAPACK at all.

## The `Sparse*` solve family: 199 rows, and what the factor set actually is

`vecLib/Sparse/Solve.h` is 8 339 lines and the family's 158 entry points plus 41 constants are it. Read
from the header of iOS 26.2 before writing anything, the surface is:

- the **transparent types** — `SparseMatrix_{Double,Float,Complex_Double,Complex_Float}` (CSC), the matching
  `DenseMatrix_*`, `SparsePreconditioner_*`, `SparseOpaqueSymbolicFactorization_*` and
  `SparseOpaqueFactorization_*` — each built through `_SparseConvertFromCoordinate(m, n, nBlock, blockSize,
  attributes, row, col, val, storage, workspace)`, so the caller supplies a storage and a workspace and the
  library lays the CSC out into them;
- the **direct methods**, one interface and eight factorisations, with the pivoting named in the enum:
  `SparseFactorizationCholesky` for SPD, `SparseFactorizationLDLT` (the default, which the header says is
  currently TPP), `LDLTUnpivoted`, `LDLTSBK` (Supernode Bunch-Kaufman with static pivoting),
  `LDLTTPP` (threshold partial pivoting), `QR` (m >= n), `CholeskyAtA` (QR without storing Q) and `LU`
  (currently TPP), with `LUUnpivoted`, `LUSPP` and `LUTPP`; and each carries its own `SparseStatus` —
  `SparseStatusOK`, `SparseFactorizationFailed`, `SparseMatrixIsSingular`, `SparseInternalError`,
  `SparseParameterError`, `SparseStatusReleased`;
- the **iterative methods** `CG`, `GMRES` and `LSMR`, each with its own options struct and its own
  preconditioner interface, and `SparseIterate` for restarting one with a new right-hand side;
- and the **factor algebra**: `SparseSolve`, `SparseRefactor`, `SparseMultiply`, `SparseMultiplyAdd`,
  `SparseGetTranspose`/`SparseGetConjugateTranspose`, `SparseGetStateSize_*`, `SparseGetInertia`,
  `SparseUpdateFactor`, `SparseCreateSubfactor` and the eleven `SparseSubfactor_*` selections,
  `SparseScaling*`, `SparseOrder*`, `SparseRetain`/`SparseCleanup`/`SparseOpaqueDestroy`, and
  `SparseConvertFromCoordinate`/`SparseConvertFromOpaque`.

**The factor set is not small, and that decides the reuse question.** Four factorisation families with
eleven named pivoting variants between them, the numerically delicate part being Bunch-Kaufman and
threshold partial pivoting, is a real sparse-factorisation stack, not something to re-derive from a header.

**The three candidates, and what the licences actually permit** — read from the upstream licences, not from
a description of them:

| upstream | licence | what it gives | usable how |
| --- | --- | --- | --- |
| Eigen `SimplicialLLT` / `SimplicialLDLT` / `SparseQR` / `SparseLU` | **MPL-2.0**, file-level copyleft | all four families, with `BunchKaufman` and `AMDOrdering` / `ColamdOrdering` already written | **vendorable as whole unmodified files**, and read as the reference for the algorithm and the pivoting. But the port ships one C/Objective-C `.dylib` per framework; adding a vendored C++ library to `packages/a/apple-backports/Accelerate/` is a packaging change to every band that shares the folder, not a row, and the vendored files would need their own package, their own licence file and their own gate entries |
| SuiteSparse **AMD and COLAMD** | **BSD-3** | the two orderings every one of the above calls underneath | **the right thing to reuse**: small, self-contained, permissively licensed, and taking them removes the only ordering work that is pure bookkeeping |
| SuiteSparse **CHOLMOD**, **UMFPACK**, **SPQR** | **LGPL / GPL** | LDLᵀ, QR and LU to stand on | **read only, never vendored.** The licence is the constraint and it is not one to work around |

**So the shape the rules point at is: a native implementation over the release's own BLAS and LAPACK, with
AMD and COLAMD vendored from SuiteSparse for the orderings, and Eigen read as the reference for the
factorisations and their pivoting.** Nothing copyleft enters the shipped library, the one component that is
pure bookkeeping is reused rather than rewritten, and the part that is numerically delicate is written here
against the release's LAPACK, which every band already links.

### The host has none of this family, and that is measured

The brief asks for this family to be held against the host's own Accelerate the way the `sparse_*` BLAS
family is. **It cannot be**, and the reason is three independent measurements:

1. **C cannot name it.** Every entry point in `Solve.h` is declared
   `__attribute__((overloadable))` (`Solve.h:267`), which is a C++-only attribute. A C probe fails to
   compile with "`call to undeclared function 'SparseConvertFromCoordinate_Double'`", and the compiler's own
   note points at `_SparseConvertFromCoordinate_Double` — the old, pre-10.13 spelling.
2. **C++ cannot name it either.** The macOS SDK's `SolveImplementationTyped.h` is the **old-style** header:
   it exposes only the `SPARSE_OLDSTYLE(sparse_matrix)` path, and `SparseOpaqueSymbolicFactorization_Double`,
   `SparseFactorSymbolic_Double`, `SparseFactorNumeric_Double` and `SparseGetStatusOfFactor_Double` are all
   undeclared there. The 11.0-era transparent types are in the 26.2 SDK's copy of that header and not in
   the host's.
3. **`dlsym` finds none of them.** Asked on the running process for eight of the family's names —
   `SparseConvertFromCoordinate_Double`, `SparseFactorSymbolic_Double`, `SparseFactorNumeric_Double`,
   `SparseSolve_Double`, `SparseGetStatusOfFactor_Double`, `SparseCG_Double`, `SparseCleanup_Double`,
   `SparseGetConjugateTranspose_Double` — every one answers **absent**.

So there is **no host oracle for any of the 158 entry points**, and a "hold it against the host" instruction
is unmeetable for them as written. That is a different situation from the `sparse_*` BLAS family beside
them, where every name is a C symbol the host exports and where all 69 rows are compared element for
element against it.

**The oracles that do exist**, and the weaker guarantee they give:

- **the arithmetic itself** — a Cholesky factor must reproduce `A = P L L' P'` to the tolerance that
  identity demands, an LDLᵀ factor `A = P S L D L' S' P'`, a QR `A = Q R P`, an LU `A = P L U Q`; and a
  solve must reproduce `A x = b`. Those are the definitions, and a factorisation that does not satisfy them
  is wrong whatever it agrees with.
- **the release's own LAPACK** — `dpotrf_`, `dsytrf_`, `dgeqrf_`, `dgetrf_` and the triangular solves are
  independent implementations of each of these, and the ladder puts every one of them at **4.0**, so they
  resolve on both ends of this port's ladder. That is a real cross-check, and a stronger one than an
  invariant alone, but it checks the arithmetic and not the API: the `SparseStatus` answers, the
  `SparseMatrixIsSingular` and `SparseFactorizationFailed` cases, the scaling and ordering behaviour, and
  the subfactor algebra have no second implementation to be compared with at all.
- **AMD and COLAMD**, for the orderings, which are the one part where two implementations agreeing is a
  genuine check rather than a tautology.

**So this family's differential has to be an invariant differential with the release's LAPACK as the
cross-check, not a host-comparison differential** — which is a weaker guarantee than the other 69 rows
carry, and the coordinator should rule on that before 158 rows are built against it. The plan is otherwise
unchanged and the measurements above are why each step of it is in the order it is.

### AMD and COLAMD: fetched, verified, and BSD-3 at the source

`git clone https://github.com/suitesparse/SuiteSparse` **fails on this machine** — "Repository not found",
for the `suitesparse` path, while a public GitLab clone works, so the proxy is selective and that path is not
reachable. **The xmake registry's own recipe is**, and it is the better answer because the machine already
trusts its pin:

```
$HOME/.xmake/repositories/xmake-repo/packages/s/suitesparse/xmake.lua
    add_urls("https://github.com/DrTimothyAldenDavis/SuiteSparse/archive/refs/tags/$(version).tar.gz", …)
    add_versions("v7.12.2", "679412daa5f69af96d6976595c1ac64f252287a56e98cc4a8155d09cc7fd69e8")
```

Fetched and hashed:

```
SuiteSparse v7.12.2, 95 337 908 bytes
  sha256 679412daa5f69af96d6976595c1ac64f252287a56e98cc4a8155d09cc7fd69e8
  which is exactly the pin the machine's own xmake registry carries for v7.12.2
```

And the licences are read out of the two files, not from a description of them:

```
AMD/Source/amd_1.c:5     AMD, Copyright (c) 1996-2022, Timothy A. Davis, Patrick R. Amestoy, and …
AMD/Source/amd_1.c:7     SPDX-License-Identifier: BSD-3-clause
COLAMD/Source/colamd.c:5  COLAMD, Copyright (c) 1998-2022, Timothy A. Davis and Stefan Larimore, …
COLAMD/Source/colamd.c:7  SPDX-License-Identifier: BSD-3-clause
```

So the reuse the plan names is executable and pinned twice over — a version and a hash the machine already
carries, and an SPDX identifier read from each source. **No source is copied into the repository**: the
package downloads the same tarball the machine's own registry pins and builds from it, so the bytes are the
tarball's and the tree carries a recipe and a hash.

### The package, written and wired, and exactly where it stops

`packages/s/suitesparse-ordering/xmake.lua`, shaped on `packages/b/box2d/xmake.lua`: the same
`add_urls` and `add_versions` pair, the same `add_links`, the same `recipe` config so a changed flag is a
different library, `set_license("BSD-3-Clause")`, `package.strict_compatibility`, and an `on_install` that
builds with the apple-ios toolchain at `-Os -fvisibility=hidden` into `libSuiteSparseOrdering.a` with
`libtool -static`. The source list is **spelled out, not globbed**, so a directory added to the tarball
cannot join the build by accident:

- `AMD/Source`: `amd_1.c amd_2.c amd_aat.c amd_control.c amd_defaults.c amd_dump.c amd_info.c
  amd_post_tree.c amd_postorder.c amd_preprocess.c amd_valid.c amd_version.c` — the `amd_l_*` int64 variants
  are left out, a 32-bit armv7 build does not use them;
- `COLAMD/Source`: `colamd.c colamd_version.c`;
- and `SuiteSparse_config/SuiteSparse_config.h` for the include path and the install.

**CHOLMOD, UMFPACK, CXSparse, SuiteSparseQR, KLU, Mongoose, ParU, RBio, SPQR, SPEX, GraphBLAS, CAMD,
CCOLAMD, CSparse and BTF are all in the same tarball and none of them is named**, because the first two are
LGPL and GPL and the rest are not what this package is for. The four licence and README files installed are
`AMD/Doc/License.txt` and `COLAMD/Doc/License.txt` plus the two READMEs, under both their own names and
the package's.

It is wired the way the ruling says: `backports.lua`'s Accelerate row carries
`archives = {"suitesparse-ordering"}`, and `packages/a/apple-backports/xmake.lua` declares
`add_deps("charon@suitesparse-ordering v7.12.2", {alias = "suitesparse-ordering"})`, without which the gate
refuses with `apple-backports links the archive suitesparse-ordering and its recipe declares no dependency
with that alias` — which is what it did, and the dep is the fix.

**Where it stops, and the bare assertion answered.** The download succeeds — `download … v7.12.2.tar.gz
.. ok`, the same URL and the same hash the machine's registry carries — and the **install step fails** with
a bare `assertion failed!` and no message. The suspicion that it is `toolchain:tool("cc")` returning nil
for apple-ios is **disproved by a print added ahead of it**, which is in the recipe and runs before
anything else is assumed:

```
suitesparse-ordering: toolchain table: 0x774f137cc0,
  cc  = $HOME/.xmake/packages/l/llvm/23.1.1/<the store's hash>/bin/clang
  cxx = $HOME/.xmake/packages/l/llvm/23.1.1/<the store's hash>/bin/clang++
```

Both resolve, so the failure is after that point: in one of the five `os.isdir` checks that follow (whose
messages name the directory) or in an xmake internal whose own assert carries no text. The next narrowing
step is to print each of those five; the log to read is



```
$HOME/.xmake/cache/packages/2609/s/suitesparse-ordering/v7.12.2/installdir.failed/logs/install.txt
assertion failed!
```

Three things were fixed on the way there and each is recorded because each was a real error, not a guess:
`$(version)` is a parse-time substitution and cannot appear inside `on_install` (the recipe now asks
`package:version()`); the version is `v7.12.2` **with** the `v`, because the registry's URL template puts
`$(version)` where the tag has one and a bare `7.12.2` is a 404; and xmake unpacks the tarball with its
top level already stripped, so the sources sit directly under `os.curdir()` and the recipe says which five
directories it expects to find there, so a layout change is a message and not an assertion.

**So the ruling's proof is not yet produced and I am not claiming it**: the archive does not build, the
`libAccelerateBackports.dylib` has not been relinked with it, and there is no `nm -gU` on a dylib carrying
it. The next step is the bare assertion in that install log, and the two lines of `on_install` that call
`package:toolchains()` and `os.vrunv` are where a message-less failure would come from — most likely the
toolchain object, since box2d's recipe takes `[1]` off the same call and works, so the difference is that
this one builds C with `toolchain:tool("cc")` where box2d builds C++ with `toolchain:tool("cxx")`.

One more thing to settle before the archive can reach a C family at all, and it is a change to a module
every band shares, so I am flagging it rather than making it: `backports.lua:546` consumes a library's
`archives` **only when the library has Objective-C++ objects** (`for _, name in ipairs(cxx and
library.archives or {})`), and `compile()` adds the archives' `-I` only for `.mm`. The `Sparse*` solve family
is C, so with the module as it stands the archive is listed, resolved and built but never linked and its
headers never on the include path. That is one line in a shared module and it is the coordinator's call.

### The device as a second oracle: asked, not yet answered

The plan records a fourth oracle — an emulated 26.x or 17.x firmware, where these symbols are in the
Accelerate cache. I have asked the worker that owns the emulated device which images exist on this machine
and what a single run would cost, and **the answer has not arrived**: the response was a status line about
that worker's own task, not an answer. So nothing is planned on the device. The invariant differential
cross-checked against the release's LAPACK is what the family is being built against, and the device oracle
is a possibility to be confirmed rather than a dependency.

**What is not done.** No code, no vendored file, no device measurement. The next steps, in order: measure the
host's `SparseFactor`/`SparseSolve` on a small SPD matrix, a symmetric indefinite one under each of the four
LDLT pivoting options, a singular matrix and a matrix that is not positive definite fed to Cholesky, and a
general square one under LU — recording the `SparseStatus` and the solution of each, because the
`SparseMatrixIsSingular` and `SparseFactorizationFailed` answers are what the whole family's error
contract is built on and they are host-specific facts, not derivable from the header. Then vendor AMD and
COLAMD and pin their commits. Then write the table-driven differential against those measurements before
the first entry point.

## The gates, and what they say

Both ends of the ladder, on the tree this page describes, at base `68befaca`:

```
build-gate.lua 6.1.3
  imports: every non-weak import of the armv7 slices of 28 binaries resolves against 158520 exports
  …/libAccelerateBackports.dylib
  0 error: lines, no "registry does not describe what the backports carry:"

build-gate.lua 4.3
  imports: every non-weak import of the armv7 slices of 28 binaries resolves against 85386 exports; 4 weak
  imports it does not export, each named in a warning above
  …/libAccelerateBackports.dylib
  0 error: lines, no "registry does not describe what the backports carry:"
```

The four weak imports 4.3 does not export are `_OBJC_CLASS_$_UIActivityViewController` in
`libSafariServicesBackports.dylib` and `_OBJC_CLASS_$_NSByteCountFormatter`,
`_OBJC_CLASS_$_NSMutableOrderedSet`, `_OBJC_CLASS_$_NSTextContainer` in `libUIKitBackports.dylib` — none of
them an Accelerate name, and none of the 35 `cblas_*`/LAPACK names this port imports, which the ladder
puts at 4.0 in the table above. That is the whole of the 4.3 gate's finding.

```
tools/release-split.lua <gate-3>/build/objects/Accelerate
  release-split: clean, every object file's symbols first-appear in one release (6 files, 87 symbols, 47
  releases checked)
  SparseBLAS9.o        67 symbols, all 9.0
  SparseProduct10.o     2 symbols, both 10.0.1
```

Two notes the tool prints and the reading depends on: no release is held between 12.0 and 16.0 and none
between 16.0 and 18.0, so a 16.0 or an 18.0 in that output means "after the previous rung and by this
one", not a measured first release. And a category has no `nm`-visible symbols, so a clean run says
nothing about any category file — there is none here.

## The complex half: where it lives and what is and is not held

`SparseComplex18.m` and `CharonSparseComplex.h` sit in `tests/backports/host/sparsecomplex/`, beside the
differential that holds them, and `run.sh` resolves the root and both source paths from its own location.
They are **beside the test and not in `packages/a/apple-backports/Accelerate/`** for a reason the gate
enforces rather than a preference: that folder is the library, a file in it is built, and a built symbol
with no registry entry is a red `built, but no entry in registry/`. The complex half has no registry rows
because it is not carried yet.

**What the 41 checks hold, name by name.** They cover eight of the twenty-nine entry-point pairs, all
through the float complex forms: the matrix-vector product, the triangular solve of a vector, the
triangular solve of a matrix, the dense product, the outer product, the trace, the elementwise norm and
the operator norm — together with `sparse_matrix_create_float_complex`,
`sparse_insert_entry_float_complex`, `sparse_set_matrix_property`, `sparse_get_matrix_nonzero_count`,
`sparse_extract_sparse_row_float_complex` and `sparse_matrix_destroy`, which the eight go through.

**What they do not hold: twenty-one pairs and the other twenty-nine singles** — the block and
variable-block creations, `sparse_insert_entries_*`, `sparse_insert_row_*`, `sparse_insert_col_*`,
`sparse_insert_block_*`, `sparse_extract_sparse_column_*`, `sparse_extract_block_*`,
`sparse_inner_product_dense_*`, `sparse_inner_product_sparse_*`,
`sparse_vector_add_with_scale_dense_*`, `sparse_vector_norm_*`, `sparse_get_vector_nonzero_count_*`,
`sparse_pack_vector_*`, `sparse_unpack_vector_*`, `sparse_permute_rows_*`, `sparse_permute_cols_*`,
`sparse_matrix_product_sparse_*`, and every double twin. None of them is called by anything yet.

So the sequence the next session takes is: widen this table until all fifty-eight are compared, and only
then add the registry rows and move the two files beside `SparseBLAS9.m`. The gate will tell it when the
move is legal, because until then the moved file's fifty-eight symbols are built with no entry.

## The complex half's differential, and the mutation proof

`tests/backports/host/sparsecomplex/differential.m` and its `run.sh` are **in the tree**, not in
`.agent-work`: a rewrite script emptied the copy that lived there, and a test that a script can empty
does not belong outside the tree. The cases are a table — the operation, the shape, which of the two
entry blocks to build, the alpha, the transpose, the order, the leading dimensions, the strides, the
norm, the expected status and a note — and one loop builds the matrix on both sides from the row, calls
through the operation's own signature and compares. The port is one dylib, `dlopen`ed
`RTLD_LOCAL | RTLD_FIRST` and reached by `dlsym`, so nothing of the port's can interpose the host's and
there is no `-D` renaming in the file. A refused case runs the host in a child, because the host does not
always refuse what the port refuses (measured: an unnamed transpose goes into `cblas_cgemv`, which ends the
process). **41 checks, 0 failures.**

Two things the table got wrong the first time, both in the table and not in the port: the two row-major
dense products carried an output stride of 2 against three columns, which the port **and** the host
refuse; and the alpha-zero outer product's elements are now compared by the nonzero count, because the
host has not materialised that product and an elementwise read of it takes its process down.

`compareComplex` builds its detail in a buffer of its own and carries the size with it. It took a
`char *` and wrote with `sizeof` on it, which is **the size of the pointer and not of the buffer**, so
every mismatch was cut to seven characters — which is why every failure used to end in `status `.

**The differential can fail.** One line of `SparseComplex18.m` mutated, `(float complex *)y + to` to
`+ (to - 1)` in `CharonComplexVectorProduct`, and:

```
MUTATED:  41 checks, 6 failures
FAIL a matrix-vector product: alpha 1: element 0: port 6+0i, host 7+0i; status 0 against 0, wanted 0
FAIL a matrix-vector product: alpha 2: element 0: port 12+0i, host 14+0i; status 0 against 0, wanted 0
RESTORED: 41 checks, 0 failures      (the source byte-identical to the committed one afterwards)
```

The differing element is named in full, which is the `sizeof` fix demonstrated rather than asserted.

## The complex half's new differential

`…/.agent-work/wip/sparsecomplex/host/differential-complex.m`, written from scratch, and the old one is
gone. What is different about it:

- **The cases are a table.** One `Case` row per case — the operation, the shape, the alpha, the
  transpose, the order, the leading dimensions, the strides, the norm, the expected status and a note —
  and **one loop** over that table. The only place a case is read is the switch, which is the operation's
  own signature; there is no per-case code.
- **The two sides are two libraries.** The port is built as `libComplexPort.dylib` (the complex family
  plus the real half that owns the `void *` entry points a complex matrix answers) and `dlopen`ed
  `RTLD_LOCAL | RTLD_FIRST`, reached by `dlsym` on that handle. So nothing of the port's can interpose
  the host's, and the host's Accelerate is the one the process already has. There is no `-D` renaming
  anywhere in it.
- **A refused case runs the host in a child**, because the host does not always refuse what the port
  refuses (measured: an unnamed transpose goes into `cblas_cgemv`, which ends the process). The same
  switch serves both sides through one `side` variable, so there is still one loop and one switch.
- **Where the host cannot be read back** — an outer product with an alpha of zero, which the host has not
  materialised and whose second row extraction takes the process — the case compares the status and
  the nonzero count instead of the elements, and says so in its output.

State: **20 cases pass, 2 fail**, and the two open items are named here so the next session starts at
them rather than looking for them.

1. **`a dense product [order 101, alpha 1]` and `[order 101, alpha 2]`** — the row-major complex dense
   product. The column-major ones pass, and every gemv, every triangular solve, every trace and every
   norm passes. **The `ldb` hypothesis is not confirmed and the port is not fixed.** The two lines it
   names are `sparse_dimension bStep = order == CblasRowMajor ? 1 : ldb;` and
   `cblas_ccopy((int)n, (const float complex *)B + from, (int)bStep, ...)`, and by inspection they are
   right for both layouts: for a row-major B the step along a row of B is 1 and the offset is
   `c * ldb`, and for a column-major one they are `ldb` and `c`. The detail string the case prints is
   truncated to `status `, so which element differs is **not** yet known, and that is what has to come
   first: the buffer is 2048 bytes and the `used` offset into it is coming back from a `snprintf` that
   has been handed a stale length.
2. **`an outer product [two nonzeros of y]` hangs the run on the host side.** The case is reached — the
   line before the hang is `# case: an outer product [two nonzeros of y]` — and the process does not come
   back, so it is inside the host's `sparse_outer_product_dense_float_complex`, its
   `sparse_get_matrix_nonzero_count`, or its `sparse_extract_sparse_row_float_complex` on the matrix it
   just built. The alpha-zero case is already handled by comparing the count instead of the elements
   (measured: the host has not materialised that one), so this is the case where it HAS materialised it
   and the read still does not return. Until that is settled, the outer product's elements are not
   compared at all.

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
