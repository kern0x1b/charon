# CIFilterShape, carried for iOS 6

10 rows, `registry/CoreImage/shape9.json`. iOS 6 has no `CIFilterShape`: the 6.1.3 armv7 cache's
selector table has neither `shapeWithRect:` nor `insetByX:Y:`, and the class arrived in iOS 9.

A filter shape is the rectangle a filter is told to work over. Every operation is the same operation on
that rectangle: two shapes intersect where their rectangles do, two take a union that bounds both, an
inset moves each edge in, and a transform either bounds the transformed shape or cuts it back to its
interior — which is what the `interior:` flag asks.

## What the pixel probe measured

`tests/backports/host/ciimage/pixel/`, the same two-process shape as the accumulator's: the port's
classes built under names of their own, the framework's in the same process and never asked. The probe
asks for every pair of three rectangles — one whole, one offset, one at a fractional origin with a
fractional size — through the union, the union with a rectangle, the intersection, the intersection
with a rectangle, two insets and four transforms each with and without the interior, and for each one
prints the shape's extent, the extent of an image cropped to it, and the length and checksum of the
bytes that image renders to.

**`ciimage: 252 measurements, 252 the same, 0 different, 0 one side only`**, at a tolerance of 5e-4.
That is every extent and every rendered pixel, for every operation, matching the framework.

## What the probe found, which the header settles

`-insetByX:Y:` was written as `insetByX:y:` with floating-point amounts. Selectors are case-sensitive
and the header's own signature is `- (CIFilterShape *)insetByX:(int)dx Y:(int)dy`, so the port answered
a selector no caller names and the framework threw on the probe's first inset. The spelling and the
types are the header's now.

`CIFilterShape` conforms to `NSCopying` and `-copyWithZone:` was not there. It is.
