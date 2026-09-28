# `MLMultiArrayDataType`, and why one enumeration of CoreML is carried

`MLMultiArrayDataType` is the only piece of CoreML this package carries, and it is carried because
CreateML cannot be written without it: `LinearRegressor<Scalar>`, `MultivariateLinearRegressor<Scalar>`,
`LogisticRegressionClassifier<Scalar, Label>`, `LinearRegressorModel<Scalar>` and the metrics are all
constrained to `Scalar : MLShapedArrayScalar`, and that protocol's one requirement is

    public protocol MLShapedArrayScalar {
        static var multiArrayDataType: CoreML.MLMultiArrayDataType { get }
    }

so the whole linear and logistic family of CreateMLComponents is behind this enumeration.

## What is being carried, and what is not

The enumeration and its cases. `MLMultiArray.h:17` declares it

    typedef NS_ENUM(NSInteger, MLMultiArrayDataType) { ... } API_AVAILABLE(..., ios(11.0), ...)

which is header-only: no class, no method, nothing to build, no symbol to export. There is no
`MLMultiArray` — the class that gives the enumeration its name and its only use is **absent**, in
`registry/CoreML/absent_CoreML.json`, and stays absent. The registry check weighs what the package
*exports* against what it says is implemented, and an enumeration exports nothing, which is why the
ledger's own status for these rows is `header-ok` and why there is nothing to build for them.

So the carry is a *lift*, not a library: the port's release has no CoreML at all, the SDK marks the
header `ios(11.0)`, and Swift refuses a reference below the deployment target.

**What the registry file is for, precisely, is giving the lift a *name* to lower.** `lift.lua` lowers
the availability of what the registry records as `implemented`; with no row for
`MLMultiArrayDataType` the enumeration keeps the SDK's `ios(11.0)` and the port's `CoreML` module
cannot see the type at all. That is the whole job.

It does **not** bring CoreML into the set of frameworks the lift walks, and an earlier version of this
file said that it did. It does not, and the review is right about why: `registry/CoreML/absent_CoreML.json`
(43 entries) is already in main at the base `68befaca`, so `lift.lua:1187`'s `local frameworks = registered`
already contained CoreML before this series. A reader who believed the old text would look for the
wrong thing the day the lift changes, which is the whole cost of a wrong sentence in a facts file.

## The values, read rather than assumed

From `MLMultiArray.h` of the iPhoneOS 16.4 SDK:

| Case | Value |
| --- | --- |
| `MLMultiArrayDataTypeDouble` | `0x10000 \| 64` |
| `MLMultiArrayDataTypeFloat64` | `0x10000 \| 64` |
| `MLMultiArrayDataTypeFloat32` | `0x10000 \| 32` |
| `MLMultiArrayDataTypeFloat16` | `0x10000 \| 16` |
| `MLMultiArrayDataTypeFloat` | `0x10000 \| 32` |
| `MLMultiArrayDataTypeInt32` | `0x20000 \| 32` |

The pairs are the same value under two names, which is what the release did: `Double`/`Float64` and
`Float32`/`Float` are the same width, and the older name is the one the first release used.

## Why it is honest to carry this much

The alternative — defining the enumeration in the port's own Swift overlay — would be a second copy
of a type CoreML declares, which the port's rules forbid, and it would leave the port answering a
`MLMultiArrayDataType` that is not CoreML's. With the registry entry, the overlay *imports* CoreML's
enumeration and names it; nothing is re-declared.

The test that this is the right carry is that it is the *minimum*: the `MLShapedArray` overlay needs
the enumeration and the enumeration needs no code, and every other CoreML type the overlay would want
— `MLModel`, `MLMultiArray` itself, `MLFeatureValue` — is a class with methods, which is the
CoreML package's work and is not begun here.

## What this module is over, and what it is not waiting for

The overlay is a module **named `CoreML`**, in `packages/c/createml/files/CoreML/`, and it sits over
`0b610213`'s Objective-C CoreML: the one declaration it needs from it is `MLMultiArrayDataType`, which
is header-only, and the class that gives the family its name — `MLMultiArray` — is theirs and is not
touched here.

**It needs no symbol from their library, and that is why it builds now.** The overlay's
`MLShapedArrayScalar` returns an enumeration *value*; returning it links nothing. So the module
compiles and links before their package is merged and compiles and links unchanged after, and
`packages/c/createml/xmake.lua` does **not** declare a dependency on `charon@apple-backports`'s
`coreml` config — declaring one against a config that does not exist in main yet would make this
package unresolvable, which is waiting by the back door.

What their merge *does* change is nothing here and one thing in the registry: their `coreml` config
brings `libCoreMLBackports.dylib` and the `MLMultiArray` class, and the rows this series marks
`absent` stay `absent` until their own registry entries land. The two series touch
`registry/CoreML/` and nothing else, and the coordinator has told them this file's names so neither
writes them twice.

## What a caller can and cannot do with it

A caller can name a scalar type's `multiArrayDataType` and can build an `MLShapedArray` of that scalar
— the shape, the strides and the values are the port's own, and the arithmetic behind them is the
device's own BLAS. A caller cannot construct an `MLMultiArray` from one, and cannot hand a model to
Core ML: those are the absent class and its absent methods, and `respondsToSelector:` and
`NSClassFromString` say so. The `.mlmodel` export of a trained model refuses for the same reason, from
the other end: the specification writer is the CoreML package's and is not begun.
