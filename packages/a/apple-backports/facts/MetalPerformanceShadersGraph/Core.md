# The graph framework on this port: the builder side and the arithmetic family

`MPSGraphObject`, `MPSGraphType`, `MPSGraphShapedType`, `MPSGraphDevice`, `MPSGraphTensor`,
`MPSGraphOperation`, `MPSGraphTensorData`, `MPSGraph`, `MPSGraphExecutable`,
`MPSGraphExecutionDescriptor` and `MPSGraphExecutableExecutionDescriptor`, and the arithmetic family of
`MPSGraph`'s factory methods.

Source: the headers of `MetalPerformanceShadersGraph` in the SDK of iOS 16.4, which is the SDK this
package compiles against, for every signature; the 26.2 headers under
`charon/.agent-work/sdk-26.2/` for what 16.4 does not declare. The behaviour is measured against the
system's own MPSGraph by `tests/backports/host/mpsgraph/run.sh`.

## The model, and why it is a walk rather than a compiler

A graph is a description of work, and a tensor is a description of a result. Running a graph therefore
means walking the operations **in the order they were added** and asking each to fill its outputs from
its inputs and from the feeds: an operation can only read what an earlier one wrote, and the order they
were added is the order that guarantees it. A tensor's value is found by looking it up — a placeholder's
comes from the feeds, any other one's from the operation that produced it.

`MPSGraphExecutable` is then the graph itself. The release compiles a graph into device code and holds
the results on the device; this port holds them in the host memory behind an `MTLBuffer`, so there is
nothing to compile ahead of time and the executable is the graph plus the targets the compile named.
That is not a shortcut around the graph, it is the same graph with the storage the device already has.

## Where the arithmetic happens, and in what precision

Over the host memory behind an `MTLBuffer`, on the CPU, exactly as the matrix kernels in
`../MetalPerformanceShaders` do (`facts/MetalPerformanceShaders/Matrix.md`). The data type of the
operands decides the arithmetic, as it does there, through the same `CharonMPSStore` and `CharonMPSLoad`:
`CharonMPSGraph.h` **includes** `CharonMPS.h` rather than restating it, so an `MPSDataType` means one
thing in both families rather than two.

A result tensor's storage is a buffer of its own, made when the operation runs, so a run never writes
into a buffer the caller fed it.

## Four names the build's SDK does not declare

The iPhoneOS 16.4 SDK predates four names of the 26.2 surface:

* **`MPSGraphObject`** arrived in iOS 17, and every class of that surface descends from it there,
  while 16.4 has them descending from `NSObject`. It is declared in `CharonMPSGraph.h` and implemented
  here, so a graph's objects have the root the 26.2 headers give them.
* `MPSGraphFFTDescriptor`, `MPSGraphImToColOpDescriptor` and
  `MPSGraphExecutableSerializationDescriptor` are in the 26.2 surface and not in the 16.4 headers.

The declarations are guarded on a host SDK that already has them — where redeclaring would be a
duplicate, and where the host's own classes are what a comparison must be against.

**Four registered names that no header the build compiles against declares** is a rule R4 item: the
lift's sets have to be re-measured in the same push as these land.

## The measuring, and where it stands

`tests/backports/host/mpsgraph/` compiles the same cases twice — once against the system's own
MPSGraph, once against these classes with the MPSGraph names mapped to `Charon` names and their
selectors prefixed — and compares the bytes of a buffer the case owns.

**Both execution routes work on this host**, measured directly:

* compiling with a shaped-type feed and running through
  `-[MPSGraphExecutable runWithMTLCommandQueue:inputsArray:resultsArray:executionDescriptor:]` over a
  result buffer the caller owns answers `[11 22 33 44]` for two 2x2 placeholders and one addition. This
  is the route the differential uses, because it is the only one where the answer lands somewhere the
  case can read: `MPSGraphTensorData` has no accessor for its bytes in either the 16.4 or the 26.2 SDK.
