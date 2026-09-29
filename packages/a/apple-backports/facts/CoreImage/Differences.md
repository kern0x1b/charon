# What the two differentials still disagree about

Measured 2026-09-28 on the rebased tree (`ciimage: 559 measurements, 534 the same, 17 different, 42 one
side only`; `modelio: 317 measurements, 300 the same, 5 different, 55 one side only`), at a tolerance of
5e-4 on both. The causes are below, grouped, and each says which side is ours to fix. **The CoreImage
count has moved since**: two rows came out and their measurements went with them, and this tree's own
run is `ciimage: 551 measurements, 525 the same, 17 different, 44 one side only` — see "The count, and
what it measures now that two rows came out" at the end, which also carries the control that shows the
comparator can fail. The 17 are the same 17.

## CoreImage, the 17 the first-number view found

**This table is the first-number view and it undercounts.** `compare.py` read only the number behind the key, so a line was the same whatever followed it, and the count it gave was 17. The count of what is actually different is 77 and it is grouped at the end of this file. One row of this table is corrected in place where the whole-tail comparison refutes it; the others are left as they were written, because they are the record of what was seen then and not a claim about the tree now.

| group | n | what the two sides say | whose |
| --- | --- | --- | --- |
| the clamped family | 6 | `alg clamped extent/rect` print an extent of +/-1.8e308 on the port and the box of the crop on the host. `CharonCIClamp` hands the framework's own nested ask - the one `-[CIAffineClamp outputImage]` makes while the filter is producing its output - an image that is not yet clamped, and the framework's answer for a half-built image is an unbounded one. The *pixels* do not agree either, and the old comparator said they did because it read only the length: the host renders 96 bytes with checksum `6821f505` and the port 24 with `63fe7f63`, and the port's own four pixels are `153 76 229 80`, `153 76 229 30` and so on against the host's uniform `153 77 229 128`. | ours: the clamp has to hand back a clamped image for the nested ask, not the input |
| the context's working format | 2 | `ctx space nil/srgb working format 2056` against the port's `kCIFormatRGBA8`. A context made with a colour space and no format is not an 8-bit RGBA working format on the host; the port answers its own default. | ours: the default is the release's, and it is not the port's |
| the shapes under a transform | 7 | `shape turned`, `shape turned interior` and their cropped pixels: the host's bounds of a rotated rectangle and the port's differ by a pixel. `CGRectApplyAffineTransform` bounds the four corners; the host appears to bound the edges. | ours, or a documented divergence: it is one pixel on a rotated bound |
| the representations, one-sided | 36 | `repr rgba8/l8/rgbaf` PNG, TIFF and JPEG, and `repr jpeg`, are on the host and on neither side on the port, and `repr write png` is 0 where the host's is 1. `charon_representationOfImage:` is returning nil. | ours |
| the clamped family, one-sided | 4 | the per-pixel lines of `alg clamped rect`, which the port has fewer of because its clamped image has a different extent. | follows from the first row |

## CoreImage, the round trip: both halves of it are `absent` now

This section first said `unpre round trip` was `6821f505` on the host and `3c04ef85` in the port, and
read the difference as the unpremultiply's: "the release's is lazy and composes, and the port's is an
eager render into bytes". Two things were wrong with that, and the whole-tail comparison is what
showed them.

The line never measured the unpremultiply. Its source was
`put_bytes(@"unpre round trip", render([[finite imageByPremultiplyingAlpha] imageByCroppingToRect:bounds]));`,
which asks `-[CIImage imageByPremultiplyingAlpha]` and nothing else - so the divergence belonged to the
premultiply row, not to either of the two rows this file's neighbours were about.

And the two rows themselves are both `absent` now, and neither is a crutch in `crutches.md`:

  - `-[CIImage imageByPremultiplyingAlpha]` is `absent` in `registry/CoreImage/algebra10.json`. The
    port's implementation was a colour matrix whose vectors took the alpha into red, green and blue,
    which is a grey image of the alpha, not a premultiplied one: measured, the system renders
    `96 487584e5` with pixel 0 `77 38 115 128` and the port rendered `96 fd3b7745` with pixel 0
    `128 128 128 128`. A colour matrix is linear over the four channels it is given, so no filter of
    the release scales a channel by the alpha of the same pixel, and the release carries neither
    premultiply filter. `facts/CoreImage/ImageAlgebra.md` carries the measurement.

  - `-[CIImage imageByUnpremultiplyingAlpha]` and `-[CIImage imageBySettingProperties:]` were taken
    out one commit earlier, for the reasons in `facts/CoreImage/ContextOwner.md`.

The probe does not ask any of the three, and `reportPremultiply` is gone with them. The diff on this
page is what remains, and every number in it is a measurement of the port.

## ModelIO, the 5 the first-number view found

The same: the whole-tail count for the ModelIO differential is 42, grouped at the end of this file, and this table is what the first-number view saw.

| group | n | what the two sides say | whose |
| --- | --- | --- | --- |
| the generator tessellation | 2 | the ellipsoid's 72 vertices against 63 and the cylinder's 47 against 29. The index counts agree, so the surface is the same and the two share vertices differently. | a documented divergence: the header does not say where Apple shares |
| the descriptor of a mesh built from buffers | 1 | 31 attributes on the system, the one given in the port. | Apple's own internal attributes; a port cannot read them |
| the voxel index extent | 1 | the system answers `INT_MAX` for small arrays and zero for larger, the same on every run; the port derives the extent from the box and the voxel size. | a named divergence, the system's answer carrying no information about the division |
| the union over such an array | 1 | follows from the extent: two voxels in the port, three on the system. | follows |

