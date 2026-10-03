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
`MPSDataTypeFloat16`, and **36 of the 53 come back with every cell of every case agreeing with the release in both
types** - the row of each is in the registry, and the run's verdict line is
`port: same as the system on 3609 of the 3808 cells with a result buffer; 3410 within the release's own
precision, 199 recorded` with `checks=128 failures=0`.

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

**Sixteen kinds read an operand as it is stored and do not see a denormal as a zero**, and the other kinds
do: `absolute`, `identity`, `signbit`, `negation`, `round`, both remainders, `minimum`, `maximum`,
`select`, `clamp`, and the five `sin`, `sinh`, `arcsin`, `asinh` and `atanh` - for those five the
release's own answer for a tiny argument is the argument, so `sin`, `sinh`, `arcsin`, `asinh` and `atanh`
of `0x00000001` are each `0x00000001` and of `0x80000001` are each `0x80000001`. Measured for the rest:
the negation of `0x00000001` is `0x80000001`, a modulo of `0x00000001` by `-2.0` is `0x00000001`, a
minimum of `0x00000001` and `0x7e00` is `0x00000001`, and a select whose predicate is a NaN takes the
branch it takes for any other non-zero. Three are **not** among them and are left out for that reason:
`arctangent`, the hyperbolic tangent and `erf` each answer `0x00000000` for `0x00000001` and
`0x80000001` for `0x80000001`, and a ReLU answers `0x00000000` for a denormal.

**A zero is a positive zero for `arctangent` and for the hyperbolic tangent, and for those two only.**
Measured: the arctangent and the hyperbolic tangent of `-0.0` are `0x00000000` where IEEE answers
`-0.0`, and the hyperbolic tangent of a negative denormal is `0x00000000` as well. The identity, a
reciprocal, a square root, a remainder, a minimum and a maximum all answer `-0.0` for a negative zero on
this host, measured, and are left alone - applying the rule to the whole family was tried and cost ten
cells that were right (`recorded-cells.txt` went from 196 to 208 and `identity`, `reciprocal`, `rint`,
`sqrt`, `divide`, `minimum`, `maximum`, `modulo`, `negative`, `select` and `round` each lost a float32
cell).

**A kind that keeps the NaN it was given keeps it only when it WAS given one.** Measured: the arcsine of a
NaN is that NaN, `0xffc00000` for a negative one, and the arcsine of `-inf` is `0x7fc00000` and not a NaN
of a negative sign.

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

### One row per operation: how much of the release each candidate spelling reproduces

The coordinator's question for the float32 residue was which precision each operation is computed in, and
the answer is measured per operation rather than argued. `.agent-work/runs/probe/float32-spellings.c`
computes, for each of the eighteen transcendental operations, the sixteen answers under both spellings -
the `float` function and the `double` one rounded to a float on store - and they are compared with the
release's own sixteen from the harness's `system` run. **How many of the sixteen classes each spelling
gets right:**

| operation | `sinf` and friends | `sin` and friends, rounded once | the operation's own class |
| --- | --- | --- | --- |
| `cos` | 16 | 16 | exact |
| `atanh` | 16 | 16 | exact |
| `acosh` | 15 | 15 | 1 cell |
| `sinh` | 15 | 15 | exact, the 15th class being the flush |
| `exp2` | 15 | 15 | 3 cells, all in half |
| `tan` | 14 | 14 | 4 cells |
| `acos` | 14 | 15 | 1 cell |
| `exp10` | 14 | 14 | 1 cell |
| `cosh` | 14 | 14 | 2 cells |
| `asin` | 13 | 14 | 1 cell |
| `asinh` | 13 | 13 | 4 cells |
| `sigmoid` | 13 | 14 | 1 cell |
| `sin` | 12 | 12 | 3 cells |
| `log2` | 13 | 13 | 8 cells, all in half |
| `atan` | 11 | 13 | 6 cells, all in half |
| `log10` | 9 | 9 | 4 cells |
| `erf` | 5 | 5 | 8 cells |
| `tanh` | 4 | 4 | 9 cells |

The two columns are equal on twelve of the eighteen, because this machine's `sinf(1.0f)` and
`(float)sin(1.0)` are the same sixteen values - it is a correctly rounded float32 either way. The six
where they differ are `acos`, `asin`, `atan` and `sigmoid`, which the `double` spelling gets one class
more, and **none of the eighteen is exact under either spelling**. That is the measurement: the release's
transcendental kernels are Metal's own, and neither precision of the C function is them. The rows this
family registers are therefore the ones whose cells agree whatever the spelling, and they are named in
their own rows.

