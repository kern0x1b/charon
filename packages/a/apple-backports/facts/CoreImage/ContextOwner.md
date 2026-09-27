# A CIContext with a surface and options, and the unpremultiply, for iOS 6

5 rows, `registry/CoreImage/ctxowner9.json`. `-imageBySamplingNearest` is in
`facts/CoreImage/ImageAlgebra.md` and is not carried; the reason is there.

iOS 6's selector table has `contextWithOptions:`, `contextWithEAGLContext:` and
`contextWithEAGLContext:options:` and **no `contextWithCGContext:` in either spelling**. So the context
here is one of the release's own, made by the release's own method, with the caller's `CGContext` and
the options kept beside it as associated objects — a category cannot add storage to a class the
framework has, and an associated object can, on any object, since iOS 3.1.

The header's drawing method is `drawImage:inRect:fromRect:`, not a bare `drawImage:`; that is the one
replaced, and **beside the replacement is one that leaves a context with no drawing surface alone**, so
a context the port did not give a surface is still drawn by the release.

`-imageByUnpremultiplyingAlpha` has no filter behind it on the release — `CIDivideBlendMode` is absent
from its cache — so the arithmetic is the port's own, over the release's own rendering of the image, and
the result is handed back as a `CIImage` over the port's own accumulator, whose `-image` is a view of
exactly those bytes. A pixel with no alpha is left as it is: a colour of nothing cannot be
unpremultiplied into a colour.

## What the pixel probe measured

`tests/backports/host/ciimage/pixel/`: a context made over a `CGContext` on each side — once with a
named working colour space and once with none — printing the working format and whether a working space
is there, then drawing an image into that context and printing **the bytes the `CGContext` ended up
holding** and four of its pixels. Plus the unpremultiply of a field with an alpha in it, and a
premultiply followed by an unpremultiply, which is the round trip.

**`ciimage: 556 measurements, 556 the same, 0 different, 0 one side only`**, at a tolerance of 5e-4. The
bytes drawn into the context are the same, and so is the unpremultiplied picture.

## Not carried, and why

- **`-imageBySamplingNearest`.** On the release every image is sampled linearly and there is no sampler
  to mark an image with, so nearest sampling is a property of a *later transform* and not of the image.
  The port has nowhere to put the mark, and an identity here would be the same pixels wearing a claim
  they have not earned. The pixel probe shows the two sides agree on the pixels, which is the evidence
  for the statement rather than a substitute for the method.
- Nothing has run on a device or under `xmake emulate`.
