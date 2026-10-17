# UIPointerAccessory and the accessories of UIPointerStyle, iOS 15

`UIPointerAccessory` (iOS 15) is a shape drawn beside the pointer, at a position given by `UIPointerAccessoryPosition` (an offset and an
angle, with the constants and `UIPointerAccessoryPositionMake`). `UIPointerStyle.accessories` (iOS 15) is the array of them a style
shows. Up to four are supported by the system; the port does not draw them.

## What the port stores

- `+accessoryWithShape:position:` copies the shape, as the host does; the shape is not the object given, and the position is the one
  given.
- `orientationMatchesAngle` is NO for a custom accessory and keeps the value set.
- A copy keeps the shape and the position, but **not** the orientation, which is NO in the copy. The host's copy does the same.
- `UIPointerStyle.accessories` is nil by default. The array is copied on set, so a change to the array given afterwards does not reach
  the style; the accessories inside are the same objects. A copy of the style keeps the accessories.
- Equality of styles does not compare the accessories: this was not measured, and the port keeps equality as it was.

Measured by `tests/backports/host/pointer-accessory` (19 checks; the port's classes and the host's print the same values, and the four
controls fail). The port's class is what the test builds in the port's build, with the CharonPort prefix stripped from the names.

The pointer itself is not drawn with the accessories, and nothing on the port's pointer is placed relative to an accessory. The
`+[UIPointerStyle systemPointerStyle]` class method is a separate row and is not built here.

Source: the host's own UIKit under Mac Catalyst, and the header of SDK 16.4 (`UIPointerAccessory.h`, `UIPointerStyle.h`), iOS 15.0.

## Not built

`+arrowAccessoryWithPosition:` (iOS 15) is declared in the SDK 16.4 header and is not built: the port has no system arrow shape to
give it, and the class has no registry row for the method. A call on the port raises "unrecognized selector". The class's row is
implemented for the members above; this method is the one gap.