### What "the same arithmetic" means for a kernel that is not the C library's

Sixteen classes are not enough to measure a precision, so the sweep is **thirty-two**: the sixteen classes
above and then sixteen ordinary values - `2^-16` and `2^-15` and three quarters and seven eighths of each,
and one plus each of those, and their negatives - because those are the inputs whose last bit a kernel's own
rounding is decided on. Every case of every family runs over the whole thirty-two in both types, and the run
compares **3808 cells** where it compared 2048.

Where the two answers of a cell differ, the comparison asks how far apart they are in units in the last
place before it calls the cell a difference: the bit patterns are read as signed integers in sign-magnitude
order, so the distance is how many representable values lie between them; a zero of either sign is the same
value, and a NaN against a number is no distance at all and stays recorded whatever the tolerance says.

**And how far they may be is the specification's figure, not this differential's.** The source is the
*Metal Shading Language Specification*, version 2026-06-04, section **8.4 "ULPs and Relative Error"**: its
single-precision table is **Table 8.1** (pages 368-369) and its half-precision table is **Table 8.3**
(pages 373-374, which "applies to iOS and macOS, starting with Apple GPU Family 4 hardware" - what this
host is). `tests/backports/host/mpsgraph/tolerances.txt` carries the figures by table and page, and where a
row of either table reads "Correctly rounded" the figure is zero: the specification holds `sqrt`, `rsqrt`,
`rint`, `round`, `ceil` and `floor` to the correctly rounded answer, so those are compared byte for byte.
The figures that are here: `acos`, `acosh`, `asin`, `asinh` four and `atan`, `atanh` five in single
precision; `atan2` six; `cos`, `cosh`, `exp2`, `exp10`, `log2`, `log10`, `sin`, `sinh` four; `tan` six;
`tanh` five; `pow` sixteen. Every half figure is one, Table 8.3 giving one for each of them.

**Two operations of this family are in neither table, and that is what decides them.** The specification
does not define or bound `erf` at all, in either precision, so there is no documented bound to hold it to
and its fifteen cells are compared byte for byte and recorded where the two differ - its row stays
`missing`. A half `pow` is likewise absent from Table 8.3 while the single-precision `pow` is in Table 8.1,
so `pow` carries the single figure and its half cells are byte for byte. A sigmoid is not a function the
specification names either, so its figure is the sum of two it does: `sigmoid(x)` is one over one plus an
exponential of the negated argument, `exp` is four in Table 8.1 and one in Table 8.3, and `x / y` and
`1.0 / x` are "Correctly rounded" in the same two tables and add nothing - four and one.

**The measured distance, next to the figure it is held to.** Every operation's measured maximum over the
thirty-two classes is one or two units in the last place except three: the hyperbolic tangent's is eleven in
half against a figure of one, the arctangent's is three against a figure of one, and a power's is two in
half against no figure at all. All three are recorded cell by cell, which is what the record is for. The
other measured maxima sit at or inside their figure:

| operation | measured float32 | figure | measured float16 | figure |
| --- | --- | --- | --- | --- |
| `sin`, `cos`, `sinh`, `cosh`, `tan` | 1 | 4, 4, 4, 4, 6 | 1 | 1 |
| `asin`, `asinh` | 1 | 4 | 0 | 1 |
| `atan` | 0 | 5 | 3 | 1 |
| `atanh` | 0 | 5 | 0 | 1 |
| `atan2` | 1 | 6 | 0 | 1 |
| `acos`, `acosh` | 0 | 4 | 0 | 1 |
| `exp2`, `exp10`, `log2`, `log10` | 1 | 4 | 0 or 1 | 1 |
| `power` | 1 | 16 | 2 | none |
| `sigmoid` | 1 | 4 | 1 | 1 |
| `tanh` | 1 | 5 | 11 | 1 |
| `erf` | 2 | **none** | 1 | **none** |

**No non-transcendental case has a tolerance at all.** A predicate, a logical, both remainders, a minimum,
a maximum, a select, a clamp, a rounding, the three questions about a value, a ReLU and a ReLU gradient are
compared byte for byte in both types, and the six comparisons and the four orderings byte for byte as one
byte each. That is deliberate: their answers are a truth, a whole number or one of two orderings, and "within
N units in the last place" is not a thing for any of them.

**What a mutation does to it**: `port: same as the system on 3609 of the 3808 cells with a result buffer;
3410 within the release's own precision, 199 recorded`, `checks=128 failures=0`, and the planted build still
differs from the release in 128 of the 130 cases. The red control is why a tolerance is safe here: the plant
is every stored element off by one whole unit of the value, which is between 10^6 and 10^38 units in the
last place, so no figure anywhere near four can hide it.

