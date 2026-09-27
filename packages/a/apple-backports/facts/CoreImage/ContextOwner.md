# A CIContext with a surface and options, and the unpremultiply, for iOS 6

3 rows, `registry/CoreImage/ctxowner9.json`. `-imageBySamplingNearest` is in
`facts/CoreImage/ImageAlgebra.md` and is not carried; the reason is there.

iOS 6's selector table has `contextWithOptions:`, `contextWithEAGLContext:` and
`contextWithEAGLContext:options:` and **no `contextWithCGContext:` in either spelling**. So the context
here is one of the release's own, made by the release's own method, with the caller's `CGContext` and
the options kept beside it as associated objects — a category cannot add storage to a class the
framework has, and an associated object can, on any object, since iOS 3.1.

The header's drawing method is `drawImage:inRect:fromRect:`, not a bare `drawImage:`; that is the one
replaced, and **beside the replacement is one that leaves a context with no drawing surface alone**, so
a context the port did not give a surface is still drawn by the release.

**`-imageByUnpremultiplyingAlpha` is not carried, and the reason is measured, not reasoned.** The
port carried it as a category on `CIImage` that rendered the image, divided each channel by the alpha it
is multiplied by, and handed the bytes back through the accumulator. Built with
`-fsanitize=address` and run, the port's own probe reports a **stack overflow with the recursion in
full**:

```
#11 CharonCIKernelOver CIImageCPUKernel.m:32
#12 -[CIImage(CharonCPUKernel) imageByUnpremultiplyingAlpha] CIImageCPUKernel.m:50
#15 -[CIContext render:toBitmap:rowBytes:bounds:format:colorSpace:]
#16 CharonCIKernelOver CIImageCPUKernel.m:34
#17 -[CIImage(CharonCPUKernel) imageByUnpremultiplyingAlpha] CIImageCPUKernel.m:50
```

`-imageByUnpremultiplyingAlpha` is not only a public convenience: **the framework calls it itself**,
unpremultiplying internally on the way to a non-premultiplied target. A category answering that
selector replaces the framework's own step, so the renderer calls the port's kernel, which renders,
which unpremultiplies again. The same mistake as answering `workingColorSpace` from a category, found
the same way: a category that replaces a method the framework itself calls.

Carrying it would need the division to happen somewhere other than that selector — a filter the release
has, which there is not (`CIDivideBlendMode` is absent from its cache), or a port renderer of its own
below CoreImage, which is a much larger piece and is not begun. The row stays named. The same reasoning
is why `-imageBySamplingNearest` is not carried: the release has no sampler to mark an image with.

## What the pixel probe measures

`tests/backports/host/ciimage/pixel/`: a context made over a `CGContext` on each side — once with a
named working colour space and once with none — printing the working format and whether a working space
is there, then drawing an image into that context and printing **the bytes the `CGContext` ended up
holding** and four of its pixels.

the CoreImage differential is re-measured after this pass and its verdict line is in the delivery, at a tolerance of 5e-4. The
bytes drawn into the context are the same, and so is the unpremultiplied picture.

## Not carried, and why

- **`-imageBySamplingNearest`.** On the release every image is sampled linearly and there is no sampler
  to mark an image with, so nearest sampling is a property of a *later transform* and not of the image.
  The port has nowhere to put the mark, and an identity here would be the same pixels wearing a claim
  they have not earned. The pixel probe shows the two sides agree on the pixels, which is the evidence
  for the statement rather than a substitute for the method.
- Nothing has run on a device or under `xmake emulate`.
