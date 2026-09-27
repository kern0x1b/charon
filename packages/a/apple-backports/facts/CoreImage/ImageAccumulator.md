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

## What is not measured, and what is reasoned

- **Not measured against the host.** The two-process probe this pass would use is the one at
  `tests/backports/host/modelio/`, and CoreImage needs a different one: both sides render, and the
  rendering has to be compared as pixels. That is not written, so nothing here is held to the host
  yet, and this file says so rather than implying otherwise.
- **Reasoned, not measured**: which byte order a format that is neither `kCIFormatRGBA8` nor
  `kCIFormatBGRA8` is stored in. The header does not say, and the port renders in the order
  CoreGraphics hands over; for the two formats an accumulator is asked for most the two orders are the
  ones the caller named, and for the rest this is a guess that a host differential would settle.
- `clear` writes zeroes over the bytes. What the host does for a format whose zero is not black is
  not known and not claimed.
