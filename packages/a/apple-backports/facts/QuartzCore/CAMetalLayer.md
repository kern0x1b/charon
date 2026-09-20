# The Metal layer, iOS 8.0

`CAMetalLayer` came in iOS 8.0: a layer that hands out textures to draw into with Metal, `nextDrawable` at a time. An
application makes one as the layer of a view, gives it the device `MTLCreateSystemDefaultDevice()` answered, and
asks it for a drawable each frame.

Source: QuartzCore of the arm64 shared cache of iOS 12.0 - the method list of `CAMetalLayer`, and
`-[CAMetalLayer setMaximumDrawableCount:]` at `0x18549a2b8`, with the exception it raises: name
`CAMetalLayerInvalidMaximumDrawableCount` and reason `failed trying to set maximumDrawableCount to %lu outside of the valid range of [2, 3]`;
the defaults are the ones the header of iOS 16.4 documents, and were not read from the cache.

## What it is

A `CALayer` that keeps a device, a pixel format (BGRA8 unless told, `MTLPixelFormatBGRA8Unorm`), whether it is for the framebuffer only
(yes), a drawable size (the size of its bounds in pixels until it is set), whether it presents with the transaction (no), a
colour space, whether `nextDrawable` may time out (yes), a maximum of drawables (3, 2 or 3 allowed), and answers a drawable for each
`nextDrawable`.

## Where iOS 6 differs

There is no Metal and no device, so a layer of this package holds what it is given and never has a drawable: `nextDrawable` answers
`nil`, as the header says it does when no drawable is available, and an application that checks for one falls back to the
OpenGL ES path it has. `preferredDevice` is `nil`. What is held is held as given, and setting a device that is `nil` is what an application
that asked `MTLCreateSystemDefaultDevice()` and got `nil` does. The maximum of drawables raises the exception of iOS 12 for a value
outside 2 to 3. The properties of iOS 16 (`wantsExtendedDynamicRangeContent`, `EDRMetadata`, `developerHUDProperties`) are declared dynamic,
as a layer's properties are, and the release's `CALayer` gives such a property an accessor that keeps the value, so they are kept and used for
nothing; the class `CAEDRMetadata` that would fill the second is absent.
