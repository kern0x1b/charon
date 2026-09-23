# UIImage imageByPreparingForDisplay, iOS 15

Source: the SDK 16.4 header of `UIImage.h`, which documents the method as decoding the image's
compressed data ahead of time and handing back a new `UIImage` backed by that decode, so that
later drawing does not pay for decompression; and iOS 6.1.3's own `CGBitmapContextCreate` /
`CGContextDrawImage`, which already do exactly that decode-into-a-bitmap step for any other
purpose a caller asks for it.

## What the port does

Draws the receiver's `CGImage` once into a freshly allocated 8-bit-per-channel ARGB bitmap
context, then reads a new `CGImage` back out of that context with `CGBitmapContextCreateImage`.
Core Graphics has no choice but to fully decode the source image to satisfy the draw, so the
image handed back is backed by raw, already-decoded pixels: drawing it again does not touch the
original compressed source. The new `UIImage` carries the receiver's scale, orientation,
`capInsets`, `alignmentRectInsets`, `renderingMode` and Charon's own baseline association
forward, the same way `UIImage+iOS13.m`'s `charon_image_copy` does for other image-returning
methods in this port. Multi-frame (`images.count > 0`) images are returned unchanged: forcing a
decode of every frame is not this method's contract on the real release either (the header does
not promise it touches animation), and re-encoding an animated image's frame sequence through a
single bitmap context would drop the animation.

## What was reasoned, not measured

No device or emulator run backs this file. The claim that `CGContextDrawImage` forces a full
decode of a compressed source (JPEG/PNG-backed `CGImage`) rather than deferring it again is
Core Graphics' documented behaviour, not something this band watched happen on the 4S or the
iPad 2 - there is no user-visible difference to check for (the API is a performance hint, and its
contract does not promise or forbid any particular before/after timing an external observer
could measure without an internal decode counter). `respondsToSelector:` was not run either.
