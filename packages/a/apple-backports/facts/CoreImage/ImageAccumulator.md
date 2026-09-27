# CIImageAccumulator, carried for iOS 6

11 rows, `registry/CoreImage/accumulator9.json`.

iOS 6 has no `CIImageAccumulator`: the 6.1.3 armv7 cache's whole selector table has no
`imageAccumulatorWithExtent:format:` and no `setImage:dirtyRect:`. The class arrived in iOS 9.

An accumulator is a piece of memory at an extent and a pixel format, that an image is rendered into
and read back out of. `image` is a `CIImage` over the accumulator's own bytes, so what was set into
them is what comes out; `setImage:` renders over the whole extent, `setImage:dirtyRect:` over the
rectangle that changed and no other, and `clear` empties them. The bytes a format takes a pixel to
are the format's own width, read from the header's declaration of it, and the row of them is the
extent's width in pixels.

## What the two-process probe measured, and what it found

`tests/backports/host/ciimage/pixel/` is the same shape as the ModelIO one: one probe built twice, once
against the framework the host carries and once against the port's own accumulator, each run over the
same script, each writing the extent, the format, the image's extent, and the length and checksum of
the RGBA bytes the image renders to, with four pixels spelled out. The port's copy is built under a
name of its own, because it re-implements a class the framework has; the framework's accumulator is in
that process and is never asked, so the two never touch the same object.

**`ciimage: 93 measurements, 90 the same, 2 different, 2 one side only`, at a tolerance of 5e-4.** The
two one-sided lines are the name each process gives itself.

**Three defects it found on its first run, all fixed.**

  1. **A double release.** The colour space was retained by hand on the way in and released on the way
     out, and under ARC an object ivar is managed already - so it was released twice, and a caller that
     let an accumulator go trapped inside CoreFoundation. The ivar is a strong reference and its
     refcount is not touched.
  2. **The format is normalised, not stored as asked.** The host answers `kCIFormatBGRA8` for an
     `kCIFormatRGBA8` request and for a `kCIFormatBGRA8` one alike, so the bytes are in blue-first order
     whatever the caller asked for. The accumulator stores and reports that, and `setImage:` renders
     the row through CoreGraphics - which hands over red first - and swaps the two outer channels as it
     writes. Storing red-first and reporting it would show the picture with red and blue exchanged.
  3. **The extent is the caller's, whole pixels or not.** The port integralised it; the host answers
     exactly what it was given, and answers the *image* over the whole pixels at the origin, which is
     `0 0 5 3` for an extent of `1.5 -2.25 5.5 3.5`. The accumulator now answers the extent it was
     given and the image over the whole pixels.

**Still different, two measurements, both the same case:** the rendered bytes of the accumulator whose
extent is `1.5 -2.25 5.5 3.5`. The extent, the format, the image's extent, the dirty-rect case, both
byte orders, `clear`, an accumulator nothing was set into and one with a colour space all match exactly.
The two that differ are the pixels, and the cause is the rectangle that is rendered into: the port
integralises the dirty rectangle before rendering and the host does not, so at a fractional origin the
two put the row a different distance down. Named, not guessed at.

## What is not measured, and what is reasoned

- The header does not say which byte order a format the accumulator normalises away from BGRA was asked
  for in, and the probe cannot see it either, because the accumulator answers BGBA for both. That part
  of the contract is unmeasurable through the public surface, and this file says so rather than
  implying the question is settled.
- Nothing here has run on a device or under `xmake emulate`. What that adds is the one thing the host
  cannot answer: that the selectors resolve against the release's own runtime and the port's dylib
  loads beside it.
