# VTPixelRotationSession: what the host's rotation is, and why the port cannot be told which one

Two things are recorded here: the measurement of what a pixel rotation *is* (four angles, two flips, ten
source shapes, two pixel formats, a forced stride - 320 cells, all of them agreeing with an expectation
computed from the source pattern alone), and the measurement of why a port rotation session cannot be given
a rotation at all on any release this port builds for.

The second is the important one, and it is not about this session: it is about every configurable
VideoToolbox session on this port's floor - pixel rotation, pixel transfer, frame silo, multi-pass.

## What the oracle holds

`tests/backports/host/videotoolbox-pixelrotation/` is the oracle. `probe.m` derives every cell's expected
pixels from the source pattern alone and checks that derivation against a **hand-written 180 per shape**
before the host is asked anything, so a wrong expectation cannot hide behind a matching host. Its own
source lists the four faults of this family's history that the ordering exists to prevent.

Run on this Mac (macOS 27.0), exit 0:

```
CELLS 320  DIFFERING 0  SET-REJECTED 0  PADDING-REFUSED 0  HANDCHECKS 10  HAND-DISAGREE 0  REFUSALS-UNEXPECTED 0
```

**A same-format rotation is a pure permutation of bytes.** Ten source shapes (2x4, 3x5, 1x4, 5x1, 1x1, 2x2,
4x3, and padded variants of five of them) x 32BGRA and 32ARGB x sixteen operations (four rotations crossed
with the two flips alone and together). All four channels of every pixel are compared, and so are the bytes
between the end of a row and the start of the next, against the fill written there.

The two formats that hold are **32BGRA and 32ARGB**. A padded `bytesPerRow` is forced through the public
mechanism - an `IOSurface` of the caller's own bytes per row wrapped by `CVPixelBufferCreateWithIOSurface` -
and asserted, because `CVPixelBufferCreate` ignores `kIOSurfaceBytesPerRow` when it allocates the surface
itself (measured: requested 28, got 64) and there is no public `CVPixelBufferAttributeKey` for a bytes per
row. Every padded shape came back at exactly the stride asked for: 24, 28, 16, 36, 20.

### What the host answers for what it does not take

| case | Apple's answer, measured 2026-10-03 |
| --- | --- |
| `Rotation` set to an `NSNumber(90)`, `FlipHorizontalOrientation` set to an `NSNumber(1)`, `Rotation` set to a `CFString` outside the four documented values | `kVTParameterErr` **(-12902)**, all three |
| a `OneComponent8` destination | `kVTPixelRotationNotSupportedErr` **(-12914)** |
| a `444YpCbCr8` destination | `kVTPixelRotationNotSupportedErr` **(-12914)** |
| a `420YpCbCr8` destination | `noErr` and a colour **conversion** (first row `171 171 171`, which is 50% in video range), not a rotation |
| a cross-format destination (BGRA source, ARGB destination) | `noErr` and a conversion: source pixel 12 as `B G R A 121 77 141 255` comes back as destination `A R G B 255 141 77 121` - an exact swap of red and blue, measured twice, once opaque and once with an alpha that varies |
| a destination geometry `VTPixelRotationSession.h:79` forbids - a quarter turn into 3x5 rather than 5x3 | `noErr` and **scale-to-fit with interpolation** (first row `111 60 9`, values that are in neither image) |

The last two rows are why there are **no biplanar YUV cells**: a 420 image's chroma planes are subsampled by
two on each axis, so rotating one is a second contract with its own arithmetic, and what the host does with
the format is convert it.

## The blocker: the release's VTSessionSetProperty refuses a session type the release does not have

`VTPixelRotationSession.h:101` says "See VTSession.h for property access APIs on VTPixelRotationSession",
so the only way to choose a rotation is `VTSessionSetProperty` with `kVTPixelRotationPropertyKey_Rotation`
(a `CFStringRef`, not a number - see fault 1 in `probe.m`). That function is **the release's**:

```
$ grep _VTSessionSetProperty coordination/corpus/caches/6.0.tsv
_VTSessionSetProperty	VideoToolbox
$ grep -n '_VTSessionSetProperty' <the 6.1.3 armv7 symbol dump>
115951:_VTSessionSetProperty	VideoToolbox
```

and it dispatches on the session's `CFTypeID` against its own table. Measured on this host, with
`kVTPixelRotationPropertyKey_Rotation` and `kVTRotation_180`:

```
CFStringRef            typeID=7      SetProperty=-12902   CopyProperty=-12902
NSMutableDictionary    typeID=18     SetProperty=-12902   CopyProperty=-12902
NSMutableData          typeID=20     SetProperty=-12902   CopyProperty=-12902
CFDictionaryRef        typeID=18     SetProperty=-12902   CopyProperty=-12902
NULL                   typeID=0      SetProperty=-12902   CopyProperty=-12902
rotation session       typeID=75     SetProperty=0
```

