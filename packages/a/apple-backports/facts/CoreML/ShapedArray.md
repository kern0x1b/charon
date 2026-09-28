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

## What Apple's own `AnyColumn` answers, measured against Apple's own

The port's `AnyColumn` is a box over a typed column, and the box's accessors are compared with
Apple's. The comparison is only worth anything once it is established that the host side is Apple and
not a construction mistake, so the control is Apple's own module with nothing of the port's in it:

    let c = TabularData.Column<Int?>(name: "a", contents: [1, nil, 3])
    print(c.missingCount, c.wrappedElementType)
    var f = TabularData.DataFrame(); f.append(column: c)
    print(f["a"].missingCount, f["a"].wrappedElementType, f["a"].count)

    pure column   missingCount=0 wrapped=Optional<Int>
    after append  missingCount=0 wrapped=Optional<Int> count=3

**`count` is 3 on both sides, so nothing is dropped on `append`, and Apple's `missingCount` is 0 for
the nil in the column.** `wrappedElementType` is `Optional<Int>`: **Apple does not unwrap.**

Three things follow for the port, all in the same direction — the host is the oracle:

| accessor | Apple | the port must |
| --- | --- | --- |
| `wrappedElementType` of `Column<Int?>` | `Optional<Int>` | `Optional<Int>`, not the unwrapped `Int` |
| `missingCount` of `[1, nil, 3]` | 0 | 0 |
| position subscript | describes as `Optional("berlin")` for a column of plain `String` | `subscript(position:) -> Any?` |

The third is the one that looks like a bug in Apple and is not: the host's subscript returns `Any?`,
and `String(describing:)` of an `Any?` that holds a value describes as `Optional(value)`. The port's
returned `Any`, which describes as the bare value, is the divergence.

### Why `missingCount` of 0 is not strange, and the two forms Apple keeps apart

`Column<Int?>` has `WrappedElement == Int?`, so its `contents:` is `[Int??]` and a `nil` written in a
literal goes in as `.some(nil)` — a **value** to Apple, not a missing one. The ordinary form has
`WrappedElement == Int`, so the same literal is a genuine missing value. Both measured, on Apple's own
module:

    let a = Column<Int?>(name: "a", contents: [1, nil, 3])
    let b = Column<Int>(name: "a", contents: [1, nil, 3])

    optional-form  missing=0 wrapped=Optional<Int> count=3
    ordinary-form  missing=1 wrapped=Int count=3

**Apple keeps the two forms apart, and the port's unwrapping collapses them into one.** The port
answers `Int` and `missingCount` 1 for *both*, because `_withoutOptionalLayer` strips the optional
before the storage line sees it and `_wrappedType(of:)` strips it for the reported type. So the
optional form, where Apple says "three values, none missing, of type `Optional<Int>`", becomes in the
port "three values, one missing, of type `Int`" — a different column by Apple's own definition of the
difference.

That is the whole of the divergence, and it is why removing the unwrapping is the fix rather than a
change of detail. The two cases that pin it are one per form: an optional-form column reporting
`Optional<Int>` and a `missingCount` of 0, and an ordinary-form column reporting `Int` and 1. The port
must match both, and a single test of one form cannot tell a port that keeps them apart from one that
has merged them.

**`isNil(at:)` has no direct oracle.** It is `internal` in the SDK, so a program outside the module
cannot call it and the control above cannot reach it. The port's `isNil(at:)` is therefore only
comparable through the host differential, which is weaker evidence than a control on pure Apple, and
that is worth saying before the port's answer there is changed.
