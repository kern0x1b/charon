# CarPlay on iOS 6: the measurement pass, and what it decides

`apple.objc.inventory` against the armv7 dyld shared cache of **6.1.3**: **no CarPlay class of any
name is in the release.** `CPInterfaceController`, `CPInterfaceControllerDelegate`,
`CPWindow` and every template class are absent -- the framework is not in this release at all, as the
ledger's own reasons already say for all 74 of its classes.

`apple.dyld`'s `first_releases` over the held cache ladder, for the 74 classes the SDK 26.2 declares
and this port does not have:

| first held release that exports it | classes |
| --- | --- |
| 12.0 | 25 |
| 16.0 | 35 |
| 18.0 | 1 |
| not in any held release | 13 |

So the CarPlay surface splits into three objects by measured release, and nothing here is a copy of
anything: the framework is Apple's and there is no open implementation of it to port.

## What the wall is, and where it is

**The wall is the head unit, and it is Apple's, not this port's.** A CarPlay scene is a connection to
a car: without a car there is no scene, which is Apple's own behaviour without a car and not a
limitation of the port. That is the honest seam, and it is one seam with two halves:

- **Everything the templates need is implementable in-app.** The ruling and this file agree: the
  list, grid, map and now-playing templates are ordinary view controllers, and a
  `CPInterfaceController` equivalent is an object with a content window of the port's own that pushes
  and pops template view controllers, keeps the tab bar and the now-playing bar, and answers the
  delegate. None of that needs a car. So the templates and the interface controller are `implemented`
  and run in an application.
- **The scene connection is not implementable.** `CPScene`/`CPInterfaceController`'s connection to a
  car is a system service no program on this device can stand in for, so the scene is refused exactly
  as Apple refuses it without a car, and every CarPlay-specific affordance that depends on the car
  (the templates' car-specific layout, the car's input, the vehicle status) answers the way Apple
  answers it. That half is `documented-absent` at the seam, per COORDINATION §2: the API surface
  exists, everything not depending on the wall is implemented, and the refusal happens only where the
  wall is.

## What this decides, per family

- **`CPInterfaceController` and the four templates** (list, grid, map, now-playing) plus the
  supporting classes: `implemented`, as in-app view controllers over the port's own content window.
  A host differential is impossible for most of it (macOS has no CarPlay templates), so the emulator
  call test at 6.1.3 is the check, as it is for the MapKit renderers.
- **The car-dependent surface**: `inert` or `absent` per class, each with the measurement that the
  release has no CarPlay at all and the reason the class depends on a car that is not there.
- **The scene**: the connection refused, and `status` `absent` for the classes that *are* the
  connection, with the effect naming what a caller gets.

One thing this pass settles before any code is written, and it is the same shape as the MapKit
`MKMapItem` correction: **the wallet half of PassKit is the release's own**, so that half is not a
backport at all. See `facts/PassKit/PassKit.md`.
