# Visual effects, iOS 8

Introduced in iOS 8: `UIVisualEffectView` mixes what lies behind it with a blur, and `UIBlurEffect` and
`UIVibrancyEffect` say how; `UIVisualEffect` is their common class.

Source: the host's own UIKit, under Mac Catalyst, asked for every answer below, and held against the backport by the
`visualeffect` group of `tests/backports/host/uikit2/run.sh`, which compiles the backport with its names changed and puts
it beside the system's classes.

## What the port does

The three effects are values: `+effectWithStyle:` and `+effectForBlurEffect:` keep the style, two effects of one style
are equal and hash alike, a copy is the same object, and they archive under the keys the system uses
(`UIBlurEffectStyle`, `UIVibrancyEffectBlurStyle`) and come back from an archive.

`UIVisualEffectView` is a view of no size when made with `-initWithEffect:`, with a `contentView` that is its subview,
fills its bounds and resizes with them (flexible width and height, as the system's does), also when the view has no
effect. `effect` answers the object it was given. A subview added to the view itself, with `addSubview:` or any of the
three `insertSubview:` methods, raises `NSInternalInconsistencyException` telling the caller to use `contentView`,
which is what the system does for an application that ignores the documented contract; nothing an application that
follows the contract does raises. A view comes back from an archive with its content view in place.

## What it cannot do

The release has no pass in the render server that blurs what lies behind a layer, and the port draws nothing in its
place: no translucent white or dark fill stands in for the blur, because that would look like an effect and be a
different one. A view with an effect is transparent, and what lies behind it stays sharp. An application that put text
on a blurred bar for legibility gets text over the unblurred picture; the ones that give the bar a background colour
of their own, as most of them do for a device without the effect, are unaffected. That is why the classes are `inert`
and the view's ceiling is stated here.

The system's view has three private subviews (the backdrop, an effect subview and the content view) and the port has
one, the content view, so an application that walks `subviews` of a visual effect view sees fewer. The styles that iOS 10
added (regular and prominent) are accepted and kept; how the newest UIKit archives them is not what iOS 10 does, so
the archive of those two styles is not held to the host.
