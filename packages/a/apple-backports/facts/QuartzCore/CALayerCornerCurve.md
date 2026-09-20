# CALayer.cornerCurve, iOS 13

Introduced in iOS 13: a layer's rounded corner is a circular arc or a continuous curve, the smoother one the system's own
icons have. `kCACornerCurveCircular` and `kCACornerCurveContinuous` name the two, and `CALayer.cornerCurve` holds one.

Source: the host's own QuartzCore, read for the two constants, the default and what a value that is not one of them does,
and compared in `tests/backports/host/uikit2` (`cornercurve`). The shared caches of iOS 6.0 and 7.0 have neither.

## What the port does as the system does

The constants are the strings "circular" and "continuous". A layer answers circular until it is given continuous; a value
that is neither, nil included, makes it circular again, as the system does; the answer is the same through key-value coding.

## What it cannot do

iOS 6 rounds a corner with a circular arc alone, so a layer set to continuous keeps the value and is drawn with circular
corners. The first layer set to continuous says so in the log.
