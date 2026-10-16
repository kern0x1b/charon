# Spatial: a header-only C API, and what the port owes it

> **Superseded in part.** The section "Why the rows below are `inert`" and the plan to carry Apple's arithmetic
> byte-identically no longer hold: the port writes its own bodies for every function, never Apple's, and a function
> is `implemented` only with a host differential behind it. The header facts below still stand. Per-function facts
> live beside this file: `SPAngle.md` for the four iOS 16 angle functions, and the rest of the 647 rows are `owed`.

## The measurement that settles what this is

`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Spatial/Base.h:34`:

```c
#define SPATIAL_INLINE static inline
```

and `Base.h:29`:

```c
#define SPATIAL_OVERLOADABLE __attribute__((__overloadable__))
```

Every function of the API is declared `SPATIAL_INLINE SPATIAL_OVERLOADABLE` with
`__API_AVAILABLE(ios(16.0))` (the float families `ios(26.0)`) and **defined in the same header** -
`SPAffineTransform3DConcatenation` is declared at `SPAffineTransform3D.h:315` and defined at
`:879`. So:

- **no Apple binary exports any of them.** There is no `Spatial.framework` to link against: the
  26.2 SDK's `usr/lib/libSpatial.tbd` is an 8-line stub with an install name and no exports, and
  `usr/lib/swift/libswiftSpatial.tbl` is the same. `dlsym` finds none of the 640 names in either.
- **there is nothing for the port to export.** A caller of `SPVector3DMake` gets Apple's own
  inlined arithmetic compiled into its own object, which is what happens on a release that has
  Spatial. The port's job is to make the *headers* say the API is there at 6.1.3, not to provide a
  symbol.

## What the ledger got wrong, and what it says now

Two defects in `tools/corpus/api-ledger.py` put all 640 rows in `missing` with the reason "the port
has to export it". Both are fixed (`09c58e8f3`, `cdb925277`), both have a test and a mutation in
`tools/corpus/tests/test_corpus.py`, and the recount over the whole surface with identical inputs
moves exactly 640 rows and no others. `include_Spatial.tsv` now reads:

| status | needs | rows | what it says |
| --- | --- | --- | --- |
| `header-ok` | `lift` | 582 | declared in the port's headers, and a translation unit naming the row compiles for 6.1.3 - no code is needed once the generator's rule has lowered it |
| `undecided` | `decide` | 65 | the 65 `SPATIAL_OVERLOADABLE` names: a bare name does not identify one of several overloads, so the generated unit cannot name it and the tool says so |

The 65 are `AlmostEqualToTransform`, `Make`, `MakeTranslation`, `Translate`, `MakeWithVector`,
`MakeLookAt`, `Concatenation` and their float siblings - the names Apple overloads on a parameter's
type or arity. Naming one for real needs a call with arguments of the declared parameter types,
which is the next step and not this one. Every one of the 65 is still `static inline` in the header,
which is the fact these rows record.

## Why the rows below are `inert` and not `implemented`

The generator's rule (`tools/gen/target_availability.lua`) reads `implemented` and `inert` as carried:
both statuses lower a declaration's mark for the port's release. `inert` is a name the port carries with
nothing of its own to define, and Spatial is that case exactly: an inline in the package's own headers.
`check_registry` gates `implemented` rows against what the build carries and does not gate `inert` ones,
which is right: there is nothing to carry.

The rule lowers a declaration's availability for a name the registry says it carries, so these 647 rows
are what makes `needs=lift` actionable: without them the declarations keep `API_AVAILABLE(ios(16.0))`
and a Swift or `-Wunguarded-availability`-as-error build of a caller stops at the call.

## What is NOT measured here

- **No host differential has been taken, and none is available - measured, not assumed.** The oracle
  on this machine is `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/Spatial/`, and
  the proposal was to compile the same generated calls twice, once against those headers and once
  against the 26.2 iOS ones, and compare. That comparison cannot fail, because **the two header sets
  are the same bytes**: all 35 files of `usr/include/Spatial/` sha256 identically between the macOS
  CLT SDK and `iPhoneOS26.2.sdk`, 0 differ. A differential of a file against itself measures the
  reader, not the code, so it is not run and not reported as a pass.
  What there is **not** either is a `Spatial.framework` to `dlsym`: `ls /System/Library/Frameworks |
  grep -i spatial` returns only `SpatialPreview.framework`, `find / -maxdepth 6 -name
  Spatial.framework` returns nothing, and the CLT SDK's `System/Library/Frameworks` has no `Spatial`.
- **So what the 582 `header-ok` rows rest on, and it is a compile, not a number.** `header-ok` claims
  a translation unit naming the row compiles for the release and that no code is needed. The 640
  functions' arithmetic is Apple's own, carried byte-identically into the port, so there is no port
  arithmetic for a numeric oracle to check. What can be checked, and is, is that the headers parse and
  name at both bands - see the next bullet.
- **No link of a 640-function unit yet.** A generated TU naming all 640 with the ledger's own
  `naming_line` shape, at `-target armv7-apple-ios6.0` and `armv7-apple-ios4.3` against the 26.2 SDK,
  gives **19 errors on both targets** and 0 on the other 621 lines; all 19 are the
  `reference to overloaded function could not be resolved` above. So the headers themselves parse
  and name at both bands, and the 19 overloaded names are what stands between the current unit and a
  link.
