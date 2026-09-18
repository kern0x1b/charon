# The tint colour of a view, iOS 7

Source: the host's own UIKit, measured beside the backport, and the `tint` group of
`tests/backports/host/uikit2/run.sh`, which holds the two to the same answers.

## What is inherited and what is told

A view with no colour of its own answers its superview's, all the way up. Setting a colour on a view
reaches every view below it that has none of its own and stops at one that has: that view keeps its
colour and is not told about the change. Clearing a colour - setting nil - puts the view back to
inheriting. `-tintColorDidChange` is sent to every view the change reaches, once, and to none of the
others.

`tintAdjustmentMode` is `Automatic` on a fresh view and answers `Normal` where nothing above it is
dimmed. Setting it to `Dimmed` reaches the views below the same way a colour does, and does not reach the
superview. While a view is dimmed its tint colour is the dimmed one; when the dimming stops the colour
comes back unchanged, because dimming is not stored - it is applied to whatever colour is inherited.

## What dimming does to a colour

The dimmed colour is the colour converted to grey and made four fifths as opaque. The conversion is not a
formula of our own: it is what CoreGraphics does when the colour is matched to the device's grey colour
space, which is why red comes out at 0.509, green at 0.863 and blue at 0.273 rather than at the 0.299,
0.587 and 0.114 of a luma weighting. Below iOS 9 there is no
`CGColorCreateCopyByMatchingToColorSpace`, so the backport asks for the same conversion the way the
release can: it fills one pixel of a device-grey bitmap with the colour and reads the byte. The
difference from the system's answer is that byte's rounding - at most 1/255, and the test holds it to
that. The alpha is multiplied by 0.8: an opaque colour dims to 0.8, a colour at 0.5 to 0.4.

## The one number that is not read from a release

The colour a view answers when nothing above it sets one is `(0, 122/255, 1)`, the blue of iOS 7, and
that number is the only thing in this file that is not read from an implementation. The host cannot give
it: Mac Catalyst answers the Mac's own accent colour, `(0, 0.533, 1)` on the machine this was measured on,
and so does `+[UIColor systemBlueColor]` there. iOS 7's own UIKit does not carry it as a literal either -
neither the float nor the double form of 122/255 appears anywhere in its armv7s image, so it is built
rather than stored. It is written down here so that nobody reads the number back out of our code as
though it had been measured.
