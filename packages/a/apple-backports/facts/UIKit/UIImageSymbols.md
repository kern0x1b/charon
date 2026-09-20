# Symbol images, iOS 13.0: UIImage, UIImageView and the weight functions

Introduced in iOS 13.0: `UIImage` gets a symbol configuration, `-isSymbolImage`, the three `+systemImageNamed:` forms and
`-imageByApplyingSymbolConfiguration:`; `UIImageView` a `preferredSymbolConfiguration`; and two functions turn a font weight into a symbol weight and back.

Source: the host's own UIKit under Mac Catalyst (macOS 27.0), held against the backport by `tests/backports/host/uikit2` (the `symbols` group).

## There are no symbols

iOS 6 has no SF Symbols. `+[UIImage systemImageNamed:]`, `...compatibleWithTraitCollection:` and `...withConfiguration:` answer nil for every name and say so
once in the log; the host answers nil for a name it does not know, for an empty name and for nil, and the port does what it does for all of them. Nothing is drawn
and no bitmap is made up for a name. A later batch could draw a subset of the symbols, and would then answer for those names. So there is never a symbol image on
iOS 6: `-isSymbolImage` (the getter of `symbolImage`) answers NO, and an application that checks the result of `systemImageNamed:` for nil is the one that runs.

## An ordinary image

- `-symbolConfiguration` of an image nobody applied one to is nil, as it is on the host for a bitmap or an empty image.
- `-imageByApplyingSymbolConfiguration:` answers another image of the same bitmap, scale, orientation, animation frames, cap insets, resizing mode, alignment
  insets and rendering mode, whose `symbolConfiguration` is the applied one merged over the image's own, or over the traits alone when it has none; `symbolImage`
  stays NO. Nothing draws by it. With nil it answers the same image when the image has a configuration and a copy without one when it has none, as the host does.
  The host's answer carries the current trait collection, the traits of its idiom, scale, size classes, style, layout direction and content size; the port's is
  `UIScreen.mainScreen.traitCollection`, which has the traits iOS 6 knows, and the applied configuration's own traits win over it in both. A copy loses the flag
  that flips it for a right to left layout, which iOS 6 has no property for.

## UIImageView

`preferredSymbolConfiguration` is nil at first, is kept as given (the object itself, not a copy), is not archived, is not touched by setting the image, and setting
an equal configuration leaves the first in place. It is read by nothing on iOS 6, since only a symbol image is drawn by it.

## The weight functions

`UIImageSymbolWeightForFontWeight` answers `Unspecified` below the float -0.8, and from there one weight for each float boundary of `UIFontWeight` -
-0.8, -0.6, -0.4, 0, 0.23, 0.3, 0.4, 0.56, 0.62 - the last from 0.62 up, infinity and NaN included; a boundary that is the double 0.4 is below the float 0.4, so
it is Semibold. `UIFontWeightForImageSymbolWeight` is the table the other way with 0 for unspecified: 0, -0.8, -0.6, -0.4, 0, 0.23, 0.3, 0.4, 0.56, 0.62.
For a symbol weight from 10 up both answer 0 as the host does; below zero the host reads the memory beside its table and the port answers 0.