### What a NaN, an infinity and a zero are in half, per operation

The release's half kernels do not agree with each other about a NaN, and each of them answers it its own
way. Measured over the case file's thirty-two classes, `CharonMPSGraphHalfNaNOf` in the interpreter is the
table, one entry per kind, and this is what it says:

| a kind's answer in half for a NaN operand | the kinds | measured |
| --- | --- | --- |
| an infinity of the NaN's own sign | the arithmetic family (`abs`, `identity`, `add`, `subtract`, `square`), and `ceil`, `floor`, `round`, `select`, a ReLU's gradient, a ReLU | `0x7e00` is `0x7c00` and `0xfe00` is `0xfc00` |
| an infinity of the other sign | `negative` | the negation of `0x7e00` is `0xfc00` and of `0xfe00` is `0x7c00` |
| a zero | `sin`, `cos`, `logBase2` | each of `0x7e00` and `0xfe00` is `0x0000`, and so is each of them of an infinity of either sign |
| the canonical positive NaN | `asin`, `acos`, `asinh`, `acosh`, `atanh` | the arcsine, the hyperbolic arc-sine and the hyperbolic arc-tangent of `0xfe00` are `0x7e00` |
| a saturation at the NaN's sign | `erf`, `tanh` | `erf(0x7e00)` is `0x3c00` and `erf(0xfe00)` is `0xbc00`; the hyperbolic tangent the same |
| a saturation at one whatever the sign | `power` | a power of an infinity, of a NaN and of a negative ordinary value are all `0x3c00` |
| one for a positive NaN and a zero for a negative one | `sigmoid` | `sigmoid(0x7e00)` is `0x3c00` and `sigmoid(0xfe00)` is `0x0000` |
| read off the bit rather than off the class | `sqrt`, `sign` | the square root of `0x7e00` is `0x7c00` and of `0xfe00` is `0x0000`, and the sign of a NaN is the sign of the NaN |

**A zero is a positive zero in half, for every kind and not per operation.** Measured: the ceiling and the
floor and the sine of a positive zero, a product of a negative zero, the negation of a negative zero, a
maximum of `-1.0` and `-0.0`, a select whose value is a negative zero, a ReLU's gradient of a negative
ordinary source and an error function of a positive zero are each `0x0000`, where IEEE answers a zero of
the operand's own sign. The rule is applied after the half block and before the store, so it also covers
the kinds the half block does not reach.

Together the table and that rule took the run from 208 recorded cells to 166, and with the figures the
specification gives, **36 of the 58 cases of this family are clean in every type**: the six comparisons and the four orderings are clean in float32 only,
and the six remainders' float32 answers are the recorded group the previous pass measured.

### The recorded cells, grouped

`tests/backports/host/mpsgraph/recorded-cells.txt` names each of the 199 with the two runs' bytes, read
out of the run's own outputs by `.agent-work/record.py`. They are of three kinds, and none of them is a
tolerance:

* **The float32 cells that are not a difference in value**: the hyperbolic tangent's nine and the two sigmoid gradients' four, where the release's answer for a NaN, a zero or a denormal is not a number at all. The release's
  transcendentals are not the C library's, in either precision. Measured cell by cell over the sixteen
  classes: the release's `sin` of `1.0` is `0x3f576aa5`, this machine's own `sinf(1.0f)` is `0x3f576aa4`
  and `(float)sin(1.0)` is `0x3f576aa4` as well, and `0x3f576aa4` is the correctly rounded one - the exact
  value `0.8414709848` is nearer `0x3f576aa4` than `0x3f576aa5` - so the release's kernel is an
  approximation and neither spelling of the C function is it. The same holds for the rest of the family:
  `coshf(1.0f)` is `0x3fc583ab` and the release answers `0x3fc583aa`, `erff(1.0f)` is `0x3f57bb3d` against
  the release's `0x3f57bb3c`, and `tanhf(1.0f)` is `0x3f42f7d6` against the release's `0x3f42f7d5`.
  **Attempted and rejected**: giving each transcendental the float32 spelling when its operand is a
  float32, which is the one thing the measurement suggests a reader would try. Measured by building it
  and running the whole file: it fixes **no** cell and makes **five** differ - `acos` 0 to 1, `asin` 4 to
  5, `atan` 2 to 4, `atan2` 1 to 3 and `sigmoid` 1 to 2, 196 to 203 recorded. The tree therefore keeps one
  spelling, the double one, and the transcendental family's float32 cells stay recorded. What would remove
  them is the release's own polynomial, which is not in any header and is not derivable from the
  specification of the operation.
