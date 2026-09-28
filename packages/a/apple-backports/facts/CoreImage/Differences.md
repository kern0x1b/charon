# What the two differentials still disagree about

Measured 2026-09-28 on the rebased tree (`ciimage: 559 measurements, 534 the same, 17 different, 42 one
side only`; `modelio: 317 measurements, 300 the same, 5 different, 55 one side only`), at a tolerance of
5e-4 on both. The causes are below, grouped, and each says which side is ours to fix.

## CoreImage, the 17 different

| group | n | what the two sides say | whose |
| --- | --- | --- | --- |
| the clamped family | 6 | `alg clamped extent/rect` print an extent of +/-1.8e308 on the port and the box of the crop on the host. `CharonCIClamp` hands the framework's own nested ask - the one `-[CIAffineClamp outputImage]` makes while the filter is producing its output - an image that is not yet clamped, and the framework's answer for a half-built image is an unbounded one. The *pixels* of `alg clamped extent` agree (`6821f505`); only the extent is wrong. | ours: the clamp has to hand back a clamped image for the nested ask, not the input |
| the context's working format | 2 | `ctx space nil/srgb working format 2056` against the port's `kCIFormatRGBA8`. A context made with a colour space and no format is not an 8-bit RGBA working format on the host; the port answers its own default. | ours: the default is the release's, and it is not the port's |
| the shapes under a transform | 7 | `shape turned`, `shape turned interior` and their cropped pixels: the host's bounds of a rotated rectangle and the port's differ by a pixel. `CGRectApplyAffineTransform` bounds the four corners; the host appears to bound the edges. | ours, or a documented divergence: it is one pixel on a rotated bound |
| the representations, one-sided | 36 | `repr rgba8/l8/rgbaf` PNG, TIFF and JPEG, and `repr jpeg`, are on the host and on neither side on the port, and `repr write png` is 0 where the host's is 1. `charon_representationOfImage:` is returning nil. | ours |
| the clamped family, one-sided | 4 | the per-pixel lines of `alg clamped rect`, which the port has fewer of because its clamped image has a different extent. | follows from the first row |

## CoreImage, the round trip: a defect of ours, found and not fixed

`unpre round trip` is `6821f505` on the host and `3c04ef85` in the port. `6821f505` is the source
checksum, so on the host a premultiply followed by an unpremultiply is **the identity**. In the port it
is not, and the reason is the kind of unpremultiply the port has: the release's is **lazy** and
composes, and the port's is an **eager** render into bytes, so the second pass quantises what the first
already quantised. Composing an unpremultiply needs a filter that divides by alpha, which the release
does not have, so the port cannot be lazy here. This is the one place in the two rows where the port is
measurably wrong, and it belongs in `crutches.md` as a named eager-render crutch rather than in a
facts file as a difference.

## ModelIO, the 5 different

| group | n | what the two sides say | whose |
| --- | --- | --- | --- |
| the generator tessellation | 2 | the ellipsoid's 72 vertices against 63 and the cylinder's 47 against 29. The index counts agree, so the surface is the same and the two share vertices differently. | a documented divergence: the header does not say where Apple shares |
| the descriptor of a mesh built from buffers | 1 | 31 attributes on the system, the one given in the port. | Apple's own internal attributes; a port cannot read them |
| the voxel index extent | 1 | the system answers `INT_MAX` for small arrays and zero for larger, the same on every run; the port derives the extent from the box and the voxel size. | a named divergence, the system's answer carrying no information about the division |
| the union over such an array | 1 | follows from the extent: two voxels in the port, three on the system. | follows |

## ModelIO, the 55 one-sided

96 of the original 111 were the per-vertex lines of a mesh the two sides built with a different number
of vertices, and they follow from the tessellation row. The rest are the OBJ submesh naming and index
range (the system names a submesh `solid_red` where the port names the two `red` and `lid`), the mesh
and material names an asset takes from its file (the system takes `tri` and `tribin` and `PLY
Material`; the port takes none of them), the `specular` property's type (a float on the system in the
physically plausible function, a colour in the older one in the port), and the clamped-family
equivalents above. **None of them is a port feature the system lacks.**

## Why the mutations did not go red: the two files were not in the probe's build

**Correction.** This section first said the three rows were *shadowed on the host* - that the macOS
framework carries those selectors, so a category answering them loses, and the two processes measured
the framework against itself. That was wrong. The two files were **copied into the probe's port build
and never compiled**: `run.sh`'s `piece` list named `CIImageProperties` and `CIImageUnpremultiply` for
the `cp` and not for the compile, so the port's probe had no `charon_CIImage_*` symbols at all. The
`dladdr` I took as proof of shadowing was proof that the object was missing.

With the two pieces in the list, `dladdr` names the **probe's own image** for all three:

    imp properties                    0x100991a44 probe
    imp imageByUnpremultiplyingAlpha   0x10099207c probe
    imp imageByClampingToExtent       0x10098fea4 probe

and the installer's own stderr says what it decided, which was the open question from that `dladdr`:

    charon: replaced -[properties]
    charon: replaced -[imageBySettingProperties:]
    charon: replaced -[CIImage imageByUnpremultiplyingAlpha]

So the `+load` runs and does replace, and the probe calls the port's own exported functions directly.
The category was never shadowed and the `+load` was never broken.

**And the port's probe then crashes** - and the crash is a stack overflow, measured:

    breakpoint set -n charon_CIImage_properties -i 500, then run
    stop reason: breakpoint 1.1
    frame #0: probe`charon_CIImage_properties
    hit count = 501

