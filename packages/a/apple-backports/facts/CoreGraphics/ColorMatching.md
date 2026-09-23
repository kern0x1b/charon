# CGColorCreateCopyByMatchingToColorSpace, iOS 9.0

Rank 28 of `coordination/corpus/band-frameworks.tsv`, `LOAD-FAIL` for telegram and utm. The armv7 cache
ladder first exports the function at 9.0. The registry had it `absent` because "the function arrived
in iOS 9, and nothing in iOS 6 has what it names" - the reason `COORDINATION.md` section 2 forbids, and
wrong: CoreGraphics exports `CGColorTransformCreate`, `CGColorTransformConvertColor` and
`CGColorTransformRelease` from 3.1.3 on (the ladder), without a header. Retracted.

## What the port does

It asks the release's own transform: `CGColorTransformCreate(space, options)`, then
`CGColorTransformConvertColor(transform, color, intent)`, whose result the caller owns. Before that:

- a `NULL` space or colour, or a pattern space on either side, answers `NULL`;
- a colour whose space is equal (`CFEqual`) to a calibrated target space comes back itself, retained;
  a colour in a device space is converted even to the same device space.

Both rules and every converted component are the host's: `tests/backports/host/cgmatch` puts 400
colours of device grey, RGB, CMYK and sRGB to seven targets (device grey, RGB, CMYK, sRGB, generic
grey, Display P3, linear sRGB) with random intents, and the port equals the host's own function
component for component, in model and in retain count: 2803 checks, 0 different. On the host the
private transform itself gives the same components as the public function for every target tried.

## On the device

A daemon on an iPad 2 running 6.1.3, 24 checks, 0 failures (`.agent-work` probe `cgmatch`), calls the
private functions with the port's signature: the transform to device grey exists, the converted
colour is grey, owned by the caller (retain count 1), keeps its alpha, and its grey is the release's
own pixel grey for the same colour drawn into a one-pixel device grey bitmap, within one byte. The
greys are 0.30, 0.59 and 0.11 for red, green and blue, the luma weights 6.1.3's CoreGraphics uses for
device colours (see `facts/UIKit/UIViewTintColor.md`), not the 0.509, 0.863 and 0.273 a later release's
colour management gives: the port answers what this release's CoreGraphics does, not an imitation of
a later one. A device RGB colour goes to device CMYK as `1 - rgb` with black 0 for the primaries.
The public function itself was not run on the device; the calls it makes were.