* **Most of the 208 are float16.** The same four kinds in `MPSDataTypeFloat16`, where the release's half kernels
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

Not written: matmul, convolution, pooling, normalization, activation, shape operations,
control flow, random, optimizers, and the rest of the surface. Each is a family of the same shape, and
each wants the differential to run a graph end to end first.

## The reduction family of 14.0

A reduction is the first family here whose result is not the operand's shape, so it is walked by a
function of its own (`CharonMPSGraphReduce` in `MPSGraphInterpreter14.m`) over the OPERAND rather than by
the element-at-a-time loop the arithmetic family uses, and `graph-cases.m` asks it through a case helper
of its own (`reduction_case`) that gives the compile a feed of the operand's shape and a destination of the
result's.

Measured against this host's own MPSGraph (macOS, Apple M4 Pro), over a 2x4 feed of
(1, 2, 3, 4 | 10, 20, 30, 40) and over the case file's sixteen input classes, in MPSDataTypeFloat32,
MPSDataTypeInt32 and MPSDataTypeFloat16. `bytes` is the release's own answer, little-endian, and every one
of them is byte-identical to the port's:

| question | answer |
| --- | --- |
| `reductionSumWithTensor:axis:0` over the 2x4 | shape (1, 4), `00003041 0000b041 00000442 00003042` = (11, 22, 33, 42) |
| `reductionSumWithTensor:axis:1` | shape (2, 1), `00002041 0000c842` = (10, 100) |
| `axis:-1` and `axes:@[1]` | the same bytes and the same (2, 1) as `axis:1` |
| `axis:-2` | the same bytes and the same (1, 4) as `axis:0` |
| `axes:@[@1, @0]` and `axes:@[@0, @1]` | both shape (1, 1), `0000dc42` = 110 |
| `axes:@[@0, @0]` | the same bytes and the same (1, 4) as `axes:@[@0]`: a set, so a repeated axis reduces once |
| `axes:@[]` | shape (2, 4) and the operand's own bytes: no axis is reduced |
| `axes:nil` | shape (1, 1), `0000dc42` = 110: nil is EVERY axis |
| `reductionProductWithTensor:axis:1` | `0000c041 00606a48` = (24, 240000) |
| `reductionMaximumWithTensor:axis:1` | `00008040 00002042` = (4, 40) |
| `reductionMinimumWithTensor:axis:1` | `0000803f 00002041` = (1, 10) |
| `meanOfTensor:axes:@[@1]` | `00002040 0000c841` = (2.5, 25); as int32 `ffffffff 02000000` = (-1, 2), the truncated quotients; as float16 `0041 8046` = (2.5, 6.5) |
| `varianceOfTensor:axes:@[@1]` | `0000a03f 0000fa42` = (1.25, 125); as int32 `01000000 01000000`; as float16 `003d 003d` = (1.25, 1.25) |
| `varianceOfTensor:meanTensor:axes:@[@1]` over the same feed and the mean of it | the same bytes as the variance above |

The three rules of the set of axes, which is what a caller can get wrong and what the port normalises:
a negative axis is counted from the end of the rank, the order written does not matter, and nil is every
axis while an empty array is none.

### The NaN in a reduction, which is the whole of the difference between the four extremes

Over a feed of (1, NaN, 3, 4 | NaN, 6, 7, 8), and then over a 2x4 whose eight elements are all NaN:

| operation | over a row with a NaN | over a row of nothing but NaNs |
| --- | --- | --- |
| `reductionMaximumWithTensor:axis:1` | (4, 8) - the NaN is skipped | `000080ff 000080ff` = negative infinity |
| `reductionMaximumPropagateNaNWithTensor:axis:1` | `0000c07f 0000c07f` = NaN | NaN |
| `reductionMinimumWithTensor:axis:1` | (1, 6) - the NaN is skipped | `0000807f 0000807f` = positive infinity |
| `reductionMinimumPropagateNaNWithTensor:axis:1` | NaN | NaN |

So the kernel seeds an infinity - negative for a maximum, positive for a minimum - and lets one comparison
decide the rest, and a NaN loses every comparison including one against another NaN. That is why a
maximum skips a NaN and why a reduced set of nothing but NaNs answers the seed rather than a NaN. The
propagating variants latch: a NaN that reaches an element is that element's answer and nothing after it
can move it. The sum, the product, the mean and the variance are different - over the same feed all four
answer NaN, because a NaN reaches the arithmetic and the arithmetic's own NaN is what leaves it.