## ModelIO, the one-sided lines, the first-number view

96 of the original 111 were the per-vertex lines of a mesh the two sides built with a different number
of vertices, and they follow from the tessellation row. The rest are the OBJ submesh naming and index
range (the system names a submesh `solid_red` where the port names the two `red` and `lid`), the mesh
and material names an asset takes from its file (the system takes `tri` and `tribin` and `PLY
Material`; the port takes none of them), the `specular` property's type (a float on the system in the
physically plausible function, a colour in the older one in the port), and the clamped-family
equivalents above. **None of them is a port feature the system lacks.**

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

## The count, and what it measures now that the whole tail is compared

    ciimage: 539 measurements, 454 the same, 77 different, 42 one side only (tolerance 0.0005)

`tests/backports/host/modelio/compare.py` used to read only the first number of a line, keyed by the
text in front of it, and count the line as the same whatever followed. Everything after that number -
the pixel tuples, the checksums, the extents, the bounds - was never compared, and the count above
was `551 measurements, 525 the same, 17 different, 42 one side only`, which said "17 different" about
a tree that had five whole families of them wrong. The measurement is now the first number **and the
rest of the line**.

The old comparator on a green pair - the host's own answers against a copy of themselves with 140
pixel tuples and one checksum changed after the first number - reported
`551 measurements, 551 the same, 0 different, 0 one side only`, exit 0. The new one on the same pair
reports `551 measurements, 410 the same, 141 different, 0 one side only`, exit 1. That gap is what the
count was not seeing.

### The 77, grouped, and what each group is

Every one of them is a measurement of the port: the port process is the framework's own CoreImage
with the port's categories on it, and `run.sh:69-72` refuses a port probe that is not the port.

| group | n | what it is | whose to fix |
| --- | --- | --- | --- |
| `shape` | 28 | `CIFilterShape` under a transform and a crop: the host's bounds of a rotated rectangle and the port's differ by about a pixel, and the pixel counts of the cropped ones follow | ours, or a documented divergence: `CGRectApplyAffineTransform` bounds the four corners, the host appears to bound the edges |
| `alg alpha` | 12 | `-imageBySettingAlphaOneInExtent:`, extent and pixels: the host sets the alpha to one and keeps the colour, the port's blend-and-colour-matrix gives a different picture | ours |
| `alg intermediate` | 10 | both spellings of `-imageByInsertingIntermediate`, off by one unit in the green channel of every pixel | ours |
| `alg clamped` | 8 | `-imageByClampingToExtent` and `-imageByClampingToRect:`: the host's clamped image is the infinite extent and its 96 bytes, the port's is `0 0 3 2` and 24 | ours |
| `alg transformed` | 5 | the high-quality downsample, off by one or two in two channels | ours, one rounding step |
| `repr` | 4 | the representations: `repr rgba8 png` is `none` on the host and a file on the port, and `repr write png` is 0 against 1 | ours |
| `ctx space` | 2 | the context's working format: the host answers 2056 (`kCIFormatRGBAh`) with a named working colour space, the port 264 (`kCIFormatRGBA8`) | ours, and see `ContextOwner.md` for the two properties that are not carried at all |
| `color` | 6 | the named colours: three components off by one unit on some of the ten | ours |
| `imp` | 1 | the address of `-imageByClampingToExtent`: the framework's in the host process, the port's in the port's. The label says which, and that it is the port is the point | not a difference at all: an address cannot be equal across two processes, and the line is here so a reader sees that |
| `odd set` | 1 | an accumulator of a fractional extent, `1.5 -2.25 5.5 3.5`: the system writes nothing into it (`60 f6009964`, four pixels `0 0 0 0`) and the port writes the whole-pixel part of the rectangle it is given | ours, and named in `ImageAccumulator.md` |

Three of these were bugs in the port and are fixed, with the numbers in the commits that fixed them:
the accumulator wrote nothing at all (`075f0d2f5`), the premultiply was a grey image of the alpha
(`d255cf714`), and the whole family of 4x4 matrices was built by a braced initialiser that is not an
initialiser (`6c0b43d89`).

### What the 42 one-sided lines are

42 of them, and they are measurements the host cannot be asked, not disagreements: the names each
process gives itself, the lines over a format the framework's own accumulator does not accept, and
the per-pixel lines of the clamped family, whose extent differs and so whose line count does too. The
old count said 44; the two that left are the premultiply's four pixels, gone with the row.

### The ModelIO differential, on the same comparator

    modelio: 317 measurements, 263 the same, 42 different, 55 one side only (tolerance 0.0005)

against `300 the same, 5 different` with the old one, which read only the first number. The 42 are the
generators' index counts under a transform (the host shares a vertex where the port does not), the
voxel array's index extent, the meshes' bounds, and `+canImportFileExtension:` for `usd`, which the
host answers YES and the port NO. The transform stack's four matrix columns, which the old comparator
called the same because the first number is 0 either way, are equal now - `6c0b43d89` carries that.

`tests/backports/host/modelio/run.sh` defaulted its tolerance in `d915b4927`; before that the
differential could not be run as shipped.
