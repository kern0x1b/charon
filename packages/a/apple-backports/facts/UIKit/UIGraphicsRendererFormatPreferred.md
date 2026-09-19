# The preferred format and the format for a trait collection, iOS 11.0

iOS 11 added two class factories to the renderer formats: `+preferredFormat`,
on `UIGraphicsRendererFormat` and overridden by `UIGraphicsImageRendererFormat`,
and `+[UIGraphicsImageRendererFormat formatForTraitCollection:]`. iOS 12 added
`preferredRange`. The classes belong to the iOS 10 range, and these members
belong to this one. The two factories are categories that depend on nothing but
the classes' own `+defaultFormat`, `scale` and `prefersExtendedRange`.

Source: UIKit of the arm64 shared cache of iOS 11.0 (iPod7,1 15A372):
- `+[UIGraphicsRendererFormat defaultFormat]` at `0x18a654eb0`;
- `+[UIGraphicsRendererFormat preferredFormat]` at `0x18a654ef4`;
- `+[UIGraphicsImageRendererFormat preferredFormat]` at `0x18a9e88c0`;
- `+[UIGraphicsImageRendererFormat formatForTraitCollection:]` at `0x18a9e88cc`.

The same methods were read in UIKitCore of 12.0 and of 18.0 (arm64e,
`formatForTraitCollection:` at `0x185a8292c`). Behaviour that can be watched
from outside comes from the differential test against the host's UIKit
(`tests/backports/host/rendererformat`).

## The preferred format is the default one

On the base class, `+preferredFormat` is not built from `+defaultFormat`. It is
a second copy of the same body: allocate the receiver, `-init`, and set the
bounds to zero. On the image format, `+preferredFormat` is a single message: it
sends `+defaultFormat` to the receiver and returns what that answers. The two
are the same in 11.0, 12.0 and 18.0.

So the preferred format is not a separate decision. What makes it right for the
screen - the main screen's scale and whether the device can show an extended
range - is decided in `+defaultFormat`, which the iOS 10 range already carries.
On an iPhone 4S or an iPad 2 that means the main screen's scale and no extended
range (`facts/UIKit/UIGraphicsImageRendererFormat.md`). The port's categories
keep both shapes: the base class allocates and initialises the receiver, and
the image format asks its own `+defaultFormat`. A subclass that overrides
`+defaultFormat` therefore sees the same thing it would see on iOS 11.

## The format for a trait collection

- **A nil trait collection is refused.** The release goes to the assertion
  handler, with the reason
  `Invalid parameter not satisfying: traitCollection`. The port raises
  `NSInternalInconsistencyException` with the same reason.
- **The rest starts from the receiver's `+preferredFormat`.**
- **The display scale.** If the magnitude of the trait collection's
  `displayScale` is not below a small threshold, it becomes the format's
  `scale`; otherwise the preferred format's scale stays. The threshold is
  where the releases differ. In 11.0 it is `FLT_EPSILON` (the double
  `0x3E80000000000000` at `0x18ad101e0`). In 18.0 it is `DBL_EPSILON` (built in
  place as `0x3CB0000000000000`). The host agrees with 18.0: a display scale of
  `1e-9` becomes the format's scale, and `1e-17` does not. This package carries
  the newest behaviour, so the port uses `DBL_EPSILON`.
- **A negative scale is taken as it is.** The comparison reads the magnitude, so
  `-2` becomes the format's scale on the host and in the port alike.
- **The display gamut.** If it is `UIDisplayGamutUnspecified`, the preferred
  format's `prefersExtendedRange` stays. Otherwise `prefersExtendedRange`
  becomes whether the gamut is anything but `UIDisplayGamutSRGB` - that is, YES
  for P3.
- Nothing else is read. `opaque` and the bounds are those of the preferred
  format.

A trait collection that says nothing about the display - an empty one, or one
with only a size class - has a display scale of zero and an unspecified gamut.
It gives the preferred format unchanged.

On an iPhone 4S or an iPad 2 no trait collection the system builds carries P3.
If an application builds one, the format stores `prefersExtendedRange` YES as
the release would. What the renderer then draws is the iOS 10 range's business,
and it draws sRGB (see below).

## Why `preferredRange` is not carried

`preferredRange` (iOS 12) chooses the colour range a bitmap is drawn in:
standard, extended or automatic. The owner of the class read the exports of
CoreGraphics of iOS 6.0. No exported name holds `Extended`, and the colour
spaces it knows are sRGB, generic RGB and its linear form, Adobe RGB 1998,
display RGB, generic grey and grey at gamma 2.2, CMYK and the calibrated and
user forms - no extended sRGB and no other space of extended range. The context
this port builds is always sRGB. The property could only hold a value nobody
would ever read. Standard would be true, but extended and automatic would be a
promise the hardware cannot keep. So the property is not there, and
`respondsToSelector:` answers NO.

## How far this is checked

`tests/backports/host/rendererformat` holds the port to the host's UIKit, 18
checks:
- both preferred formats and the default one;
- a nil trait collection;
- an empty one;
- scales of 3, 1, 0, `1e-9`, `1e-17` and -2;
- each gamut;
- scale and gamut together;
- a collection with nothing about the display.
