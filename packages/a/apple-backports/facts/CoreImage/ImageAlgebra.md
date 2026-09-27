# CIImage's algebra, carried for iOS 6

19 rows, `registry/CoreImage/algebra10.json`.

iOS 6 has the filters this is made of and not the operation. Read out of the release's own 6.1.3 cache:
`CIAffineClamp`, `CIAffineTransform`, `CIColorMatrix`, `CIMultiplyBlendMode`, `CIGaussianBlur`,
`CISourceOverCompositing`, `CICrop`, `CIConstantColorGenerator`, `CIMaskToAlpha` and
`CILanczosScaleTransform` are all there, and `CIDivideBlendMode`, `CIPremultiplyAlpha`,
`CIUnpremultiplyAlpha`, `CIIdentity`, `CIInsertIntermediate` and `CIRenderDestination` are all absent.
So each of these is the release's own filter composed into the operation, and the composition is the
whole of it.

`-imageByInsertingIntermediate:` takes a **BOOL cache flag**, not a filter name, and the header's
spelling is what the port answers.

## What the pixel probe measured

`tests/backports/host/ciimage/pixel/`: a field with an alpha in it, and from it the blur at a sigma, the
clamp to the extent and to a rectangle, both spellings of the intermediate, the premultiply, the alpha
set to one over the whole extent and over half of it, the transform with and without the high-quality
flag, the properties, and all ten constant colour images. For each, the extent of what comes out and
the bytes it renders to.

**`ciimage: 530 measurements, 530 the same, 0 different, 0 one side only`**, at a tolerance of 5e-4.

## Not carried, and why - read the release's own selector table

- **`+[CIContext contextWithCGContext:options:]`.** Checked rather than assumed: the 6.1.3 selector
  table has `contextWithOptions:`, `contextWithEAGLContext:` and `contextWithEAGLContext:options:`, and
  **no `contextWithCGContext:` at all**, in either spelling. There is nothing on the release for it to
  extend. Carrying it means a context of the port's own that draws into a `CGContext`: a bitmap render
  and a draw per call, and a real question of what drawing means for a context asked to draw the same
  image twice.
- **`-imageByUnpremultiplyingAlpha`** needs a filter that divides by alpha, and the release has none:
  `CIDivideBlendMode` is absent from its cache. The one honest path is through the port's own
  accumulator, dividing the bytes per pixel, and that is not written yet.
- **`-imageBySamplingNearest`** needs a nearest sampler; the release samples linearly and has no other
  sampling to leave. `facts/CoreImage/Compositing.md` already records that for the method of the same
  name that is carried.
- **`workingColorSpace` and `workingFormat`** answer what a context was made with, which means
  remembering the options - and a category cannot add storage to a class the framework has, so this needs
  a subclass of the port's own, with the same consequence for a context the release made itself.
- Nothing has run on a device or under `xmake emulate`.