### An axis outside the rank, which the release cannot answer at all

`reductionSumWithTensor:axis:5` over a 2x4 writes `invalid axes: 5` and then takes the process down with
`LLVM ERROR: Failed to infer result type(s)`, so there is no answer to record: the graph is never built.
A port cannot reproduce a process that is gone, and answering a tensor for it would be an answer the
release does not give, so the port raises `NSInvalidArgumentException` when the graph is built instead.
This is the one place in the reduction family where the port is not the release's answer in form, and it
is named in the row of every method of the family.

## The rest of the reduction family: 15.0's argument reductions and NaN-propagating extremes, and 15.3's truth folds

Eight rows: `reductionArgMaximumWithTensor:axis:name:` and `reductionArgMinimumWithTensor:axis:name:` and the
two `WithNaNPropagation` binary forms (15.0, `MPSGraphReductionOps150.m`), and `reductionAndWithTensor:` and
`reductionOrWithTensor:` in both forms (15.3, `MPSGraphReductionOps153.m`).

**How one walk serves three releases.** The walk over the family is a TABLE keyed by the operation's own
parameters, not by its kind: an operation says which combination it folds with (`@"combination"`), whether a
NaN latches (`@"propagateNaN"`), whether the answer is an index rather than a value (`@"index"`), and for the
elementwise half whether the kernel latches a NaN (`@"latchNaN"`). None of those words is a name of any
release's framework, so the 14.0 object that holds the walk and the axis arithmetic names nothing of 15.0 or
15.3, and each of those two objects names only its own four methods. That is the arrangement the coordinator
ruled for this family after v-mps3's report named the question; `relcheck`'s `check_releases` is what reads
it back out of the objects ("compiled 13 objects of MPSGraphBackports", "check_releases: every object of
MPSGraphBackports holds API of one release").

Every cell of every case below is byte-identical between the release and the port, in all three data types
the family is asked in, and none of them is on `recorded-cells.txt`.

### The argument reductions

| question, over the case file's 2x4 feeds | the release's answer | the port |
| --- | --- | --- |
| `reductionArgMaximumWithTensor:axis:1` over the sixteen classes | `00000000 00000000` = (0, 0) | identical |
| `reductionArgMinimumWithTensor:axis:1` over the same | `01000000 01000000` = (1, 1) | identical |
| `argMaximum` over (1, 2, 3, 4 \| 10, 20, 30, 40) | `03000000 03000000` = (3, 3) | identical |
| `argMinimum` over the same | `00000000 00000000` = (0, 0) | identical |
| `argMaximum` over (4, 4, 4, 9 \| 9, 9, 1, 1) | `03000000 00000000` = (3, 0) | identical |
| `argMinimum` over the same | `00000000 02000000` = (0, 2) | identical |
| `argMaximum` and `argMinimum` over a row of nothing but NaNs | `ffffffff ffffffff` = (-1, -1) | identical |
| `argMaximum` over the int32 and over the float16 feed | `03000000 03000000` = (3, 3) | identical |
| `argMaximum axis:0` and `argMinimum axis:0` over the ordinary feed | `01000000 01000000 01000000 01000000` and four zeros, a 1x4 | identical |
| `argMaximum axis:-1` | the same bytes as `axis:1` | identical |

So the rules, all measured: the answer is the index of the **first** element holding the extreme (the tied row
above is what says so - a comparison that replaced on equality would answer the last of the three); a NaN
loses every comparison and is never the answer wherever it sits (measured one NaN at a time at each of the
four positions of a row of four, and at both ends and the middle of a row of nine: `(nan, 1, 2, 3)` answers 3
for a maximum and 1 for a minimum, `(1, 2, 3, nan)` answers 2 and 0, and a row of nine with a NaN at either end
answers 8 and 7); a reduced set of nothing but NaNs answers **-1**, which is "nothing was found" rather than
an index into an empty set; the two signed zeros compare equal, so `(0, -0, 0, -0)` answers 0 for both; and
the answer is stored as **MPSDataTypeInt32** whatever the operand's own type was, which is why the case names
carry the result's type and where it came from.

### The two binary NaN-propagating extremes

The header states the rule (`isNaN(primary) || isNaN(secondary) ? NaN : min(primary, secondary)`) and the
measurement over the case file's sixteen classes in float32 and float16 confirms it: the four NaN positions
answer a NaN each and the four ordinary ones answer exactly what 14.0's pair answers over the same feeds
(`00000000 000080bf 00000080 000080ff` against a primary of (1, -1, +0, -0, +inf, -inf, NaN, -NaN) and a
secondary of (+0, -0, +inf, -inf, NaN, -NaN, 1.4e-45, 2)), so the four NaNs are the whole difference between
the two pairs.

**Every data type that is not a floating point one is refused, and the port refuses exactly that set.**
Measured on this host's own MPSGraph, one type at a time, over a feed of eight ascending bytes against eight
descending ones (which every one of these types reads as the same two numbers), both operations:

| operand type | the release over `minimumWithNaNPropagation` and over `maximumWithNaNPropagation` | the kernel it reaches for |
| --- | --- | --- |
| `MPSDataTypeFloat32`, `MPSDataTypeFloat16` | **answers** | - |
| `MPSDataTypeInt8` | raises `NSInvalidArgumentException` | `isNaN_i8` |
| `MPSDataTypeInt16` | raises | `isNaN_i16_i8` |
| `MPSDataTypeInt32` | raises | `isNaN_i_i8` |
| `MPSDataTypeInt64` | raises | `isNaN_i64_i8` |
| `MPSDataTypeUInt8` | raises | `isNaN_u8_i8` |
| `MPSDataTypeUInt16` | raises | `isNaN_u16_i8` |
| `MPSDataTypeUInt32` | raises | `isNaN_u_i8` |
| `MPSDataTypeUInt64` | raises | `isNaN_u64_i8` |
| `MPSDataTypeBool` | raises | `isNaN_i8` |

Every refusal is `-[__NSDictionaryM setObject:forKey:]: object cannot be nil (key: ...)` from inside the
framework's own kernel table, raised before a single element is written, and the key names the type it
wanted: there is no NaN kernel for an integer type, and a boolean is an integer type to it. So the port's
rule - refuse every data type that is not `MPSDataTypeFloat32` or `MPSDataTypeFloat16` - is the measured set
and not a guess, and it is asked of both operations over all nine types in
`tests/backports/host/mpsgraph/graph-cases.m`, each case built and run inside an `@try` because that is where
the release raises: `raised-NSInvalidArgumentException` on both sides of all eighteen.

This is the second place in this family where the port is not the release's answer in form, and it is named
in the row of both methods.

**In float16 this pair keeps the sign of a zero where 14.0's does not.** Measured over the same sixteen
classes: `maximumWithNaNPropagation` answers `8000` for a maximum of -1.0 and -0.0 and `8000` for a maximum
of +0.0 and -inf, where 14.0's `maximum` answers `0000` for the same two pairs - and the port's float32
answer is -0.0 for both, so it is the half kernel and not the pair. The port's half rule ("a zero is a
positive zero in half", one rule for every kind of 14.0, measured over nine kinds) therefore does not apply to
an operation that latches, and the walk reads that out of the operation's own parameters like everything else.

### The two truth folds

| question | the release's answer | the port |
| --- | --- | --- |
| `reductionAndWithTensor:axis:1` over the sixteen classes | `00000000 0000803f` = (0, 1) | identical |
| `reductionOrWithTensor:axis:1` over the same | `0000803f 0000803f` = (1, 1) | identical |
| both over the int32 feed | `00000000 01000000` and `01000000 01000000` | identical |
| both over the float16 feed | `003c003c` for each | identical |
| both over a row of nothing but NaNs | `0000803f 0000803f` = (1, 1) | identical |
| both over `axes:nil` (every axis, a 1x1) | `00000000` for the "and", `0000803f` for the "or" | identical |
| both over `axes:@[]` (no axis, a 2x4) | the operand's own bytes, `0000803f 000080bf 00000080 000080ff ...` | identical |
| both over `axes:@[@1, @0]` (a set, a 1x1) | `0000803f` | identical |

So: the answer is written in the **operand's own type** and not in a boolean (measured in float32, float16,
int32 and uint8), the test is against zero, so both signed zeros are false and a NaN is a nonzero like any
other value (an "and" of a row of nothing but NaNs is 1), the answer is one and not a truth of another kind
(0x3f800000, 0x3c00, 1, 1), and the axes are the family's own (nil every axis, an empty array none, a
descending set still a set).