* `-[MPSGraph runWithFeeds:targetTensors:targetOperations:]` answers too, and is one call.

**What the differential found, in order.** All of these were bugs, and the first two were mine in the
harness rather than in the library:

* **A `memmove` on a null destination.** The interpreter made a result's storage from an empty `NSData`,
  which is a zero-length buffer whose `contents` is null. A result now takes a buffer of the shape's
  own size, made and zeroed when the tensor data is made.
* **The inputs paired with the feed tensors in the wrong order.** `-[MPSGraphExecutable
  runWithMTLCommandQueue:...]` took the feed tensors from the dictionary's key order, which is
  arbitrary, so the second operand reached the first tensor and every non-commutative operation read
  its arguments backwards: subtraction answered `9, 18, 27…` where the release answers `-9, -18,
  -27…`. The pairings are now in the graph's placeholder order, which is the order the caller passed
  the inputs in.
* **The harness overwrote its own inputs.** It remembered each *feed's* buffer as well as the result's,
  and read every remembered buffer back into the array it came from, so after the first case each input
  array held the previous case's output and both sides agreed on the wrong numbers. Only the result
  buffer is read back now.
* **A square root of a negative, three times.** I read the chain case — where the product is positive even
  where the sum is not, so no negative ever reaches the root — as the release's root answering a
  magnitude, and changed it to `fabs`. Measured over a feed of `(1, 2, 3, 4, -1, -2, -3, -4)`, the
  release answers `1, 1.41421, 1.73205, 2` and then four NaNs. It is a NaN, it is one again, and
  `MPSGraphOperationKindSqrt` now takes `sqrt(a)`: over the sixteen classes below the whole row is
  byte-identical to the release's, element for element.
* **A branch that decided a division, a reciprocal, a square root and a logarithm by itself.** Each of the
  four had a case for the values the arithmetic is undefined at — `b == 0.0`, `a == 0.0`, `a < 0.0`,
  `a <= 0.0` — and each of the first two chose its infinity from the sign of the dividend alone, so it had
  one answer where the arithmetic has two: `-1 / -0.0` is `+inf` and the division branch had only `-inf`
  for it, and a reciprocal of `-0.0` is `-inf` where the reciprocal branch had only `+inf`. The measured
  columns `reciprocal` and `divide` carry both zeroes, `ff800000` and `7f800000`, which is what the case
  file feeds now. IEEE division answers every one of them, so the four cases are the arithmetic itself.
* **A denormal, and a NaN of its own.** `CharonMPSGraphAsZero` and `CharonMPSGraphOwnNaN` are what a result
  leaves the release's arithmetic as, and they are in `CharonMPSGraphApply` rather than in the store,
  because `CharonMPSStore` is shared with the matrix and image families and because two kinds keep both: the
  measured table below has `abs` and `identity` returning `0x00000001` and `0x7f800001` unchanged.

**Where it stands, measured on macOS 27.0 build 26A428 (M4 Pro, Metal 4):
`tests/backports/host/mpsgraph/run.sh` ends `port: same as the system, case for case and bit for bit` and
`checks=15 failures=0` over `compared: 15 cases`.** Every case is byte-identical to the release's, and the
case file feeds all sixteen classes of the table below to each of them rather than the eight values that
first showed a difference. The planted build beside it is the control: `red control: the planted build
differs from the release in 13 of 15 cases`, which is every line of the run that is a case - the other two
are the graph device's type and a shaped type's data type, neither of which is a stored element.

What the release answers for each class, float32, one row per input and one column per unary operation.
Every cell is the four bytes it wrote:

