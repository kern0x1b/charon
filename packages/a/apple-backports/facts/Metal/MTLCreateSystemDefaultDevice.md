# The default Metal device, iOS 8.0

`MTLCreateSystemDefaultDevice()` came in iOS 8.0 with Metal. It answers the device an
application draws with, and nil when the hardware has none; an application that offers
Metal with OpenGL ES behind it asks first, and takes the OpenGL ES path on nil.

Source: Metal of the arm64 shared cache of iOS 12.0 - `_MTLCreateSystemDefaultDevice` at
`0x183053fa8`, which runs a routine at `0x183054090` once, and answers the device the routine
leaves in a list it keeps.

## What it is

The list is filled once, from the graphics drivers of the machine, and the function answers
its first entry, or nil while the list is empty. Which driver puts a device on the list was not
read here; Metal runs on the graphics of the A7 and later, and the iPhone 4S and the iPad 2 that
run iOS 6 have the A5.

## Where iOS 6 differs

There is no Metal driver in iOS 6 and no graphics that would have one, so the list is empty
and the function answers nil, as it does on a device of iOS 8 or later that Metal does not
support. The rest of Metal is absent: no protocol, class or constant is there, and the
framework has no device to make them with. MetalKit is absent with it, and an application that
asks for a device and gets nil never makes a `MTKView`. The rows are in `registry/Metal/` and
`registry/MetalKit/`.