**A reduced set of no axes is the identity, and the truth folds are what measure it.** Over `axes:@[]` both
of them answer the operand byte for byte, where a seed of each fold's identity would answer 1 and 0
everywhere. The walk therefore answers a reduction over no axis with the operand itself, and the rule is in
the walk rather than in the two folds because a sum and a product of the identity are the identity either way:
only a fold whose answer is not the element's own can tell the two apart.

## The cumulative family of 16.0

Sixteen rows in one object (`MPSGraphCumulativeOps160.m`): `cumulativeSum`, `cumulativeProduct`,
`cumulativeMaximum` and `cumulativeMinimum`, each in four forms - an axis written down with and without the
`exclusive:` and `reverse:` flags, and an axis fed at run time with and without them.

**The walk is the reduction family's fold along an axis**, and it shares the fold table and the step with
it: `CharonMPSGraphFoldStep` is one function both walks call, so the seeds, the NaN rule and the four steps
are measured once. What the scan adds is a direction, an axis and a flag, all three read out of the
operation's parameters (`@scanCombination`, `@scanAxis`/`@scanAxisTensor`, `@scanExclusive`, `@scanReverse`),
so the 16.0 object names its sixteen methods and nothing of any other release.

### The rule, and what is measured

The accumulator is the result buffer and starts at the fold's seed, the walk goes along the axis in the
direction the flag says, and at each position the element joins the answer BEFORE that answer is written -
unless the answer is `exclusive`, which writes it first and folds the element in afterwards, so the position
the walk starts at holds the seed.

