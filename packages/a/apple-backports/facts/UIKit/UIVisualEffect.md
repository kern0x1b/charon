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

## What the port does for the blur

The release has no pass in the render server that blurs what lies behind a layer, so a view with a blur effect makes the picture itself.
Each time it is due, the view hides itself and every layer drawn above it (the later siblings of it and of each of its superviews' layers, and those
with a greater `zPosition`), draws the layers of its window into a bitmap a quarter of the size of the area behind it (the area of the view, grown by the
blur radius, read in the view's own coordinates so that a transform above it does not shift the picture), shows them again, blurs the bitmap with three passes of a box filter whose width is the one the ImageEffects sample of
iOS 7 uses for a Gaussian of the style's radius, raises its saturation, mixes the style's tint over it and gives it to a layer under the content view,
cut to the size of the view and stretched smoothly to it. A picture that has not changed since the last one is not blurred again.

The styles are those of the ImageEffects sample: extra light (radius 20, near-white tint at 0.82, saturation 1.8), light (radius 30, white at 0.3, saturation
1.8) and dark (radius 20, near-black at 0.73, saturation 1.8); the light tint of 0.3 is the alpha `_UIBackdropViewSettingsLight` sets in UIKitCore of iOS 12.0
(`0x1ad2c310c`), and the other values are the sample's, which was not compared with the newer release. The regular and prominent styles of iOS 10 are drawn as
light and extra light, and the materials of iOS 13 as light or dark by their name, which is an approximation and not what those releases draw.

It is taken when the view first has a window, when its size or its effect changes, and by a timer of ten times a second that waits three times as long as a
picture took, and half a second when nothing behind has changed, and that stops when the view leaves its window, is hidden or clear, or the application is in
the background. On the iPhone 4S the picture of a view the width of the screen took under a millisecond to take when nothing had changed, and the test holds
a refresh to a quarter of a second.

## What it cannot do

The blur is not live: what moves behind the view is followed a few times a second, not on every frame, and a fast animation shows the blur late. What the
window draws with OpenGL ES is not in a layer's bitmap, so an application that blurs a game or a video drawn that way blurs whatever else is under it, not the
picture. The blur is the port's, made by a box filter, and not the render server's Gaussian filter, so its edges and its saturation differ from the system's.
Vibrancy is not carried: the views in the content view of a vibrancy effect are drawn as they are.

Every frame is not within reach on the iPad 2 (6.1.3, 768 x 1024, scale 1; the port's `CharonBackdrop`, `CharonBlur` and `CharonSheetShadow` compiled into a probe, one
refresh called from a display link at 60 Hz over a scroll view of 100 labels that moved by 7 points a frame, 149 frames each; the probe, `cost.m`, its `build.sh` and its log, `ipad2.log`, are kept in
`charon/.agent-work/handoffs/2026-09-26-b1314-sheet-17/`). The window's `renderInContext:` alone, with nothing done to the pixels, took 21 ms (mean; p95 22 ms) for the shadow's 620 x 740
region and 31 to 33 ms for one of 768 x 920 or more, so the display link ran at 46, 32 and 30 frames a second before any filter ran. It does not shrink below the cost of
the window itself: a 90 x 36 region at the blur's quarter scale still took 14 ms, 146 x 86 took 24 ms and the whole screen (192 x 256) 63 ms, which is more than the read
of the same screen at scale 1 (33 ms): a reduced context draws the layer tree slower. With the box blur and the picture added, a refresh took 19 ms (320 x 100), 50 ms
(540 x 300) and 172 ms (768 x 1024), 50, 20 and 5.8 frames a second. What the port does now (a refresh at most every 0.1 s, and after three times what the last one
took) is what those costs leave. What would improve it, not measured: reading the whole window once at scale 1 (33 ms whatever the region) and scaling that down, in
place of a reduced context; and even then a read above 16.7 ms alone keeps 60 frames a second out of reach on this device, whatever the filter costs.
The shadow's shading is not part of this: since the client shades off the main thread (`UISheetPresentationController.md`) the display link kept 60, 55 and 55 frames a second
with a shadow refresh running (the read, 3 ms a frame on average, 25.5 to 37.6 ms at p95, is what is left on the main thread). The blur's box filter is still on the main thread.

The system's view has three private subviews (the backdrop, an effect subview and the content view) and the port has one, the content view, and a layer for the
picture, so an application that walks `subviews` of a visual effect view sees fewer. The styles that iOS 10
added (regular and prominent) are accepted and kept; how the newest UIKit archives them is not what iOS 10 does, so
the archive of those two styles is not held to the host.
