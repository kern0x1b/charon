# The shaped-array overlay: `MLShapedArray` and the frame it sits in

CoreML on this port's releases is **absent** — there is no CoreML at all below iOS 11, and
`registry/CoreML/absent_CoreML.json` says so for the framework. What this port carries is a Swift
overlay named after it, and this file is what the five rows for that overlay are measured against:
`MLShapedArray`, `MLShapedArraySlice`, `MLShapedArrayScalar`, `MLShapedArray.strides` and
`MLShapedArray.withUnsafeShapedBufferPointer`.

The measurements are in `tests/backports/host/createml/tabularframe.swift`, which builds the same
frame twice — once with the port's overlay and once with Apple's own on the host — and compares
shape, contents, selection and slicing. **86 checks, 0 failures.**

## The shape is a shape, not a buffer

`the shape's rows`, `the shape's columns`, `the row count` and
`the column names, in the order they were added`. The last is the one that earns its keep: a frame
whose columns come back in insertion order is a frame a caller can index by position, and one whose
columns come back in hash order is a frame where `frame.columns[0]` means something different on two
consecutive calls.

`a frame whose columns agree on a height is valid` and `a frame is not empty` are the two halves of
the frame's own invariant: columns of different heights cannot be one frame, and a frame with no
columns is not a frame. Both are checked against the host rather than asserted, because the host is
where the answer for an empty frame is known rather than assumed.

## A column read as the wrong type is nil, not a conversion

`a typed column by ColumnID`, `a typed column by name and type`, `a category column by ColumnID`, and
then the three that pin the failure modes: `a column read as the wrong type is nil`,
`containsColumn with the wrong type is false`, `containsColumn with its own type is true`. A port
that converted an `Int` column to `Double` on request would answer every one of these with a value
and be wrong every time: the numbers would be indistinguishable and the **types** would not, which is
the entire reason `TabularData` distinguishes them.

`a column that is not there is nil`, `the position of a column that is not there is nil`,
`the dynamic member lookup of a column that is not there has no value` and
`the dynamic member lookup of a column that is there is the column` — the last two together are what
`@dynamicMemberLookup` is for, and the negative case is the one that would otherwise crash: a dynamic
lookup on a name that is not a column must answer nothing rather than trap.

## Rows, selection, and slices that write through

`a row's count`, `a row by name`, `a row by ColumnID`, `a row by name and type`,
`a row out of range answers nil`, and `a row as a column of one row per column` — a row read as a
column is the bridge from the frame to the estimator, and a row out of range must answer nothing
rather than read past the end.

Selection is checked in every shape it takes: `selecting one column`, `selecting two columns, in the
order named`, `dropping a column`, and the four filters — on the row, on a column by name, on a
`ColumnID`, on a category, plus `a filter that keeps everything` and `a filter that keeps nothing`,
which are the two degenerate cases a filter gets wrong.

Slicing is checked for both the count and the values, and for the property that matters most:
`a slice's own frame, copied out`, `a slice's column names`, and
`a discontiguous slice's count`. **A slice of a frame must be a copy, and a subscript write through
a slice must reach the original** — a slice that held the parent's storage would make every write
through it an aliasing bug, and `a discontiguous slice's count` is the check that a slice over rows
that are not adjacent is still a frame with a row count.

That last property cost a repair: the slice was first made read-only to avoid the aliasing, which is
a workaround that removes the capability, and the repair was to make the subscript write *through* to
the parent. A read-only slice is a smaller API that answers a different question from the one a
caller asks when they subscript a slice.

## What this overlay is over, and what it is constrained to

The overlay declares **no dependency on CoreML**, and it is named after the framework. The reason is
in `packages/c/createml/xmake.lua`: the module is called `CoreML` and so is the SDK's CoreML as a
clang module, two modules cannot share a name, and the Swift one wins — so the module is given a
header of its own that includes the framework's, and built with `-import-objc-header`. That is the
same route `charon@swift-runtime` takes for `Foundation`, `UIKit` and `CoreData`, and it is why
`MLShapedArrayScalar`'s one requirement can be written as `CoreML.MLMultiArrayDataType` and mean the
framework's own type rather than a copy.

**The enumeration that requirement names is `absent` on these releases**, and its own measurements —
what is being carried, why a header-only `NS_ENUM` with an `ios(11.0)` annotation cannot reach a
release that never had it, and the measurement that lifting it to `ios(6.1.3)` makes the linear
family compile at ios 7.0 through 10.0 — are in
**[MLMultiArrayDataType.md](MLMultiArrayDataType.md)**.