Over the case file's 2x4 of (1, 2, 3, 4 | 10, 20, 30, 40), axis 1, every one of these byte-identical between
the release and the port in float32, int32 and float16:

| operation | inclusive | reverse | exclusive reverse |
| --- | --- | --- | --- |
| `cumulativeSum` | (1, 3, 6, 10 \| 10, 30, 60, 100) | (10, 9, 7, 4 \| 100, 90, 70, 40) | (9, 7, 4, 0 \| 90, 70, 40, 0) |
| `cumulativeProduct` | (1, 2, 6, 24 \| 10, 200, 6000, 240000) | (24, 24, 12, 4 \| 240000, 24000, 1200, 40) | (24, 12, 4, 1 \| 24000, 1200, 40, 1) |
| `cumulativeMaximum` | (1, 2, 3, 4 \| 10, 20, 30, 40) | (4, 4, 4, 4 \| 40, 40, 40, 40) | (4, 4, 4, -inf \| 40, 40, 40, -inf) |
| `cumulativeMinimum` | (1, 1, 1, 1 \| 10, 10, 10, 10) | (1, 2, 3, 4 \| 10, 20, 30, 40) | (2, 3, 4, +inf \| 20, 30, 40, +inf) |

(the exclusive columns' seeds are the type's extreme finite value, which is the next table, and the reverse
minimum and maximum over an increasing row are each the row itself read from the other end).

**The seed of the two extremes is the type's own extreme FINITE value, not an infinity.** Measured over one
exclusive scan of each, in each of the three data types the family is asked in:

| type | the maximum's seed | the minimum's seed |
| --- | --- | --- |
| `MPSDataTypeFloat32` | `ff7fffff` = -FLT_MAX | `7f7fffff` = +FLT_MAX |
| `MPSDataTypeFloat16` | `fbff` = -65504, the largest finite half | `7bff` = +65504 |
| `MPSDataTypeInt32` | -2147483648 | 2147483647 |

which is the identity of a comparison over the values that type can hold. The reduction family of 14.0 seeds
an **infinity** instead - measured, `reductionMaximumWithTensor:axis:1` over a row of nothing but NaNs
answers `0xff800000` - and that is a different kernel with a different measurement, and it is left as it is.
A sum's seed is the zero of the type and a product's its one, in every type measured.

**A scan's comparison is not strict where a reduction's is**, and that is measured rather than guessed: over
the sixteen classes, whose first row is (1, -1, -0.0, +0.0), a *reverse* cumulative maximum answers a NEGATIVE
zero at positions 1 and 2 where a strict comparison keeps the zero it already held, and an exclusive reverse
maximum answers a negative zero at positions 0 and 1 where a strict comparison would take the positive one it
was handed. So `CharonMPSGraphFoldStep` takes both rules as arguments: the two reductions pass
"propagate a NaN, break a tie towards the held answer" and a scan passes "skip a NaN, break a tie towards the
new value", and the reduction family's own cases (a row of (0, -0, 0, -0) answers 0, the first of the equal
elements) are what pin its half of that.

**A NaN is skipped in a scan, as in a reduction**: over a row of (1, 2, 3, NaN) an exclusive reverse maximum
answers (3, 3, -FLT_MAX, -FLT_MAX) and an exclusive reverse minimum (2, 3, +FLT_MAX, +FLT_MAX), and over a row
of nothing but NaNs both answer the seed at every position. Nothing in this family latches a NaN - the two
propagating reductions of 14.0 are the only two that do, and they are in a different object.