| input | bits | sqrt | rsqrt | square | reciprocal | log | abs | sign |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| +1 | `3f800000` | `3f800000` | `3f800000` | `3f800000` | `3f800000` | `00000000` | `3f800000` | `3f800000` |
| -1 | `bf800000` | `7fc00000` | `7fc00000` | `3f800000` | `bf800000` | `7fc00000` | `3f800000` | `bf800000` |
| -0.0 | `80000000` | `80000000` | `ff800000` | `00000000` | `ff800000` | `ff800000` | `00000000` | `00000000` |
| 0.0 | `00000000` | `00000000` | `7f800000` | `00000000` | `7f800000` | `ff800000` | `00000000` | `00000000` |
| +inf | `7f800000` | `7f800000` | `00000000` | `7f800000` | `00000000` | `7f800000` | `7f800000` | `3f800000` |
| -inf | `ff800000` | `7fc00000` | `7fc00000` | `7f800000` | `80000000` | `7fc00000` | `7f800000` | `bf800000` |
| qNaN | `7fc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `00000000` |
| -qNaN | `ffc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `00000000` |
| denormal 0x00000001 | `00000001` | `00000000` | `7f800000` | `00000000` | `7f800000` | `ff800000` | `00000001` | `00000000` |
| denormal 0x007fffff | `007fffff` | `00000000` | `7f800000` | `00000000` | `7f800000` | `ff800000` | `007fffff` | `00000000` |
| -denormal 0x80000001 | `80000001` | `80000000` | `ff800000` | `00000000` | `ff800000` | `ff800000` | `00000001` | `00000000` |
| smallest normal 0x00800000 | `00800000` | `20000000` | `5f000000` | `00000000` | `7e800000` | `c2aeac50` | `00800000` | `3f800000` |
| 0x00ffffff | `00ffffff` | `203504f3` | `5eb504f4` | `00000000` | `7e000001` | `c2ad496b` | `00ffffff` | `3f800000` |
| 1e-20 | `0e8d1e59` | `27066639` | `57f3cf8f` | `00000000` | `706833b2` | `c287a965` | `0e8d1e59` | `3f800000` |
| 0x3f7fffff | `3f7fffff` | `3f7fffff` | `3f800000` | `3f7ffffe` | `3f800001` | `b3800000` | `3f7fffff` | `3f800000` |
| qNaN payload 0x7f800001 | `7f800001` | `7fc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `7f800001` | `00000000` |

Four things in it are worth naming, because each one is a rule rather than a value:

* **A denormal is read as a zero of the same sign and never answered.** `sqrt` of `0x00000001` is
  `00000000` and of `0x80000001` is `80000000`; `sign` of `0x00000001` is `00000000`; `reciprocal` of
  `0x00000001` is `7f800000`. The result is flushed as well as the operand, which is a different rule and
  shows in one row: `square` of `0x00800000` is `00000000`, because the square of the smallest normal is a
  denormal, while `square` of `0x3f7fffff` is `3f7ffffe`, which is neither.
* **A NaN a kind computes is the arithmetic's own.** Every computing column answers `7fc00000` for
  `ffc00000` and for the payload-carrying `7f800001` — the sign and the payload are both gone — and the
  two copying columns are the two that keep them: `abs` of `7f800001` is `7f800001`, and `identity` of
  `7f800001` is `7f800001` too.
* **A negative zero is a negative zero.** `sqrt` of `80000000` is `80000000`, where a `fabs` before the
  root could not have answered it.
* **`log` of a zero is `-inf` and `sign` of a NaN is `0`.** Both are in the table and neither needs a case
  of its own, which is the point of taking them out.

**A half is a different arithmetic on this host, and the port now carries the half of it that is a
rule.** The case file feeds the same sixteen classes in `MPSDataTypeFloat16` as in float32, and the run
compares the two families side by side: `tests/backports/host/mpsgraph/run.sh` reports
`port: same as the system on 17 of the 24 cases with a result buffer; 7 float16 cases differ in 22 of
their cells, recorded` and `checks=24 failures=0 recorded=7`. Every float32 case is byte-identical and
170 of the 192 half cells are.

What the release's half path answers where a float32 does not, and what `CharonMPSGraphApply` now
answers the same way:

| | the release | measured on |
| --- | --- | --- |
| a zero result | `0000`, the sign gone | the identity of a half `-0.0` is `0000`, a square root of `-0.0` is `0000`, the reciprocal of `-inf` is `0000` |
| a NaN to the square, the absolute value | `7c00` | `7c00` for a NaN of either sign |
| a NaN to the identity, an addition, a subtraction | `7c00` or `fc00`, the NaN's own sign | `identity(0x7e00)` is `7c00` and `identity(0xfe00)` is `fc00`; `add(0x7c00, 0x7e00)` is `7c00` and `add(0xfc00, 0xfe00)` is `fc00` |
| a NaN to a reciprocal, a reverse square root, a logarithm | `0000` | `reciprocal(0x7e00)` is `0000`, `rsqrt(0x7e00)` is `0000`, `log(0x7e00)` is `0000` |
| a NaN to a square root | `7c00` for a positive one, `0000` for a negative one | the sign bit, read as a bit: a NaN compares false against everything |
| a NaN to the sign | `3c00` or `bc00` | the sign bit and not a comparison, so `sign(0xfe00)` is `bc00` |
| a negative argument to a square root, a reverse square root | `0000` | `sqrt(0xbc00)`, `sqrt(0x8001)` and `rsqrt(0xbc00)` are all `0000` |
| a zero to a reverse square root | `7c00` for either sign | `rsqrt(0x0000)` and `rsqrt(0x8000)` are both `7c00`, where the reciprocal of a negative zero is a negative infinity |
| a zero to a logarithm | `f98c`, which is `-45440` | `log(0x0000)` and `log(0x8000)` are both `f98c`, where IEEE answers `-inf` |
| anything else that is not a positive number, to a logarithm | `0000` | `log(0xbc00)`, `log(0x7c00)`, `log(0xfc00)` and `log(0xfe00)` are all `0000`, where IEEE answers a NaN, an infinity and two NaNs |
| a denormal | kept | `identity(0x0001)` is `0001` and `abs(0x8001)` is `0001`, where float32 answers `00000000` |

**A halfway half rounds away from zero here, and now does in the port's MPSGraph path.**
`CharonMPSFloatToHalfRounded` in `../MetalPerformanceShaders/CharonMPS.h` takes the rounding as an
argument, `CharonMPSStoreRounded` passes it on to the narrowing, and the interpreter's two stores ask
for it; `CharonMPSFloatToHalf` and `CharonMPSStore` are the same functions with the even rounding and
every other family keeps calling those, so the matrix and image kernels do not move. Measured: an
addition of `2^-10` to 3.0 is exactly halfway between two halves and the release answers `4201`, and
a square root of `3c01` — `sqrt(1 + 2^-14 * 2)` — is exactly halfway and the release answers `3c01`,
where round-to-even gives `3c00`. **Four cells left the record when this was applied, not three**: it
also fixed a multiply of a half denormal by 0.5 and a division of one by -0.5, whose exact answers are
both halfway between two halves.

**The 18 cells that are still not the release's, and the rule attempted for each group.**
`tests/backports/host/mpsgraph/recorded-cells.txt` names each of them with the two sets of bytes, and the
comparison is per cell: a cell that is not on that list fails, and so does a cell on it whose bytes are
not the two written there, so neither a new divergence nor a stale record can pass.

**Seven are the release's own approximation**, within one unit in the last place of a half or near it:
`log(0x03ff)` and `log(0x0400)` are `c8db` where the correctly rounded half of the exact logarithm is
`c8da`, `log(0x1400)` is `c6ef` against `c6ee`, `log(0x3555)` is `bc66` against `bc65`, `rsqrt(0x3555)` is
`3eef` against `3eee`, and `sqrt(0x3c01)` is `3c01` against `3c00`. **Attempted and rejected**: that the
kernels keep their intermediate in a half, which is the shape the coordinator suggested. Three models
were measured against all sixteen cells of each kind — the operation narrowed once, `x` times a reverse
square root narrowed to a half, and a reverse square root of the narrowed reciprocal — and each explains
*fewer* cells than the single narrowing the port already does: 6, 7 and 7 of 16 against 8 for the square
root, 5 and 7 of 16 against 8 for the reverse square root. For the logarithm, three models — one
narrowing, a `log2` narrowed to a half and then multiplied by `ln2`, and a `log2` narrowed twice —
explain **0 of the 5** recorded cells. A half-precision intermediate is therefore not what is happening,
and what is left is the compiler's own approximation, whose coefficients are not derivable from the
specification. **Owed, not attempted further.**

**Eleven are the release's half binary arithmetic answering what no operation of the specification
produces**, and every one of them has an operand that is a zero, an infinity, a NaN or a denormal: a zero
times an infinity is `0000` where IEEE answers a NaN, an infinity times a NaN is `7c00` and a negative
infinity times a negative NaN is also `7c00` — the sign of the infinity gone — a positive NaN times a
denormal is `1e00` (`0.00585938`) and a negative NaN times 2.0 is `fc00`, a division of a NaN is `7c00`
and of a negative NaN is `fa00` (`-49152`), a division of `-1.0` by `-0.0` is `fc00` where IEEE answers
a positive infinity, and a subtraction of `+inf` and a NaN is `f800` (`-32768`) and of `-inf` and a NaN
is `7800` (`32768`). **Attempted and rejected**: the two suggestions, in the form each can be measured.
A half denormal read with the wrong exponent bias is ruled out by the ratios — the release's answers for
an operation with a denormal operand were 2×, 2× and 4× the exact value and `0.00585938`, and no single
exponent field gives a fixed ratio across them. A clamped or fast-math float path is ruled out by the
group's own answers: within one class of operand — one that is not a finite non-zero normal — the release
answers `0000`, `7c00`, `fc00`, `1e00` and `0000`, and no rule over the class produces five different
values. Five substitutions were measured against all eleven cells: IEEE itself explains 3, "a NaN operand
becomes the largest finite half" 1, "a NaN operand becomes an infinity" 2, "a zero operand makes the
product a zero" 5, and "computed in a float32 with denormals flushed" 2. Nothing explains a group.
**Owed, not attempted further**: a kernel that answers these is not a function of the operations the
specification names, and reproducing it bit for bit would be a table of its answers.

The buffer a half case needs is sixteen elements: `MPSNDArray` refuses a shorter one — "buffer is not
large enough. Must be 32 bytes", `MPSNDArray.mm:893` — so a half tensor in this harness cannot be
smaller than 32 bytes.

Two of the case file's cases are not counted as agreeing:

* **A constant** cannot be asked for at all on this host. `-[MPSGraph constantWithShape:dataType:values:name:]`
  aborts the process, so it is asked for **last**, after everything the host does answer, and the run
  stops there on the host side. An earlier version of the case file had it in the middle of the unary
  family, where it took seven cases down with it - and because the harness compared the shorter of the
  two runs, those seven counted as agreeing.
* **A placeholder's `dataType`** is the other one that is not comparable, for the reason below.

The harness now **fails on a length mismatch** rather than truncating to the shorter side, and names the
case each side last reached, so an abort in either run cannot be read as agreement.

One thing the harness did teach, and which is written into the case file: **reading a shaped type's
equality, or a placeholder's `dataType`, takes the release down** — it calls
`-[MPSGraphTensor tensorDataType]`, a selector its own `MPSGraphTensor` does not declare. So those
answers are not comparable on this host and the case file does not ask for them.

## The elementary family of 14.0, and what the release's own kernels do

Fifty-three methods of the 14.0 arithmetic, rounding, comparison, logical and activation surface are
written, in `MPSGraph14.m` and in the interpreter beside it: the transcendentals, the two roundings, the
six comparisons and the six logicals, the three questions about a value, the two remainders, a minimum, a
maximum, a division that answers no NaN, the select, the clamp, a ReLU and a sigmoid with their gradients.
Every one of them is asked over the case file's sixteen input classes in `MPSDataTypeFloat32` and in
`MPSDataTypeFloat16`, and **18 of the 53 come back with every cell byte-identical to the release in both
types** - the row of each is in the registry, and the run's verdict line is
`port: same as the system on 1852 of the 2048 cells with a result buffer; 196 recorded` with
`checks=128 failures=0`.

**A predicate's result is a boolean and the logical family's is not.** Measured on this host's own
MPSGraph over a rank-3 float32 operand: `isNaN`, `isFinite`, `isInfinite`, `equal`, `notEqual`,
`lessThan`, `lessThanOrEqualTo`, `greaterThan` and `greaterThanOrEqualTo` answer `MPSDataTypeBool`, which
is `MPSDataTypeAlternateEncodingBit | 8` (MPSCoreTypes.h:260) and **one byte** an element
(`MPSSizeofMPSDataType(MPSDataTypeBool)` is 1, measured), while `logicalAND`, `logicalOR`, `logicalNAND`,
`logicalNOR`, `logicalXOR`, `logicalXNOR`, `not` and `signbit` answer the operand's own type. The port
therefore has two builders - `charon_mps_arithmetic:operands:name:` and
`charon_mps_predicate:operands:name:` - and `CharonMPSLoad` and `CharonMPSStoreRounded` in
`../MetalPerformanceShaders/CharonMPS.h` carry the one-byte type.

**A minimum and a maximum are `fmin` and `fmax`, not an operator.** Measured: a minimum of `+inf` and a
NaN is `0x7f800000`, of `-inf` and a NaN is `0xff800000` and of a NaN and `0x00000001` is `0x00000001`,
where a comparison would answer a NaN for each.

**Eleven kinds read an operand as it is stored and do not see a denormal as a zero**, and the other kinds
do: `absolute`, `identity`, `signbit`, `negation`, `round`, both remainders, `minimum`, `maximum`,
`select` and `clamp`. Measured for each: the negation of `0x00000001` is `0x80000001`, a modulo of
`0x00000001` by `-2.0` is `0x00000001`, a minimum of `0x00000001` and `0x7e00` is `0x00000001`, and a
select whose predicate is a NaN takes the branch it takes for any other non-zero. A ReLU is not among
them: it answers `0x00000000` for a denormal, measured.

**Seven kinds answer the NaN they were given and the rest answer the arithmetic's own.** The negation of
`0x7fc00000` is `0xffc00000`, which is what a sign-bit flip answers; `round`, `arcsin`, `arctangent`, the
hyperbolic arc-sine, the hyperbolic arc-tangent and `select` each keep the sign too, and `identity` copies
the NaN's bits outright. Every other kind that computes answers `0x7fc00000` for either sign.

**A round that lands on zero is a positive zero** (measured for `-0.0`, `-0x1p-126` and `-0x1p-20`, each
`0x00000000`, where C's `round(-0.0)` is `-0.0`).

**A sigmoid's gradient reads the source as the value that was activated, not as its answer.** Measured:
a `sigmoidGradient` of an incoming gradient of `1.0` over a source of `0.0` is `0x3e800000`, which is
`1.0` times the sigmoid of `0.0` times one minus the sigmoid of `0.0`.

**`divisionNoNaN` decides on the divisor and a NaN divisor is not one of them.** Measured: a zero divisor
answers `0x00000000` for every numerator, and a NaN divisor answers the arithmetic's NaN - `+inf` over
`0x7e00` is `0x7fc00000`, and `0xfe00` over `2.0` is `0x7fc00000`.

### The 196 recorded cells, grouped

`tests/backports/host/mpsgraph/recorded-cells.txt` names each one with the two runs' bytes. They are of
four kinds and none of them is a tolerance:

* **58 float32 cells, all in the transcendental family and in the two sigmoid gradients.** The release's
  transcendentals are not the C library's: measured cell by cell over the sixteen classes, `sin`, `tan`,
  `sinh`, `asinh`, `atanh`, `logBase10`, `expBase10`, `atan2` and `power` agree with the *float32*
  function where the port computes in double and rounds once (`sin` of `1.0` is `0x3f576aa5` where
  `sin` in double rounded to float is `0x3f576aa4`), while `asin`, `acos` and `atan` agree with the double
  one, and `cosh`, `erf`, `tanh` and `sigmoid` agree with neither by one unit in the last place. Choosing
  per operation between the float32 and the double spelling would make most of these cells agree, and is
  not done: it fits twenty measurements rather than stating a rule, and the release's kernels are Metal's
  own approximations, whose coefficients are not derivable from the specification.
* **140 float16 cells.** The same four kinds in `MPSDataTypeFloat16`, where the release's half kernels
  answer the special classes by rules of their own - the ones already measured for the arithmetic family
  are the table above - and where a per-operation half rule has not been derived yet. The families with
  the fewest are `expBase10` and `acosh` and `acos` and `rint` (none), `signbit` and `reLU` and `minimum`
  and `atanh` and `asinh` and `ceil` (one to three) and the ones with the most are `sigmoidGradient`
  (fourteen) and `tanh` (seven) and `erf` (seven).
* **8 boolean cells**, all of them a comparison whose float16 operand is a NaN: `lessThan` and
  `lessThanOrEqualTo` answer `true` for `+inf` against `0x7e00` and for `-NaN` against `2.0`, and
  `greaterThan` and `greaterThanOrEqualTo` answer `true` for `-inf` against `0xfe00` and for `0x7e00`
  against `0x0001`, where every other comparison of the same case answers what IEEE answers. The release's
  own diagnostic names the kernel: `ConvertBinaryCompareToZero expects the second operand to be zero`
  (MPSGraphUtilities.mm:254).
* **Cells of the pre-existing arithmetic family**, which the record already carried and which the same
  per-cell comparison re-checks.

**One thing the harness had to be taught.** The framework writes its own diagnostics to the same standard
output the cases go to, and with a block-buffered stream one of them landed in the middle of a case line: a
flush boundary split the sixteen halves of `subtract float16` and the line carried the tail of a warning
instead of its last four bytes. The case file now sets `setvbuf(stdout, NULL, _IOLBF, 0)`, so a case is one
line or nothing, and `run.sh` compares only the lines the case file marks `#case`, so the framework's
diagnostics are not cases. The size of the result table went from sixty-four to five hundred and twelve for
the same reason: it held one entry per case and there are a hundred and thirty now, so a hundred and
twenty-ninth case wrote past its own end.