Everything that is not one of Apple's own sessions is refused with `kVTParameterErr`. **A session object the
port creates has a type ID the release's table does not have, so every set is refused and the session stays
at the header's default, `kVTRotation_0`.**

The port cannot replace the function either, and this is mechanical rather than a matter of taste.
`modules/apple/backports.lua`'s `band()` (line 787) puts an object into one of three answers:

- every exported symbol already exported by the band' release: the object is **dropped** and its symbols go
  into `-reexported_symbols_list` - the release's own implementations are re-exported instead;
- some but not all: `raise("... defines ... which the release already exports, together with ... which it
  does not; an object carries API that arrived in one release, so split it")`;
- none: the object is kept.

`_VTSessionSetProperty` is exported by every band the port builds - measured in the 6.1.3 armv7 dump, in
`caches/6.0.tsv`, and in the 4.3 armv7 cache read with `tools/corpus/dump-cache.lua` - so a port object
defining only that is dropped from every band and a port object defining it together with the four rotation
functions raises. And `attach.c` interposes Objective-C classes and categories only - it has no C-symbol
interposition. So there is no mechanism by which the port's own `VTSessionSetProperty` would ever be the one
an application calls.

**Consequence: on this port's releases a pixel rotation session can only ever rotate by 0 degrees with no
flip**, whatever the four functions themselves do.

## The vImage the rotation would ride on, measured per band

The 6.1.3 armv7 dump carries the four entry points a 32-bit packed rotation needs, twice each (a `vImage` and
an `Accelerate` attribution): `_vImageRotate90_ARGB8888`, `_vImageHorizontalReflect_ARGB8888`,
`_vImageVerticalReflect_ARGB8888`, `_vImagePermuteChannels_ARGB8888`. **The 4.3 cache carries no `vImage`
symbol at all** - its Accelerate exports 401 names and every one is a vDSP. So at 4.3 the geometry has to
come from the port's own Accelerate, and what the port carries there is narrower than the order assumed:

- `vImageRotate90_ARGB16U` and `vImageRotate90_ARGB16S` at 7.0 (`vImageGeometry7.m`), and the three
  half-precision shapes at 15.0 (`vImageGeometry15.m`);
- the mapping and the loop are `Accelerate/CharonGeometry.h`'s `charon_turn` and `charon_turn_run`, a byte
  mover parameterised by bytes per sample, measured over eight destination shapes both ways, which is the
  shape a 32-bit packed format needs;
- **no `vImageRotate90_ARGB8888`, no `vImageRotate180_*` and no `vImageHorizontalReflect_*` or
  `vImageVerticalReflect_*` for any pixel type**: `grep` over `registry/Accelerate/*.json` returns zero rows
  naming them. The two flips, which the header applies after the rotation, have no vImage entry point in
  this tree at all.

## What that means for the four rows, and the open question

The four rows - `VTPixelRotationSessionCreate`, `...GetTypeID`, `...Invalidate`, `...RotateImage` - are
implementable: the session object, its type ID, its invalidation and the rotation loop over the release's
vImage (`_vImageRotate90_ARGB8888`, `_vImageHorizontalReflect_ARGB8888`, `_vImageVerticalReflect_ARGB8888`
and `_vImagePermuteChannels_ARGB8888` are all in the 6.1.3 armv7 dump, so nothing has to be invented) are
all native. What cannot be delivered on the port's bands is the **choice** of angle and flip, because the
only route to it is a function the release owns and refuses to answer for this session type.

Three answers are possible and which one the ledger records is a ruling, not a measurement:

1. the four rows `implemented`, `RotateImage` doing the real rotation for the one configuration the session
   can be in, and every registry row saying in as many words that the angle and the flips cannot be selected
   on any band floor because `VTSessionSetProperty` refuses the port's session type;
2. the four rows left `missing` with this cause, which costs the port a rotation session it could mostly
   have;
3. the port carries the property table on an object of its own and the caller reaches it through a seam -
   which is a value nothing reads, and the coordinator has already rejected that shape twice in this wave
   (`NSURLSessionConfiguration.proxyConfigurations`, `MPSeekCommandEvent`'s host check).

Nothing here is a crutch, and nothing has been landed: the measurement is the deliverable, and the loop over
vImage is not written until the shape of the API is settled.

## Source

- `tests/backports/host/videotoolbox-pixelrotation/` - the oracle, its four plants and the refusal section.
- `coordination/corpus/caches/6.0.tsv`, the 6.1.3 armv7 symbol dump, and `tools/corpus/dump-cache.lua` over
  `~/.charon/dyld/4.3/dyld_shared_cache_armv7` (read-only) - `_VTSessionSetProperty` and
  `_VTSessionCopyProperty` in all three, the four `_vImage*_ARGB8888` entry points in 6.1.3 and no
  `vImage` symbol in 4.3.
- `modules/apple/backports.lua` `band()` - what happens to a port object that defines a symbol the release
  already exports.
- SDK 26.2 `VTPixelRotationSession.h:79` and `VTPixelRotationProperties.h:38-65`.