**The other three questions the family asks.** A negative axis is counted from the end, measured (`axis:-1`
answers what `axis:1` answers). The result is the operand's own shape and data type, measured in all three
types - which is why this family needs no case helper of its own, unlike the reduction family whose result is
a different shape. And the accumulator is the result's own storage: measured, the cumulative sum of
(1, 2, 3, 4) in float16 is `4900` = 10, and the cumulative product of four halves of 65504 is an infinity from
the second step.

### The two refusals, both named in the row of every method

* **An axis outside the rank.** The release asserts and dies: `MPSGraphNDArrayScan.mm:253` writes
  `Axis = ... This class only supports axis = 0, 1, 2, 3` and takes the process with it. The port raises
  `NSInvalidArgumentException` - when the axis is written down, when the graph is built; when it is fed, when
  the graph runs, because then it is data and there is nothing earlier to refuse.
* **An axis fed as a floating point tensor.** The release cannot build the graph at all: its own compiler
  refuses the operand (`'mps.cumulative_sum' op operand #1 must be 0D tensor of mps index type values or
  static-shape defined tensor with shape equal to [1] ... but got 'tensor<1xf32>'`) and the process goes down
  with `failed assertion`, `MPSGraphExecutable.mm:4419`. The port raises `NSInvalidArgumentException` when the
  graph is built. An int32 and an int64 axis of shape [1] both answer, measured.

Neither is in the differential, and that is deliberate in both cases: the release's own answer is a process
that is gone, so there is nothing to compare a line against. Both are measurements in the rows instead.

### What is not measured here

The shape family (`reshape`, `squeeze`, `expandDims`, `transpose`, `slice`,
`concat`, `stack`, `split`, `pad`, `tile`, `reverse`, `broadcast`, `flatten2D`, `spaceToDepth`, `depthToSpace`,
`spaceToBatch`, `batchToSpace`, `coordinateAlongAxis`, `nonZeroIndices`, the `gather*` and `scatter*` forms
and the `topK`/`bottomK` pair) are not in this page and not in the tree: they are the rows the ledger still
carries as `missing`.

## The R4 names this band adds, in full

The SDK this package compiles against, the iPhoneOS 16.4 one, declares none of these: they are the
private surface the two families use to share their own state, and each is a registered implemented name or a
method of its object's own class rather than of a category - which is the one shape `carried_api` does not
read, so it is named here in the facts rather than only in the registry. The graph's are read out of the
graph's own compiled objects with `nm` (`MPSGraphBackports`, 13 objects), not from the sources, so a
declaration and a definition are not confused:

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
* `-[MPSGraph charon_mps_nanPropagatingExtreme:secondaryTensor:lesser:name:]` — MPSGraphReductionOps150.m, the one method 15.0's two NaN-propagating extremes share
* `-[MPSMatrixCopyDescriptor charon_mps_offsetsAtIndex]` — MPSMatrixCopy11.m, MPSMatrixCopyDescriptor11.m
* `-[MPSGraph charon_mps_operation]` — MPSGraph14.m
* `-[MPSGraph charon_mps_predicate]` — MPSGraph14.m
* `-[MPSGraph charon_mps_reduction:axes:tensor:parameters:name:]` — MPSGraph14.m, the seam every release's reduction factory goes through
* `-[MPSGraph charon_mps_reductionOf:tensor:combination:kind:propagatesNaN:name:]` — MPSGraph14.m
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

**The matrix and CNN entries are a snapshot of an earlier pass and are short of the tree**: measured against
the sources, `MPSPredicate16.m` carries `charon_mps_permitsExecution`, `MPSImagePyramid16.m` carries three
(`charon_mps_filter`, `charon_mps_filterWidth`, `charon_mps_filterHeight`) and `MPSNDArray13.m` carries four
(`charon_mps_wholeShapeOf:`, `charon_mps_makeBuffer`, `charon_mps_elementCount`, `charon_mps_bufferStrides:`),
and none of those eight is named above. The graph's nineteen are current, read out of the graph's own
compiled objects (`MPSGraphBackports`, 13 objects) rather than from the sources, so a declaration and a
definition are not confused; nothing in the graph family rests on the gap in the rest of the list, because
the registry check reads the built libraries and not this page - but the page is wrong about the tree until
the whole library's objects are read again, which is what the closing sentence describes.

The graph's are the interpreter's — its kinds, its per-operation wiring, its element accessors and the seams
its releases' factories share — and the matrix and CNN families' are the window, the fold, the state and the
copy descriptor's. None of them is called by an application. Each needs the lift's sets re-measured in the
same push as the ones that land with them, and the list is regenerated from the objects whenever the family
changes.

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