Not written of this family: the soft-max pair, which is an axis reduction and wants the reduction
machinery first. The rest of the 14.0 surface - reductions, matmul, convolution, pooling, normalization,
the shape operations, control flow, random, the optimizers - is not written either, and each is a family
of the same shape.

## The arithmetic family, and the rest

Addition, subtraction, multiplication, division, and the unary operations negation, square,
reciprocal, square root, reverse square root, exponential, logarithm, absolute and sign. Each is a kind
in `CharonMPSGraphOperationKind` and a case in the interpreter, so a family lands by adding a kind and a
function rather than by touching every other operation.

Not written: reductions, matmul, convolution, pooling, normalization, activation, shape operations,
control flow, random, optimizers, and the rest of the surface. Each is a family of the same shape, and
each wants the differential to run a graph end to end first.

## The R4 names this band adds, in full

The SDK this package compiles against, the iPhoneOS 16.4 one, declares none of these: they are the
private surface the two families use to share their own state, and each is a registered implemented name
that no header the build sees declares. **27 of them**, read out of the compiled objects with
`nm -g --defined-only`, not from the sources, so a declaration and a definition are not confused:

* `-[MPSGraph charon_mps_addOperationOfKind]` — MPSGraph14.m
* `-[MPSState charon_mps_appendBuffer]` — MPSState11.m
* `-[MPSState charon_mps_appendResource]` — MPSState11.m
* `-[MPSState charon_mps_appendTexture]` — MPSState11.m
* `-[MPSGraph charon_mps_arithmetic]` — MPSGraph14.m
* `-[MPSMatrixRandom charon_mps_batchOver]` — MPSMatrixRandom13.m
* `-[MPSMatrixRandom charon_mps_configureWithDataType]` — MPSMatrixRandom13.m, MPSMatrixRandomMTGP3213.m, MPSMatrixRandomPhilox13.m
* `-[MPSMatrixCopy charon_mps_destinationAtIndex]` — MPSMatrixCopy11.m, MPSMatrixCopyDescriptor11.m
* `-[MPSCNNConvolutionDescriptor charon_mps_fold]` — MPSCNNConvolutionDescriptor10.m
* `-[MPSCNNBatchNormalization charon_mps_foldFromDataSource]` — MPSCNNBatchNormalization12.m
* `-[MPSCNNConvolutionWeightsAndBiasesState charon_mps_listOfBufferSizes]` — MPSCNNConvolutionWeightsAndBiasesState11.m
* `-[MPSMatrixCopy charon_mps_offsetsAtIndex]` — MPSMatrixCopy11.m, MPSMatrixCopyDescriptor11.m
* `-[MPSGraph charon_mps_operation]` — MPSGraph14.m
* `-[MPSGraph charon_mps_runOperation]` — MPSGraph14.m, MPSGraphInterpreter14.m
* `-[MPSMatrixLogSoftMax charon_mps_setLogarithmic]` — MPSMatrixLogSoftMax12.m, MPSMatrixSoftMax12.m
* `-[MPSCNNPooling charon_mps_setMaximum]` — MPSCNNPooling10.m
* `-[MPSCNNConvolutionDescriptor charon_mps_setNeuronParameterC]` — MPSCNNConvolutionDescriptor10.m
* `-[MPSGraph charon_mps_setOutputTensors]` — MPSGraph14.m, MPSGraphOperation14.m
* `-[MPSGraph charon_mps_setParameters]` — MPSGraph14.m, MPSGraphOperation14.m
* `-[MPSCNNKernel charon_mps_setWindowWidth]` — MPSCNNKernel10.m, MPSCNNPooling10.m
* `-[MPSMatrixCopy charon_mps_sourceAtIndex]` — MPSMatrixCopy11.m, MPSMatrixCopyDescriptor11.m
* `-[MPSState charon_mps_temporaryWithBlock]` — MPSState11.m
* `-[MPSMatrixCopyDescriptor charon_mps_withCount]` — MPSMatrixCopyDescriptor11.m
* `-[MPSTemporaryMatrix charon_mps_withReadCount]` — MPSTemporaryMatrix11.m, MPSTemporaryVector12.m
* `-[MPSMatrixRandom charon_mps_wordAtIndex]` — MPSMatrixRandom13.m
* `-[MPSCNNPooling charon_mps_zeroPadSizeX]` — MPSCNNPooling10.m
* `-[MPSCNNPooling charon_mps_zeroPadSizeY]` — MPSCNNPooling10.m

The graph's are the interpreter's — its kinds, its per-operation wiring, its element accessors — and the
matrix and CNN families' are the window, the fold, the state and the copy descriptor's. None of them is
called by an application. Each needs the lift's sets re-measured in the same push as the ones that land
with them, and the list is regenerated from the objects whenever the family changes.
