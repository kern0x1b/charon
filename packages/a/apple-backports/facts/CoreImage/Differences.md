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

## The two mutations did not go red, and that is not a proof

Flipping one line in each of the two new files - `imageBySettingProperties:` returning the image it was
called on, and the unpremultiply dropping its clamp - left the verdict at exactly `559/534/17/42`, with
`props distinct 1` and `unpre finite 96 07488805` unchanged on both sides. The probe is reading the rows
(lines present in both answers files, and the values agree with the host), so the mutations either did
not reach the built sources or the rows are insensitive to them. I could not determine which in this
pass, and I am not claiming either row is proved: this is the same failure mode as the first
"four mutations still gave 252/252", where the port process was the host. **The next thing to do is to
find out which, before either row is claimed as held.**