`EXC_BAD_ACCESS (code=2)` at `0x16f603fe0` is the main thread's **guard page** just below its stack,
which is what a stack overflow faults on; `bt` shows only frame #0 because the stack is gone, so the
recursion is invisible to an unwind. The breakpoint count is what shows it, and it is 501 and counting.

**The mechanism, and it is not the one I first guessed.** The installer captures the release's `-properties`
IMP with

    Method method = class_getInstanceMethod([CIImage class], @selector(properties));
    CharonCIPropertiesRelease = method_getImplementation(method);

but **the runtime attaches a file's categories before it runs that file's `+load`**, so
`class_getInstanceMethod` returns this same file's own `-[CIImage properties]`, not the framework's. The
captured "release IMP" is therefore the category's method, which calls `charon_CIImage_properties`, which
calls the captured IMP - a two-frame cycle, and the stack goes.

The guard that would have caught it is not `captured != replacement`, which is true here and passes:
the captured is the *category's* method, a third thing. It is **"the captured IMP is not in this image"**,
which is what `dladdr` is for, asserted at install.

The rows are therefore not measured yet, the mutations have not been re-run, and the `ciimage` count
still carries measurements the probe does not make.

## The two mutations did not go red, and that is not a proof

Flipping one line in each of the two new files - `imageBySettingProperties:` returning the image it was
called on, and the unpremultiply dropping its clamp - left the verdict at exactly `559/534/17/42`, with
`props distinct 1` and `unpre finite 96 07488805` unchanged on both sides. The probe is reading the rows
(lines present in both answers files, and the values agree with the host), so the mutations either did
not reach the built sources or the rows are insensitive to them. I could not determine which in this
pass, and I am not claiming either row is proved: this is the same failure mode as the first
"four mutations still gave 252/252", where the port process was the host. **The next thing to do is to
find out which, before either row is claimed as held.**

## The 4.3 lower bound, measured: CoreImage arrives in 5.0

`tools/cicontext-bounds.lua`, with `apple.dyld` and no raw search over the cache bytes:

    4.3     the CoreImage image: NOT in the cache
    4.3.5   the CoreImage image: NOT in the cache
    5.0     the CoreImage image: in the cache

So **iOS 4.3 has no CoreImage at all**, and my earlier guess that "4.3 has CIContext" was wrong twice
over. The placement follows from that: the two new files reference `CIContext` and `CIImage`, whose
lower bound is 5.0, so they must sit at 5.0 or later and must not be built for 4.3. The 4.3 gate's
failure is not "the release has the class and the port's copy is dropped" - at 4.3 the port's copy is
*kept* - it is that the band does not link CoreImage because the files that make it are placed at 10.0
and 11.0 and never enter the 4.3 band at all.

The `image.exports` accessor inside `apple.dyld` did not resolve from an `open_cache` image entry, so
this establishes the **image's presence** and not which of the two releases first exports the four
classes from it. The presence is what the placement needs.

## The 4.3 gate, and what it means for the two new files

`4.3` fails on two symbols, and the reason is the release's:

```
Undefined symbols for architecture armv7:
  "_OBJC_CLASS_$_CIContext", referenced from:
      objc-class-ref in CIImageUnpremultiply11.o
  "_OBJC_CLASS_$_CIImage", referenced from: ...
```

iOS 4.3 **has** CIImage and CIContext. So at that band the release supplies the classes, the port's own
`CIImage+FilterParameters.m` is dropped as carrying API the release has, and the two new files - which
define only selectors the release lacks, so they are kept - are left referencing classes no port object
defines. That is the "a file whose exports a band's release already has is left out of that band" trap
arriving through the class rather than through a C function, and it is why neither new file may name a
class without the band carrying it. Not fixed; the next step is to see which of the port's files is
dropped at 4.3 and to decide between keeping the arithmetic in a file the band keeps and having the
class come from the release.

## The count, and what it now measures

    ciimage: 564 measurements, 532 the same, 19 different, 52 one side only (tolerance 5e-4)

The three CoreImage rows that were in that count and were **not measurements of the port** are out of
it, and the two that are in it are now the port's own code, because the probe calls
`charon_CIImage_properties`, `charon_CIImage_imageBySettingProperties` and
`charon_CIImage_imageByUnpremultiplyingAlpha` directly and `dladdr` names the probe's image for all
three. Both are registered as **crutches**, with the measurement, in `registry/CoreImage/ctxowner9.json`
and `coordination/crutches.md`:

- `-imageBySettingProperties:` — the values read back correctly (`props count 1`, `props value one` on
  both sides) and the identity cannot match: `props distinct 0` in the port against `1` on the system.
- `-imageByUnpremultiplyingAlpha` — `unpre finite pixel 1` is `255 153 255 128` on the system and
  `255 151 255 128` in the port, and `unpre round trip` is `487584e5` (which **is** the source
  checksum, so the system's is exactly the identity) against `fd3b7745`.

### UNMEASURED: the four "0 distinct" alternatives were measured on the host, not on the release

The finding that no public construction makes a distinct image with the same extent - `-copy`, an
identity affine transform, an identity colour matrix and a crop to the image's own extent all returning
the same object, and a clamp returning a distinct one only by making the extent infinite - was
**measured against the macOS 26 host's CoreImage**. The port runs against the **release's** CoreImage.
CoreImage arrives with iOS 5.0 (measured against the armv7 caches: the image is absent from 4.3 and
4.3.5, present in 5.0), so on iOS 6.1.3 the question is whether `-copy` or an identity transform
returns a distinct image there. **That is unmeasured, and it is a device or emulator question.** If the
release's copy is distinct, the port's row is right and the identity matches with no change; if it is
not, the crutch stands. Nothing here should be read as a claim about the release.
